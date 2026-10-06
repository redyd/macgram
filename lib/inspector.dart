import 'package:flutter/material.dart';

import 'controller.dart';
import 'model.dart';

const _help = '''
Rien de sélectionné.

• Entité, Association, Enum, Note : choisir l'outil puis cliquer sur le canevas.
• Lier : cliquer deux éléments.
    entité + association → patte
    entité + entité → nouvelle association
    entité + enum → attribut de ce type
• Flèche : cliquer la source puis la cible.
• Cliquer une cardinalité pour la faire défiler.
• Type d'attribut : taper a|b|c crée un enum.
• Molette : zoom. Glisser le fond : déplacer la vue.
• Suppr : supprimer la sélection.''';

/// Side panel editing the selected item.
class Inspector extends StatelessWidget {
  final Controller c;
  const Inspector(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final item = c.selected == null ? null : c.doc.item(c.selected!);
    if (item == null) return const Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.all(16), child: Text(_help)));
    return ListView(
      // Fields keep their own text state; a new key rebuilds them from the document.
      key: ValueKey('${c.revision}/${item.id}'),
      padding: const EdgeInsets.all(12),
      children: [
        ...switch (item) {
          Entity e => [_text('Entité', e.name, (v) => e.name = v), ..._attrs(e.attributes)],
          Association a => [_text('Association', a.name, (v) => a.name = v), ..._legs(a), ..._attrs(a.attributes)],
          EnumType t => [
              _text('Enum', t.name, (v) => t.name = v),
              _text('Valeurs (une par ligne)', t.values.join('\n'),
                  (v) => t.values = [for (final l in v.split('\n')) if (l.trim().isNotEmpty) l.trim()],
                  lines: 10),
            ],
          Note n => [_text('Note', n.text, (v) => n.text = v, lines: 10)],
          Arrow r => [_text('Libellé de la flèche', r.label, (v) => r.label = v)],
        },
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: c.deleteSelected,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          ),
        ),
      ],
    );
  }

  static const _dense = InputDecoration(isDense: true, border: OutlineInputBorder());

  Widget _text(String label, String value, void Function(String) set, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: value,
          maxLines: lines,
          decoration: _dense.copyWith(labelText: label),
          onChanged: (v) => c.change(() => set(v), 'edit:$label:${c.selected}'),
        ),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _icon(IconData icon, String tooltip, VoidCallback onTap, {bool? on}) => IconButton(
        icon: Icon(icon, size: 18, color: on == null ? null : (on ? Colors.blue.shade700 : Colors.grey.shade400)),
        tooltip: tooltip,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      );

  List<Widget> _legs(Association a) => [
        _title('Pattes'),
        if (a.legs.isEmpty) const Text('Utiliser l\'outil Lier pour rattacher une entité.'),
        for (final (i, l) in a.legs.indexed)
          Row(children: [
            Expanded(child: Text(c.doc.entities.firstWhere((e) => e.id == l.entityId).name)),
            DropdownButton<String>(
              value: l.card,
              isDense: true,
              items: [for (final x in cards) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => c.change(() => l.card = v!),
            ),
            Tooltip(
              message: 'Identifiant relatif (entité faible)',
              child: Checkbox(value: l.relative, onChanged: (v) => c.change(() => l.relative = v!)),
            ),
            _icon(Icons.close, 'Retirer la patte', () => c.change(() => a.legs.removeAt(i))),
          ]),
        const SizedBox(height: 8),
      ];

  List<Widget> _attrs(List<Attribute> attrs) => [
        _title('Attributs'),
        for (final a in attrs)
          Padding(
            key: ObjectKey(a),
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              _icon(Icons.key, 'Identifiant', () => c.change(() => a.isId = !a.isId), on: a.isId),
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: a.name,
                  decoration: _dense,
                  onChanged: (v) => c.change(() => a.name = v, 'name:${identityHashCode(a)}'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: Focus(
                  onFocusChange: (focused) {
                    if (!focused) c.normalizeType(a);
                  },
                  child: TextFormField(
                    initialValue: c.doc.typeName(a.type),
                    decoration: _dense.copyWith(hintText: 'type ou a|b|c'),
                    onChanged: (v) => c.change(() => a.type = v, 'type:${identityHashCode(a)}'),
                    onFieldSubmitted: (_) => c.normalizeType(a),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Choisir un type',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 140),
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                onSelected: (t) => c.change(() {
                  a.type = t;
                  c.revision++;
                }),
                itemBuilder: (_) => [
                  for (final t in primitiveTypes) PopupMenuItem(value: t, height: 32, child: Text(t)),
                  for (final e in c.doc.enums) PopupMenuItem(value: 'enum:${e.id}', height: 32, child: Text('enum ${e.name}')),
                ],
              ),
              _icon(Icons.question_mark, 'Nullable', () => c.change(() => a.nullable = !a.nullable), on: a.nullable),
              _icon(Icons.fingerprint, 'Unique', () => c.change(() => a.unique = !a.unique), on: a.unique),
              _icon(Icons.close, 'Supprimer l\'attribut', () => c.change(() => attrs.remove(a))),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => c.change(() => attrs.add(Attribute())),
            icon: const Icon(Icons.add),
            label: const Text('Attribut'),
          ),
        ),
      ];
}
