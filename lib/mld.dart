import 'model.dart';

class _Col {
  final String name;
  final String? type;
  final bool pk, fk, nullable;
  _Col(
    this.name,
    this.type, {
    this.pk = false,
    this.fk = false,
    this.nullable = false,
  });
  @override
  String toString() =>
      '${pk ? '_' : ''}${fk ? '#' : ''}$name${pk ? '_' : ''}${type == null ? '' : ': $type'}${nullable ? '?' : ''}';
}

/// Textual relational model derived from the MCD. `_x_` is a primary key, `#x` a foreign key.
String mld(Document d) {
  final ents = {for (final e in d.entities) e.id: e};

  // The leg whose entity receives the foreign key, for a binary association with a max-1 side.
  Leg? holder(Association a) {
    if (a.legs.length != 2) return null;
    final ones = a.legs.where((l) => l.maxOne).toList();
    if (ones.isEmpty) return null;
    return ones.firstWhere((l) => l.card == '1,1', orElse: () => ones.first);
  }

  void add(List<_Col> cols, _Col c) {
    var name = c.name;
    for (var i = 2; cols.any((x) => x.name == name); i++) {
      name = '${c.name}_$i';
    }
    cols.add(_Col(name, c.type, pk: c.pk, fk: c.fk, nullable: c.nullable));
  }

  String fkName(String col, Entity target) {
    final suffix = target.name.toLowerCase();
    return col.toLowerCase().contains(suffix) ? col : '${col}_$suffix';
  }

  _Col attr(Attribute a) =>
      _Col(a.name, d.typeName(a.type), pk: a.isId, nullable: a.nullable);

  // `seen` stops reflexive associations and weak-entity cycles from recursing forever.
  List<_Col> cols(String id, Set<String> seen) {
    final out = ents[id]!.attributes.map(attr).toList();
    if (seen.contains(id)) return out;
    for (final a in d.associations) {
      final h = holder(a);
      if (h == null || h.entityId != id) continue;
      final other = ents[a.legs.firstWhere((l) => !identical(l, h)).entityId]!;
      for (final c in cols(other.id, {...seen, id}).where((c) => c.pk)) {
        add(
          out,
          _Col(
            fkName(c.name, other),
            null,
            pk: h.relative,
            fk: true,
            nullable: h.card.startsWith('0'),
          ),
        );
      }
      for (final x in a.attributes) {
        add(out, attr(x));
      }
    }
    return out;
  }

  final lines = <String>[
    for (final e in [...d.enums]..sort((a, b) => a.name.compareTo(b.name)))
      'enum ${e.name} { ${e.values.join(', ')} }',
    if (d.enums.isNotEmpty) '',
    for (final e in [...d.entities]..sort((a, b) => a.name.compareTo(b.name)))
      '${e.name}(${cols(e.id, {}).join(', ')})',
  ];
  for (final a in [
    ...d.associations,
  ]..sort((a, b) => a.name.compareTo(b.name))) {
    if (holder(a) != null || a.legs.isEmpty) continue;
    final out = <_Col>[];
    for (final l in a.legs) {
      for (final c in cols(l.entityId, {}).where((c) => c.pk)) {
        add(
          out,
          _Col(fkName(c.name, ents[l.entityId]!), null, pk: true, fk: true),
        );
      }
    }
    for (final x in a.attributes) {
      add(out, attr(x));
    }
    lines.add('${a.name}(${out.join(', ')})');
  }
  return lines.join('\n');
}
