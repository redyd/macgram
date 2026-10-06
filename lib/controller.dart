import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;

import 'model.dart';

enum Tool { select, entity, association, enumType, note, link, arrow }

class Controller extends ChangeNotifier {
  Document doc = Document();
  Tool tool = Tool.select;
  String? path, selected;

  /// First element clicked with the link or arrow tool.
  String? pending;
  bool uml = false, showMld = false;

  /// The file changed on disk (git pull, checkout…) while there were unsaved edits.
  bool changedOnDisk = false;

  String _saved = Document().encode();
  final _undo = <String>[], _redo = <String>[];
  String? _tag;
  StreamSubscription<FileSystemEvent>? _watch;

  bool get dirty => doc.encode() != _saved;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  void setTool(Tool t) => _set(() {
    tool = t;
    pending = null;
  });
  void select(String? id) => _set(() {
    selected = id;
    _tag = null;
  });
  void toggleUml() => _set(() => uml = !uml);
  void toggleMld() => _set(() => showMld = !showMld);
  void endCoalesce() => _tag = null;

  /// Every edit goes through here. Consecutive edits with the same [tag]
  /// (typing in one field, dragging one node) share a single undo step.
  void change(VoidCallback f, [String? tag]) {
    if (tag == null || tag != _tag) {
      _undo.add(doc.encode());
      _redo.clear();
    }
    _tag = tag;
    f();
    doc.prune();
    notifyListeners();
  }

  void _restore(List<String> from, List<String> to) {
    if (from.isEmpty) return;
    to.add(doc.encode());
    doc = Document.decode(from.removeLast());
    selected = pending = _tag = null;
    notifyListeners();
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);

  static (int, int) snap(Offset p) =>
      ((p.dx / 10).round() * 10, (p.dy / 10).round() * 10);

  void move(String id, Offset p) =>
      change(() => doc.layout[id] = snap(p), 'move:$id');

  void deleteSelected() {
    if (selected == null) return;
    change(() {
      doc.remove(selected!);
      selected = null;
    });
  }

  void cancel() => _set(() {
    tool = Tool.select;
    pending = selected = null;
  });

  /// A click on the canvas: [key] is what was hit (see Scene.hits), [p] the scene position.
  void tap(String? key, Offset p) {
    void add(Item item, void Function() insert) => change(() {
      insert();
      doc.layout[item.id] = snap(p - const Offset(50, 14));
      selected = item.id;
      tool = Tool.select;
    });
    switch (tool) {
      case Tool.select:
        // A link selects its association; handles (resize…) keep the selection.
        final id = key == null ? null : (linkOf(key) ?? key);
        select(
          id == null
              ? null
              : (id.startsWith('leg:')
                    ? id.split(':')[1]
                    : (doc.item(id) == null ? selected : id)),
        );
      case Tool.entity:
        final e = Entity(id: newId('e'));
        add(e, () => doc.entities.add(e));
      case Tool.association:
        // Like Looping: click two entities to relate them. A click on empty space drops a lone association.
        if (key != null && key.startsWith('e-')) {
          if (pending == null) return _set(() => pending = key);
          final from = pending!;
          pending = null;
          tool = Tool.select;
          return _link(from, key);
        }
        if (pending != null) return _set(() => pending = null);
        final a = Association(id: newId('a'));
        add(a, () => doc.associations.add(a));
      case Tool.enumType:
        final t = EnumType(id: newId('t'));
        add(t, () => doc.enums.add(t));
      case Tool.note:
        final n = Note(id: newId('n'));
        add(n, () => doc.notes.add(n));
      case Tool.link || Tool.arrow:
        if (key == null || !doc.layout.containsKey(key)) return;
        if (pending == null) {
          _set(() => pending = key);
          return;
        }
        final from = pending!;
        final linking = tool == Tool.link;
        pending = null;
        tool = Tool.select;
        if (linking) {
          _link(from, key);
        } else if (from != key) {
          change(
            () => doc.arrows.add(Arrow(id: newId('r'), from: from, to: key)),
          );
        } else {
          notifyListeners();
        }
    }
  }

  /// The link a scene key belongs to: `leg:<association>:<index>` or an arrow id.
  static String? linkOf(String key) =>
      key.startsWith('leg:') || key.startsWith('r-')
      ? key
      : (key.startsWith('seg|') || key.startsWith('bend|')
            ? key.split('|')[1]
            : null);

  (Association, Leg)? leg(String link) {
    final [_, id, i] = link.split(':');
    final a = doc.associations.where((a) => a.id == id).firstOrNull,
        n = int.parse(i);
    return a == null || n >= a.legs.length ? null : (a, a.legs[n]);
  }

