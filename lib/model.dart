import 'dart:convert';
import 'dart:math';

const primitiveTypes = ['string', 'text', 'int', 'decimal', 'bool', 'date', 'datetime', 'uuid', 'json'];
const cards = ['0,1', '1,1', '0,n', '1,n'];

final _rnd = Random();

/// Ids are random, not counters: two git branches adding elements never collide,
/// and since lists are saved sorted by id, additions land on different lines.
/// The prefix gives the kind: e entity, a association, t enum, n note, r arrow.
String newId(String prefix) =>
    '$prefix-${List.generate(6, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rnd.nextInt(36)]).join()}';

sealed class Item {
  String get id;
  Map<String, Object?> toJson();
}

class Attribute {
  String name, type;
  bool isId, nullable, unique;
  Attribute({this.name = 'attribut', this.type = 'string', this.isId = false, this.nullable = false, this.unique = false});
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

List<Attribute> _attrs(Map j) => [for (final a in (j['attributes'] ?? []) as List) Attribute.fromJson(a as Map)];

class EnumType extends Item {
  @override
  final String id;
  String name;
  List<String> values;
  EnumType({required this.id, this.name = 'Enum', List<String>? values}) : values = values ?? ['A', 'B'];
  EnumType.fromJson(Map j)
      : id = j['id'] as String,
        name = j['name'] as String,
        values = (j['values'] as List).cast<String>().toList();
  @override
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'values': values};
}

class Entity extends Item {
  @override
  final String id;
  String name;
  List<Attribute> attributes;
  Entity({required this.id, this.name = 'Entite', List<Attribute>? attributes})
      : attributes = attributes ?? [Attribute(name: 'id', type: 'int', isId: true)];
  Entity.fromJson(Map j)
      : id = j['id'] as String,
        name = j['name'] as String,
        attributes = _attrs(j);
  @override
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'attributes': [for (final a in attributes) a.toJson()]};
}

class Leg {
  String entityId, card;

  /// Relative identifier: the entity on this leg is weak, identified through the association.
  bool relative;
  Leg(this.entityId, {this.card = '0,n', this.relative = false});
  Leg.fromJson(Map j)
      : entityId = j['entity'] as String,
        card = j['card'] as String,
        relative = j['relative'] == true;
  bool get maxOne => card.endsWith('1');
  Map<String, Object?> toJson() => {'entity': entityId, 'card': card, if (relative) 'relative': true};
}

class Association extends Item {
  @override
  final String id;
  String name;
  List<Attribute> attributes;
  List<Leg> legs;
  Association({required this.id, this.name = 'relation', List<Attribute>? attributes, List<Leg>? legs})
      : attributes = attributes ?? [],
        legs = legs ?? [];
  Association.fromJson(Map j)
      : id = j['id'] as String,
        name = j['name'] as String,
        attributes = _attrs(j),
        legs = [for (final l in (j['legs'] ?? []) as List) Leg.fromJson(l as Map)];
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
  Note({required this.id, this.text = 'Note'});
  Note.fromJson(Map j)
      : id = j['id'] as String,
        text = j['text'] as String;
  @override
  Map<String, Object?> toJson() => {'id': id, 'text': text};
}

class Arrow extends Item {
  @override
  final String id;
  String from, to, label;
  Arrow({required this.id, required this.from, required this.to, this.label = ''});
  Arrow.fromJson(Map j)
      : id = j['id'] as String,
        from = j['from'] as String,
        to = j['to'] as String,
        label = (j['label'] ?? '') as String;
  @override
  Map<String, Object?> toJson() => {'id': id, 'from': from, 'to': to, if (label.isNotEmpty) 'label': label};
}

class Document {
  final enums = <EnumType>[];
  final entities = <Entity>[];
  final associations = <Association>[];
  final notes = <Note>[];
  final arrows = <Arrow>[];

  /// Top-left position of every node, on a 10px grid.
  final layout = <String, (int, int)>{};

  Iterable<Item> get nodes => [...enums, ...entities, ...associations, ...notes];

  Item? item(String id) => [...nodes, ...arrows].where((i) => i.id == id).firstOrNull;

  String typeName(String type) => type.startsWith('enum:')
      ? enums.where((e) => e.id == type.substring(5)).firstOrNull?.name ?? '?'
      : type;

  void remove(String id) {
    for (final l in <List<Item>>[enums, entities, associations, notes, arrows]) {
      l.removeWhere((i) => i.id == id);
    }
    prune();
  }

  /// Drops dangling references (after a delete, or a hand-resolved git merge).
  void prune() {
    final ents = {for (final e in entities) e.id};
    final enumIds = {for (final e in enums) e.id};
    for (final a in associations) {
      a.legs.removeWhere((l) => !ents.contains(l.entityId));
    }
    for (final a in [...entities.expand((e) => e.attributes), ...associations.expand((a) => a.attributes)]) {
      if (a.type.startsWith('enum:') && !enumIds.contains(a.type.substring(5))) a.type = 'string';
    }
    final ids = {for (final n in nodes) n.id};
    arrows.removeWhere((r) => !ids.contains(r.from) || !ids.contains(r.to));
    layout.removeWhere((k, _) => !ids.contains(k));
    for (final id in ids) {
      layout.putIfAbsent(id, () => (0, 0));
    }
  }

  /// Deterministic: same document, same bytes. Lists and layout are sorted by id.
  String encode() {
    List<Object?> sorted(List<Item> l) => [for (final i in [...l]..sort((a, b) => a.id.compareTo(b.id))) i.toJson()];
    return '${_fmt({
          'version': 1,
          'enums': sorted(enums),
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
    if (((j['version'] ?? 1) as int) > 1) throw const FormatException('Version de fichier non supportée');
    Iterable<Map> l(String k) => ((j[k] ?? []) as List).cast<Map>();
    final d = Document()
      ..enums.addAll(l('enums').map(EnumType.fromJson))
      ..entities.addAll(l('entities').map(Entity.fromJson))
      ..associations.addAll(l('associations').map(Association.fromJson))
      ..notes.addAll(l('notes').map(Note.fromJson))
      ..arrows.addAll(l('arrows').map(Arrow.fromJson));
    ((j['layout'] ?? {}) as Map).forEach((k, v) {
      d.layout[k as String] = (((v as List)[0] as num).round(), (v[1] as num).round());
    });
    return d..prune();
  }
}

/// JSON with one line per atomic element (attribute, leg, position), so that
/// one model change is a one-line git diff.
String _fmt(Object? v, [String ind = '']) {
  bool flat(Object? x) => x is! Map && x is! List;
  final i2 = '$ind  ';
  if (v is Map) {
    if (v.values.every(flat)) {
      return '{${v.entries.map((e) => '${jsonEncode(e.key)}: ${jsonEncode(e.value)}').join(', ')}}';
    }
    return '{\n${v.entries.map((e) => '$i2${jsonEncode(e.key)}: ${_fmt(e.value, i2)}').join(',\n')}\n$ind}';
  }
  if (v is List) {
    if (v.every(flat)) return '[${v.map(jsonEncode).join(', ')}]';
    return '[\n${v.map((e) => '$i2${_fmt(e, i2)}').join(',\n')}\n$ind]';
  }
  return jsonEncode(v);
}
