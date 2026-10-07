import 'dart:convert';
import 'dart:math';

const primitiveTypes = [
  'string',
  'text',
  'int',
  'decimal',
  'bool',
  'date',
  'datetime',
  'uuid',
  'json',
];
const cards = ['0,1', '1,1', '0,n', '1,n'];

final _rnd = Random();

/// Ids are random, not counters: two git branches adding elements never collide,
/// and since lists are saved sorted by id, additions land on different lines.
/// The prefix gives the kind: e entity, a association, t enum, m enum copy,
/// n note, r arrow.
String newId(String prefix) =>
    '$prefix-${List.generate(6, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rnd.nextInt(36)]).join()}';

typedef Pt = (int, int);

// Points are stored as a flat [x1, y1, x2, y2] list so their owner stays on one line.
List<Pt> _pts(Object? j) {
  final l = (j ?? []) as List;
  return [
    for (var i = 0; i + 1 < l.length; i += 2)
      ((l[i] as num).round(), (l[i + 1] as num).round()),
  ];
}

List<int> _flat(List<Pt> pts) => [
  for (final (x, y) in pts) ...[x, y],
];

sealed class Item {
  String get id;
  Map<String, Object?> toJson();
}

class Attribute {
  String name, type;
  bool isId, nullable, unique;
  Attribute({
    this.name = 'attribut',
    this.type = 'string',
    this.isId = false,
    this.nullable = false,
    this.unique = false,
  });
  Attribute.fromJson(Map j)
    : name = j['name'] as String,
      type = j['type'] as String,
      isId = j['id'] == true,
      nullable = j['nullable'] == true,
      unique = j['unique'] == true;
  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    if (isId) 'id': true,
    if (nullable) 'nullable': true,
    if (unique) 'unique': true,
  };
}

List<Attribute> _attrs(Map j) => [
  for (final a in (j['attributes'] ?? []) as List) Attribute.fromJson(a as Map),
];

/// Enum names are PascalCase: `Mon_enum` and `mon enum` become `MonEnum`.
String pascal(String s) => s
    .split(RegExp(r'[_\s-]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join();

class EnumType extends Item {
  @override
  final String id;
  String _name;
  List<String> values;
  EnumType({required this.id, String name = 'Enum', List<String>? values})
    : _name = pascal(name),
      values = values ?? ['A', 'B'];
  EnumType.fromJson(Map j)
    : id = j['id'] as String,
      _name = pascal(j['name'] as String),
      values = (j['values'] as List).cast<String>().toList();
  String get name => _name;
  set name(String v) => _name = pascal(v);
  @override
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'values': values};
}

class Entity extends Item {
  @override
  final String id;
  String name;
  List<Attribute> attributes;
  Entity({required this.id, this.name = 'Entite', List<Attribute>? attributes})
    : attributes =
          attributes ?? [Attribute(name: 'id', type: 'int', isId: true)];
  Entity.fromJson(Map j)
    : id = j['id'] as String,
      name = j['name'] as String,
      attributes = _attrs(j);
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'attributes': [for (final a in attributes) a.toJson()],
  };
}

class Leg {
  /// The entity on this leg, or an enum copy (see [Document.mirrors]).
  String entityId, card, note;

  /// Break points of the link, from the association to the entity.
  List<Pt> bends;

  /// Relative identifier: the entity on this leg is weak, identified through the association.
  bool relative;
  Leg(
    this.entityId, {
    this.card = '0,n',
    this.relative = false,
    this.note = '',
    List<Pt>? bends,
  }) : bends = bends ?? [];
  Leg.fromJson(Map j)
    : entityId = j['entity'] as String,
      card = j['card'] as String,
      relative = j['relative'] == true,
      note = (j['note'] ?? '') as String,
      bends = _pts(j['bends']);
  bool get maxOne => card.endsWith('1');
  Map<String, Object?> toJson() => {
    'entity': entityId,
    'card': card,
    if (relative) 'relative': true,
    if (note.isNotEmpty) 'note': note,
    if (bends.isNotEmpty) 'bends': _flat(bends),
  };
}

class Association extends Item {
  @override
  final String id;
  String name;
  List<Attribute> attributes;
  List<Leg> legs;
  Association({
    required this.id,
    this.name = 'relation',
    List<Attribute>? attributes,
    List<Leg>? legs,
  }) : attributes = attributes ?? [],
       legs = legs ?? [];
  Association.fromJson(Map j)
    : id = j['id'] as String,
      name = j['name'] as String,
      attributes = _attrs(j),
      legs = [
        for (final l in (j['legs'] ?? []) as List) Leg.fromJson(l as Map),
      ];
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'attributes': [for (final a in attributes) a.toJson()],
    'legs': [for (final l in legs) l.toJson()],
  };
}

class Note extends Item {
  @override
  final String id;
  String text;

  /// Manual size; null means sized to the text.
  Pt? size;
  Note({required this.id, this.text = 'Note', this.size});
  Note.fromJson(Map j)
    : id = j['id'] as String,
      text = j['text'] as String,
      size = _pts(j['size']).firstOrNull;
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    if (size != null) 'size': [size!.$1, size!.$2],
  };
}

class Arrow extends Item {
  @override
  final String id;
  String from, to, label;
  List<Pt> bends;
  Arrow({
    required this.id,
    required this.from,
    required this.to,
    this.label = '',
    List<Pt>? bends,
  }) : bends = bends ?? [];
  Arrow.fromJson(Map j)
    : id = j['id'] as String,
      from = j['from'] as String,
      to = j['to'] as String,
      label = (j['label'] ?? '') as String,
      bends = _pts(j['bends']);
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    if (label.isNotEmpty) 'label': label,
    if (bends.isNotEmpty) 'bends': _flat(bends),
  };
}