  List<Pt> _bends(String link) => link.startsWith('leg:')
      ? leg(link)!.$2.bends
      : doc.arrows.firstWhere((r) => r.id == link).bends;

  /// Right click: on a segment (`seg|link|j`) breaks it at [p], on a break point (`bend|link|j`) removes it.
  void toggleBend(String key, Offset p) {
    final [kind, link, j] = key.split('|');
    change(
      () => kind == 'bend'
          ? _bends(link).removeAt(int.parse(j))
          : _bends(link).insert(int.parse(j), snap(p)),
    );
  }

  void moveBend(String key, Offset p) {
    final [_, link, j] = key.split('|');
    change(() => _bends(link)[int.parse(j)] = snap(p), key);
  }

  void resizeNote(String id, Offset size) => change(
    () => doc.notes.firstWhere((n) => n.id == id).size = snap(
      Offset(max(60, size.dx), max(30, size.dy)),
    ),
    'resize:$id',
  );

  /// Link tool: entity + association adds a leg, entity + entity creates the
  /// association between them, entity + enum adds an attribute of that enum.
  void _link(String a, String b) {
    if (a[0] != 'e') (a, b) = (b, a);
    if (a[0] != 'e') return notifyListeners();
    change(() {
      switch (b[0]) {
        case 'a':
          doc.associations.firstWhere((x) => x.id == b).legs.add(Leg(a));
        case 'e':
          final assoc = Association(id: newId('a'), legs: [Leg(a), Leg(b)]);
          doc.associations.add(assoc);
          final pa = doc.layout[a]!, pb = doc.layout[b]!;
          final mid = Offset((pa.$1 + pb.$1) / 2, (pa.$2 + pb.$2) / 2);
          doc.layout[assoc.id] = snap(
            a == b ? mid + const Offset(40, -100) : mid,
          );
          selected = assoc.id;
        case 't':
          final t = doc.enums.firstWhere((x) => x.id == b);
          doc.entities
              .firstWhere((x) => x.id == a)
              .attributes
              .add(Attribute(name: t.name.toLowerCase(), type: 'enum:$b'));
      }
    });
  }

  /// Turns a typed type into an enum reference: `a|b|c` creates the enum,
  /// an existing enum name links to it.
  void normalizeType(Attribute a) {
    final t = a.type.trim();
    if (t.startsWith('enum:')) return;
    final named = doc.enums.where((e) => e.name == t).firstOrNull;
    if (named == null && !t.contains('|')) return;
    change(() {
      var e = named;
      if (e == null) {
        final values = [
          for (final v in t.split('|'))
            if (v.trim().isNotEmpty) v.trim(),
        ];
        final name = a.name.isEmpty
            ? 'Enum'
            : a.name[0].toUpperCase() + a.name.substring(1);
        e = EnumType(id: newId('t'), name: name, values: values);
        doc.enums.add(e);
        final near = doc.layout[selected] ?? (0, 0);
        doc.layout[e.id] = (near.$1 + 280, near.$2);
      }
      a.type = 'enum:${e.id}';
    });
  }

  void newDocument() {
    _watch?.cancel();
    doc = Document();
    _saved = doc.encode();
    path = selected = pending = null;
    _loaded();
  }

  void _loaded() {
    _undo.clear();
    _redo.clear();
    changedOnDisk = false;
    notifyListeners();
  }

  /// Throws if the file is unreadable or not a valid document (e.g. git conflict markers).
  void load(String p) {
    final text = File(p).readAsStringSync();
    doc = Document.decode(text);
    _saved = text;
    path = p;
    selected = pending = null;
    _loaded();
    _watchFile();
  }

  void save([String? to]) {
    path = to ?? path!;
    _saved = doc.encode(); // set first so the watcher ignores our own write
    File(path!).writeAsStringSync(_saved);
    changedOnDisk = false;
    notifyListeners();
    if (to != null) _watchFile();
  }

  // The directory is watched, not the file: git replaces files instead of modifying them.
  void _watchFile() {
    _watch?.cancel();
    _watch = File(path!).parent.watch().listen((_) {
      final String text;
      try {
        text = File(path!).readAsStringSync();
      } on FileSystemException {
        return;
      }
      if (text == _saved) return;
      if (!dirty) {
        try {
          load(path!);
          return;
        } catch (_) {
          // half-written or conflicted file: fall through and let the user decide
        }
      }
      _set(() => changedOnDisk = true);
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }
}
