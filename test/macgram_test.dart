import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    ..enums.add(
      EnumType(id: 't-1', name: 'Statut', values: ['ouverte', 'payee']),
    )
    ..entities.addAll([
      Entity(
        id: 'e-cli',
        name: 'Client',
        attributes: [
          Attribute(name: 'id', type: 'int', isId: true),
          Attribute(name: 'nom', nullable: true),
        ],
      ),
      Entity(
        id: 'e-cmd',
        name: 'Commande',
        attributes: [
          Attribute(name: 'id', type: 'int', isId: true),
          Attribute(name: 'statut', type: 'enum:t-1'),
        ],
      ),
      Entity(
        id: 'e-lig',
        name: 'Ligne',
        attributes: [Attribute(name: 'numero', type: 'int', isId: true)],
      ),
      Entity(
        id: 'e-pro',
        name: 'Produit',
        attributes: [Attribute(name: 'ref', isId: true)],
      ),
    ])
    ..associations.addAll([
      Association(
        id: 'a-1',
        name: 'passe',
        legs: [
          Leg('e-cli'),
          Leg('e-cmd', card: '1,1'),
        ],
      ),
      Association(
        id: 'a-2',
        name: 'contient',
        legs: [
          Leg('e-cmd', card: '1,n'),
          Leg('e-lig', card: '1,1', relative: true),
        ],
      ),
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
    expect(
      text,
      contains(
        '\n        {"name": "nom", "type": "string", "nullable": true}\n',
      ),
    );

    // Insertion order must not leak into the file.
    final shuffled = Document.decode(text);
    shuffled.entities.insert(0, shuffled.entities.removeLast());
    expect(shuffled.encode(), text);

    // Moving a box changes exactly one line.
    final moved = Document.decode(text)..layout['e-cli'] = (120, 40);
    final before = text.split('\n'), after = moved.encode().split('\n');
    expect(after.length, before.length);
    expect(
      [
        for (var i = 0; i < before.length; i++)
          if (before[i] != after[i]) after[i],
      ],
      ['    "e-cli": [120, 40],'],
    );
  });

  test('deleting an entity prunes legs, arrows and layout', () {
    final d = sample()..remove('e-cli');
    expect(d.associations.firstWhere((a) => a.id == 'a-1').legs.length, 1);
    expect(d.arrows, isEmpty);
    expect(d.layout.containsKey('e-cli'), isFalse);
  });

  test('mld', () {
    expect(
      mld(sample()),
      '''
enum Statut { ouverte, payee }

Client(_id_: int, nom: string?)
Commande(_id_: int, statut: Statut, #id_client)
Ligne(_numero_: int, _#id_commande_)
Produit(_ref_: string)
concerne(_#numero_ligne_, _#id_commande_ligne_, _#ref_produit_, quantite: int)'''
          .trimLeft(),
    );
  });

  test('reflexive association does not recurse forever', () {
    final d = Document()
      ..entities.add(Entity(id: 'e-1', name: 'Employe'))
      ..associations.add(
        Association(
          id: 'a-1',
          name: 'dirige',
          legs: [
            Leg('e-1', card: '0,1'),
            Leg('e-1'),
          ],
        ),
      );
    expect(mld(d), 'Employe(_id_: int, #id_employe?)');
    expect(buildScene(d).shapes, isNotEmpty);
  });

  test('scene: both notations render, UML inlines plain binary associations, SVG escapes text', () {
    final d = sample();
    final merise = buildScene(d), uml = buildScene(d, uml: true);
    String texts(Scene s) =>
        s.shapes.whereType<Label>().map((l) => l.text).join(' | ');
    expect(texts(merise), contains('(1,1)'));
    expect(merise.hits.any((h) => h.$1 == 'a-1' && h.$2.width > 60), isTrue);
    expect(texts(uml), contains('1..*'));
    // composition diamond + arrow head ; the note's resize grip is an editing handle
    expect(uml.shapes.whereType<Poly>().length, 3);
    expect(
      buildScene(d, uml: true, handles: false).shapes.whereType<Poly>().length,
      2,
    );
    expect(uml.hit(const Offset(-500, -500)), isNull);
    // Enums live in the side panel, not on the canvas.
    expect(merise.hits.any((h) => h.$1 == 't-1'), isFalse);
    expect(toSvg(merise), contains('a &lt; b &amp; c'));
  });

  test(
    'link notes, break points and note size stay one line each in the file',
    () {
      final d = sample();
      d.associations.first.legs[0]
        ..note = 'au moins une'
        ..bends = [(200, 40), (240, 80)];
      d.arrows.single.bends = [(10, 20)];
      d.notes.single.size = (200, 80);
      final text = d.encode();
      expect(Document.decode(text).encode(), text);
      expect(
        text,
        contains(
          '\n        {"entity": "e-cli", "card": "0,n", "note": "au moins une", "bends": [200, 40, 240, 80]},\n',
        ),
      );
      expect(
        text,
        contains(
          '\n    {"id": "n-1", "text": "a < b & c", "size": [200, 80]}\n',
        ),
      );
      expect(
        text,
        contains(
          '\n    {"id": "t-1", "name": "Statut", "values": ["ouverte", "payee"]}\n',
        ),
      );
    },
  );

  test(
    'controller: association tool relates two entities, enum shortcut, undo',
    () {
      final c = Controller();
      c.setTool(Tool.entity);
      c.tap(null, const Offset(100, 100));
      c.setTool(Tool.entity);
      c.tap(null, const Offset(400, 100));
      final [a, b] = c.doc.entities;
      c.setTool(Tool.association);
      c.tap(a.id, Offset.zero);
      expect(c.pending, a.id);
      c.tap(b.id, Offset.zero);
      expect(c.doc.associations.single.legs.map((l) => l.entityId), [
        a.id,
        b.id,
      ]);
      expect(c.tool, Tool.select);

      final attr = Attribute(name: 'statut', type: 'ouverte|payee');
      c.change(() => a.attributes.add(attr));
      c.normalizeType(attr);
      expect(c.doc.enums.single.values, ['ouverte', 'payee']);
      expect(c.doc.typeName(attr.type), 'Statut');

      c.undo();
      expect(c.doc.enums, isEmpty);
      c.redo();
      expect(c.doc.enums.single.name, 'Statut');
    },
  );

  test(
    'right click breaks a link where clicked, and again removes the break',
    () {
      final c = Controller()
        ..doc = (sample()
          ..layout['e-cli'] = (0, 0)
          ..layout['a-1'] = (400, 0)
          ..layout['e-cmd'] = (400, 300));
      Scene scene() => buildScene(c.doc);
      // Somewhere on the Client–passe link, between the two boxes.
      final onLink = scene().segs.firstWhere((s) => s.$1 == 'seg|leg:a-1:0|0');
      final p = (onLink.$2 + onLink.$3) / 2;
      expect(scene().hit(p), 'seg|leg:a-1:0|0');
      expect(scene().hit(p + const Offset(0, 40)), isNull);

      c.toggleBend('seg|leg:a-1:0|0', p + const Offset(0, 60));
      final bend = c.doc.associations
          .firstWhere((a) => a.id == 'a-1')
          .legs[0]
          .bends;
      expect(bend.length, 1);
      final at = Offset(bend[0].$1.toDouble(), bend[0].$2.toDouble());
      expect(scene().hit(at), 'bend|leg:a-1:0|0');
      expect(scene().hit(p), isNull); // the straight line is gone

      c.moveBend('bend|leg:a-1:0|0', at + const Offset(30, 0));
      expect(bend[0].$1, at.dx + 30);
      c.toggleBend('bend|leg:a-1:0|0', Offset.zero);
      expect(bend, isEmpty);
    },
  );

  test('a resized note wraps its text and never clips it', () {
    final d = Document()
      ..notes.add(
        Note(id: 'n-1', text: 'un deux trois quatre cinq six', size: (100, 10)),
      );
    d.prune();
    final s = buildScene(d);
    final rect = s.hits.firstWhere((h) => h.$1 == 'n-1').$2;
    final lines = s.shapes.whereType<Label>().length;
    expect(rect.width, 100);
    expect(lines, greaterThan(2));
    expect(rect.height, greaterThanOrEqualTo(lines * rowH));
    expect(s.hit(rect.bottomRight - const Offset(4, 4)), 'resize|n-1');
  });

  test(
    'export holds everything: bent arrows far outside the boxes, and the enums',
    () {
      final d = sample();
      d.arrows.single.bends = [(-900, -700)];
      final s = buildScene(d, handles: false, legend: true, pal: Palette.dark);
      expect(s.bounds.contains(const Offset(-900, -700)), isTrue);
      final enumBox = s.hits.firstWhere((h) => h.$1 == 't-1').$2;
      expect(s.bounds.contains(enumBox.bottomRight), isTrue);
      // The legend sits clear of the diagram, to its right.
      expect(
        s.hits
            .where((h) => h.$1 != 't-1')
            .every((h) => h.$2.right < enumBox.left),
        isTrue,
      );
      final svg = toSvg(s);
      expect(svg, contains('payee'));
      expect(svg, contains('fill="#14171c"/>')); // dark canvas background
    },
  );

  test(
    'applyLayout moves the boxes in one undo step and drops break points',
    () {
      final c = Controller()..doc = sample();
      final leg = c.doc.associations.first.legs[0]..bends = [(5, 5)];
      final before = c.doc.encode();
      c.applyLayout({'e-cli': (300, 200), 'unknown': (1, 1)});
      expect(c.doc.layout['e-cli'], (300, 200));
      expect(c.doc.layout.containsKey('unknown'), isFalse);
      expect(leg.bends, isEmpty);
      c.undo();
      expect(c.doc.encode(), before);
    },
  );

  Future<Controller> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = Controller();
    await tester.pumpWidget(App(c));
    await tester.tap(find.text('Entité'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(DiagramCanvas)));
    await tester.pump();
    return c;
  }

  testWidgets(
    'double click opens the entity popup; typing, Enter and clicking outside keep everything',
    (tester) async {
      final c = await pumpApp(tester);
      final e = c.doc.entities.single;
      final at = tester.getCenter(find.byType(DiagramCanvas));
      expect(find.byType(Dialog), findsNothing);
      await tester.tapAt(at);
      await tester.pump();
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: 'a single click only selects',
      );
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Entite'),
        'Client',
      );
      // Enter in an attribute row adds the next one, focused.
      await tester.showKeyboard(find.widgetWithText(TextField, 'id'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(e.attributes.length, 2);
      tester.testTextInput.enterText('nom');
      await tester.pump();
      expect(e.attributes[1].name, 'nom');

      // A second Enter leaves a blank row, dropped when the popup closes.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(e.attributes.length, 3);

      await tester.tapAt(const Offset(5, 895)); // outside the popup
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(e.name, 'Client');
      expect(e.attributes.map((a) => a.name), ['id', 'nom']);
    },
  );

  testWidgets('click on a link opens its cardinality popup', (tester) async {
    final c = await pumpApp(tester);
    final e = c.doc.entities.single;
    final a = Association(id: 'a-1', legs: [Leg(e.id)]);
    c.change(() {
      c.doc.associations.add(a);
      c.doc.layout[a.id] = (
        c.doc.layout[e.id]!.$1 + 300,
        c.doc.layout[e.id]!.$2,
      );
    });
    await tester.pump();
    final seg = buildScene(c.doc).segs.single;
    final canvas = tester.getTopLeft(find.byType(DiagramCanvas));
    final onLink = (seg.$2 + seg.$3) / 2;
    await tester.tapAt(canvas + onLink);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('1,1'));
    await tester.pump();
    expect(a.legs.single.card, '1,1');
  });

  testWidgets(
    'unsaved changes can be saved before going on; enums are in the side panel',
    (tester) async {
      final c = await pumpApp(tester); // one unsaved entity
      final file = File(
        '${Directory.systemTemp.createTempSync('macgram').path}/t.mcd.json',
      );
      c.path = file.path;

      await tester.tap(find.byTooltip('Nouvel enum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(c.doc.enums.single.name, 'Enum');
      expect(c.doc.layout.containsKey(c.doc.enums.single.id), isFalse);

      await tester.tap(find.byTooltip('Nouveau'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(c.doc.entities.length, 1, reason: 'cancel keeps the document');

      await tester.tap(find.byTooltip('Nouveau'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final saved = Document.decode(file.readAsStringSync());
      expect(saved.entities.length, 1);
      expect(saved.enums.length, 1);
      expect(c.doc.entities, isEmpty);
    },
  );

  testWidgets(
    'Réarranger: runs in an isolate behind a progress popup, then applies as one undo step',
    (tester) async {
      tester.view.physicalSize = const Size(1900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // A ring of 6 entities, placed so that its links cross.
      final c = Controller();
      final ids = [for (var i = 0; i < 6; i++) 'e-$i'];
      c.doc.entities.addAll([for (final id in ids) Entity(id: id, name: id)]);
      for (var i = 0; i < 6; i++) {
        c.doc.associations.add(
          Association(
            id: 'a-$i',
            legs: [Leg(ids[i]), Leg(ids[(i * 2 + 1) % 6])],
          ),
        );
        c.doc.layout[ids[i]] = (i.isEven ? 100 : 700, 100 + i * 90);
        c.doc.layout['a-$i'] = (400, 100 + ((i * 5) % 6) * 90);
      }
      c.doc.prune();
      final tangled = c.doc.encode();

      await tester.pumpWidget(App(c));
      await tester.tap(find.byTooltip('Réarranger (moins de croisements)'));
      await tester.pump();
      expect(find.text('Réarrangement du schéma'), findsOneWidget);
      // Nothing runs until the spacing is confirmed.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Réarranger'));
      await tester.pump();
      expect(
        c.doc.encode(),
        tangled,
        reason: 'nothing changes while it computes',
      );

      for (
        var i = 0;
        i < 300 && find.text('Réarrangement du schéma').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Réarrangement du schéma'), findsNothing);
      expect(find.textContaining('Schéma réarrangé'), findsOneWidget);
      expect(c.doc.encode(), isNot(tangled));
      c.undo();
      expect(c.doc.encode(), tangled);
    },
  );

  testWidgets(
    'navigation: scroll, Shift+scroll and right-button drag move the view; left drag does not',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = Controller();
      await tester.pumpWidget(App(c));
      final canvas = find.byType(DiagramCanvas);
      final centre = tester.getCenter(canvas),
          local = centre - tester.getTopLeft(canvas);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(centre));

      await tester.sendEventToBinding(
        mouse.scroll(const Offset(0, 100)),
      ); // view goes down 100
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        mouse.scroll(const Offset(0, 50)),
      ); // view goes right 50
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      final right = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.moveBy(
        const Offset(30, 0),
      ); // drags the diagram right: view goes left 30
      await right.up();
      final left = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.mouse,
      );
      await left.moveBy(const Offset(200, 200));
      await left.up();
      await tester.pump();

      // An entity dropped at the centre of the window lands where the view now is.
      await tester.tap(find.text('Entité'));
      await tester.pump();
      await tester.tapAt(centre);
      await tester.pump();
      expect(
        c.doc.layout.values.single,
        Controller.snap(
          local + const Offset(50 - 30, 100) - const Offset(50, 14),
        ),
      );
    },
  );

  testWidgets(
    'rubber band selects the boxes it touches; they move and delete together, Ctrl+A takes all',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = Controller();
      await tester.pumpWidget(App(c));
      final origin = tester.getTopLeft(find.byType(DiagramCanvas));
      for (final at in const [
        Offset(100, 100),
        Offset(300, 100),
        Offset(700, 500),
      ]) {
        c.setTool(Tool.entity);
        c.tap(null, at);
      }
      c.select(null);
      await tester.pump();
      final [a, b, far] = c.doc.entities.map((e) => e.id).toList();

      Future<void> drag(Offset from, Offset by) async {
        final g = await tester.startGesture(
          origin + from,
          kind: PointerDeviceKind.mouse,
        );
        await g.moveBy(by / 2);
        await g.moveBy(by / 2);
        await g.up();
        await tester.pump();
      }

      await drag(const Offset(20, 40), const Offset(400, 200));
      expect(c.group, {a, b});

      final before = Map.of(c.doc.layout);
      await drag(
        const Offset(60, 100),
        const Offset(50, 30),
      ); // grab one of them
      expect(c.doc.layout[a], (before[a]!.$1 + 50, before[a]!.$2 + 30));
      expect(c.doc.layout[b], (before[b]!.$1 + 50, before[b]!.$2 + 30));
      expect(c.doc.layout[far], before[far]);
      c.undo(); // the whole drag is one step
      expect(c.doc.layout, before);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(c.group, {a, b, far});
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(c.doc.entities, isEmpty);
    },
  );
}
