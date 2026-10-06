import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:macgram/canvas.dart';
import 'package:macgram/controller.dart';
import 'package:macgram/main.dart';
import 'package:macgram/mld.dart';
import 'package:macgram/model.dart';
import 'package:macgram/scene.dart';

/// Client -0,n- passe -1,1- Commande ; Ligne is weak under Commande ;
/// Ligne -0,n- concerne(quantite) -0,n- Produit ; Commande.statut is an enum.
Document sample() {
  final d = Document()
    ..enums.add(EnumType(id: 't-1', name: 'Statut', values: ['ouverte', 'payee']))
    ..entities.addAll([
      Entity(id: 'e-cli', name: 'Client', attributes: [
        Attribute(name: 'id', type: 'int', isId: true),
        Attribute(name: 'nom', nullable: true),
      ]),
      Entity(id: 'e-cmd', name: 'Commande', attributes: [
        Attribute(name: 'id', type: 'int', isId: true),
        Attribute(name: 'statut', type: 'enum:t-1'),
      ]),
      Entity(id: 'e-lig', name: 'Ligne', attributes: [Attribute(name: 'numero', type: 'int', isId: true)]),
      Entity(id: 'e-pro', name: 'Produit', attributes: [Attribute(name: 'ref', isId: true)]),
    ])
    ..associations.addAll([
      Association(id: 'a-1', name: 'passe', legs: [Leg('e-cli'), Leg('e-cmd', card: '1,1')]),
      Association(id: 'a-2', name: 'contient', legs: [Leg('e-cmd', card: '1,n'), Leg('e-lig', card: '1,1', relative: true)]),
      Association(
        id: 'a-3',
        name: 'concerne',
        attributes: [Attribute(name: 'quantite', type: 'int')],
        legs: [Leg('e-lig'), Leg('e-pro')],
      ),
    ])
    ..notes.add(Note(id: 'n-1', text: 'a < b & c'))
    ..arrows.add(Arrow(id: 'r-1', from: 'n-1', to: 'e-cli', label: 'voir'));
  return d..prune();
}

void main() {
  test('file format is deterministic, round-trips, and diffs line by line', () {
    final d = sample();
    final text = d.encode();
    expect(Document.decode(text).encode(), text);
    expect(text.endsWith('}\n'), isTrue);
    expect(text, contains('\n        {"name": "nom", "type": "string", "nullable": true}\n'));

    // Insertion order must not leak into the file.
    final shuffled = Document.decode(text);
    shuffled.entities.insert(0, shuffled.entities.removeLast());
    expect(shuffled.encode(), text);

    // Moving a box changes exactly one line.
    final moved = Document.decode(text)..layout['e-cli'] = (120, 40);
    final before = text.split('\n'), after = moved.encode().split('\n');
    expect(after.length, before.length);
    expect([for (var i = 0; i < before.length; i++) if (before[i] != after[i]) after[i]], ['    "e-cli": [120, 40],']);
  });

  test('deleting an entity prunes legs, arrows and layout', () {
    final d = sample()..remove('e-cli');
    expect(d.associations.firstWhere((a) => a.id == 'a-1').legs.length, 1);
    expect(d.arrows, isEmpty);
    expect(d.layout.containsKey('e-cli'), isFalse);
  });

  test('mld', () {
    expect(mld(sample()), '''
enum Statut { ouverte, payee }

Client(_id_: int, nom: string?)
Commande(_id_: int, statut: Statut, #id_client)
Ligne(_numero_: int, _#id_commande_)
Produit(_ref_: string)
concerne(_#numero_ligne_, _#id_commande_ligne_, _#ref_produit_, quantite: int)'''
        .trimLeft());
  });

  test('reflexive association does not recurse forever', () {
    final d = Document()
      ..entities.add(Entity(id: 'e-1', name: 'Employe'))
      ..associations.add(Association(id: 'a-1', name: 'dirige', legs: [Leg('e-1', card: '0,1'), Leg('e-1')]));
    expect(mld(d), 'Employe(_id_: int, #id_employe?)');
    expect(buildScene(d).shapes, isNotEmpty);
  });

  test('scene: both notations render, UML inlines plain binary associations, SVG escapes text', () {
    final d = sample();
    final merise = buildScene(d), uml = buildScene(d, uml: true);
    String texts(Scene s) => s.shapes.whereType<Label>().map((l) => l.text).join(' | ');
    expect(texts(merise), contains('(1,1)'));
    expect(merise.hits.any((h) => h.$1 == 'a-1' && h.$2.width > 60), isTrue);
    expect(texts(uml), contains('1..*'));
    expect(uml.shapes.whereType<Poly>().length, 2); // composition diamond + arrow head
    expect(uml.hit(const Offset(-500, -500)), isNull);
    expect(toSvg(merise), contains('a &lt; b &amp; c'));
  });

  test('controller: link tool, enum shortcut, undo', () {
    final c = Controller();
    c.setTool(Tool.entity);
    c.tap(null, const Offset(100, 100));
    c.setTool(Tool.entity);
    c.tap(null, const Offset(400, 100));
    final [a, b] = c.doc.entities;
    c.setTool(Tool.link);
    c.tap(a.id, Offset.zero);
    c.tap(b.id, Offset.zero);
    expect(c.doc.associations.single.legs.map((l) => l.entityId), [a.id, b.id]);

    c.tap('leg:${c.doc.associations.single.id}:0', Offset.zero);
    expect(c.doc.associations.single.legs[0].card, '1,n');

    final attr = Attribute(name: 'statut', type: 'ouverte|payee');
    c.change(() => a.attributes.add(attr));
    c.normalizeType(attr);
    expect(c.doc.enums.single.values, ['ouverte', 'payee']);
    expect(c.doc.typeName(attr.type), 'Statut');

    c.undo();
    expect(c.doc.enums, isEmpty);
    c.redo();
    expect(c.doc.enums.single.name, 'Statut');
  });

  testWidgets('app: place an entity on the canvas and edit it', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = Controller();
    await tester.pumpWidget(App(c));
    await tester.tap(find.text('Entité'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(DiagramCanvas)));
    await tester.pump();
    expect(c.doc.entities.length, 1);
    expect(c.selected, c.doc.entities.single.id);
    await tester.enterText(find.widgetWithText(TextFormField, 'Entite'), 'Client');
    expect(c.doc.entities.single.name, 'Client');
    expect(c.dirty, isTrue);
  });
}