class Document {
  final enums = <EnumType>[];
  final entities = <Entity>[];
  final associations = <Association>[];
  final notes = <Note>[];
  final arrows = <Arrow>[];

  /// Copies of enums placed on the canvas so associations can reach them:
  /// copy id → enum id. A copy has no content, it is drawn from its enum.
  final mirrors = <String, String>{};

  /// Top-left position of every node, on a 10px grid.
  final layout = <String, Pt>{};

  /// The items on the canvas. Enums live in the side panel; only their
  /// copies are on the canvas.
  Iterable<Item> get nodes => [...entities, ...associations, ...notes];

  /// An enum copy resolves to its enum.
  Item? item(String id) => [
    ...nodes,
    ...arrows,
    ...enums,
  ].where((i) => i.id == (mirrors[id] ?? id)).firstOrNull;

  /// Name of what a leg is attached to.
  String endName(String id) => switch (item(id)) {
    Entity e => e.name,
    EnumType t => t.name,
    _ => '?',
  };

  String typeName(String type) => type.startsWith('enum:')
      ? enums.where((e) => e.id == type.substring(5)).firstOrNull?.name ?? '?'
      : type;

  void remove(String id) {
    for (final l in <List<Item>>[
      enums,
      entities,
      associations,
      notes,
      arrows,
    ]) {
      l.removeWhere((i) => i.id == id);
    }
    mirrors.remove(id);
    prune();
  }

  /// Drops dangling references (after a delete, or a hand-resolved git merge).
  void prune() {
    final ents = {for (final e in entities) e.id};
    final enumIds = {for (final e in enums) e.id};
    mirrors.removeWhere((_, e) => !enumIds.contains(e));
    for (final a in associations) {
      a.legs.removeWhere(
        (l) => !ents.contains(l.entityId) && !mirrors.containsKey(l.entityId),
      );
    }
    for (final a in [
      ...entities.expand((e) => e.attributes),
      ...associations.expand((a) => a.attributes),
    ]) {
      if (a.type.startsWith('enum:') &&
          !enumIds.contains(a.type.substring(5))) {
        a.type = 'string';
      }
    }
    final ids = {for (final n in nodes) n.id, ...mirrors.keys};
    arrows.removeWhere((r) => !ids.contains(r.from) || !ids.contains(r.to));
    layout.removeWhere((k, _) => !ids.contains(k));
    for (final id in ids) {
      layout.putIfAbsent(id, () => (0, 0));
    }
  }

  /// Deterministic: same document, same bytes. Lists and layout are sorted by id.
  String encode() {
    List<Object?> sorted(List<Item> l) => [
      for (final i in [...l]..sort((a, b) => a.id.compareTo(b.id))) i.toJson(),
    ];
    return '${_fmt({
      'version': 1,
      'enums': sorted(enums),
      if (mirrors.isNotEmpty) 'mirrors': {for (final k in mirrors.keys.toList()..sort()) k: mirrors[k]},
      'entities': sorted(entities),
      'associations': sorted(associations),
      'notes': sorted(notes),
      'arrows': sorted(arrows),
      'layout': {
        for (final k in layout.keys.toList()..sort()) k: [layout[k]!.$1, layout[k]!.$2],
      },
    })}\n';
  }

  static Document decode(String text) {
    final j = jsonDecode(text) as Map;
    if (((j['version'] ?? 1) as int) > 1) {
      throw const FormatException('Version de fichier non supportée');
    }
    Iterable<Map> l(String k) => ((j[k] ?? []) as List).cast<Map>();
    final d = Document()
      ..enums.addAll(l('enums').map(EnumType.fromJson))
      ..entities.addAll(l('entities').map(Entity.fromJson))
      ..associations.addAll(l('associations').map(Association.fromJson))
      ..notes.addAll(l('notes').map(Note.fromJson))
      ..arrows.addAll(l('arrows').map(Arrow.fromJson));
    d.mirrors.addAll(((j['mirrors'] ?? {}) as Map).cast<String, String>());
    ((j['layout'] ?? {}) as Map).forEach((k, v) {
      d.layout[k as String] = (
        ((v as List)[0] as num).round(),
        (v[1] as num).round(),
      );
    });
    return d..prune();
  }
}

/// JSON with one line per atomic element (attribute, leg, position), so that
/// one model change is a one-line git diff. The two outer levels (sections,
/// then their entries) always get one entry per line.
String _fmt(Object? v, [String ind = '', int depth = 0]) {
  bool scalar(Object? x) => x is! Map && x is! List;
  bool flat(Object? x) => scalar(x) || (x is List && x.every(scalar));
  final i2 = '$ind  ';
  if (v is Map) {
    if (v.isEmpty) return '{}';
    if (depth >= 2 && v.values.every(flat)) {
      return '{${v.entries.map((e) => '${jsonEncode(e.key)}: ${_fmt(e.value, i2, depth + 1)}').join(', ')}}';
    }
    return '{\n${v.entries.map((e) => '$i2${jsonEncode(e.key)}: ${_fmt(e.value, i2, depth + 1)}').join(',\n')}\n$ind}';
  }
  if (v is List) {
    if (v.every(scalar)) return '[${v.map(jsonEncode).join(', ')}]';
    return '[\n${v.map((e) => '$i2${_fmt(e, i2, depth + 1)}').join(',\n')}\n$ind]';
  }
  return jsonEncode(v);
}
