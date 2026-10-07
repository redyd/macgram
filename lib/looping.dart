import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'model.dart';

// Import of Looping diagrams (.loo). The format is an undocumented MFC
// serialisation; the layout below was worked out from sample files.
//
// The file is a list of drawing objects (entities, relations, rules, link
// arcs, and the text blocks each of them owns), followed by a table chaining
// the arcs of every link to the objects at its two ends.
//
// Looping rules and title blocks become notes, rule links and free arrows
// become arrows. Attribute types are not read: `id` gets int, the rest string.

const _arcs = {'CDrawArc', 'CDrawArcRegle'};
const _owners = {'CDrawEntite', 'CDrawRelation', 'CDrawRegle', 'CDrawTitre'};

typedef _Obj = ({String cls, int a, int b});
typedef _Rec = ({int? obj, Pt? pt, List<_Obj> tx, bool last});

/// Throws a [FormatException] when [bytes] is not a readable Looping file.
Document importLooping(Uint8List bytes) {
  try {
    return _Loo(bytes).read();
  } on RangeError {
    throw const FormatException('Fichier Looping illisible');
  }
}

int _grid(int v) => (v / 10).round() * 10;

bool _eq(List<Object> t, int k, List<int> values) {
  if (k + values.length > t.length) return false;
  for (final (i, v) in values.indexed) {
    if (t[k + i] != v) return false;
  }
  return true;
}

class _Loo {
  final Uint8List d;
  final ByteData bd;

  /// Objects by Looping id, in file order. Offsets [a]..[b] span the body.
  final objs = <int, _Obj>{};

  _Loo(this.d) : bd = ByteData.sublistView(d);

  int i32(int p) => bd.getInt32(p, Endian.little);
  int u16(int p) => bd.getUint16(p, Endian.little);
  String cls(int? id) => objs[id]?.cls ?? '';

  /// Walks the MFC object tags: `FFFF schema len name` introduces a class,
  /// `8000|n` refers back to the n-th tag. Classes and objects share one counter.
  void split() {
    final s = latin1.decode(d);
    final news = {
      for (final m in RegExp(
        r'\xff\xff\x00\x00[\x08-\x10]\x00CDraw',
      ).allMatches(s))
        m.start,
    };
    final starts = {
      ...news,
      for (final m in RegExp(
        r'[\x00-\xff][\x80-\x83][\x00-\xff]{2}\x00\x00(?:[\x00\x01]\x00){6}',
      ).allMatches(s))
        m.start,
    }.toList()..sort();
    final byIndex = <int, String>{}, type = <String, int>{};
    final found = <(String, int)>[];
    var n = 1;
    for (final o in starts) {
      final String name;
      final int body;
      if (news.contains(o)) {
        final len = u16(o + 4);
        name = latin1.decode(d.sublist(o + 6, o + 6 + len));
        body = o + 6 + len;
        byIndex[n++] = name;
        type[name] = i32(body);
      } else {
        final known = byIndex[u16(o) & 0x7fff];
        if (known == null || type[known] != i32(o + 2)) continue;
        name = known;
        body = o + 2;
      }
      found.add((name, body));
      n++;
    }
    for (final (i, (name, a)) in found.indexed) {
      if (a + 104 > d.length) continue;
      final b = i + 1 < found.length ? found[i + 1].$2 : d.length;
      objs[i32(a + 100)] = (cls: name, a: a, b: b);
    }
  }

  /// The body of [o] as a run of int32 and CString (`FF FE FF len utf16`) tokens.
  List<Object> toks(_Obj o) {
    final out = <Object>[];
    var p = o.a + 104;
    while (p + 4 <= o.b) {
      if (d[p] == 0xff && d[p + 1] == 0xfe && d[p + 2] == 0xff) {
        var n = d[p + 3], q = p + 4;
        if (n == 255) {
          n = u16(q);
          q += 2;
        }
        n = min(n, (d.length - q) ~/ 2);
        out.add(
          String.fromCharCodes([for (var i = 0; i < n; i++) u16(q + 2 * i)]),
        );
        p = q + 2 * n;
      } else {
        out.add(i32(p));
        p += 4;
      }
    }
    return out;
  }

  List<String> strings(List<Object> t) => [
    for (final x in t)
      if (x is String && x.isNotEmpty && x != 'Calibri') x,
  ];

  /// Attributes of a text block: each is a name followed by a fixed record,
  /// whose 20th field is the identifier flag.
  List<Attribute> attrs(List<Object> t, {required bool ids}) => [
    for (var k = 0; k + 20 < t.length; k++)
      if (t[k] case final String name
          when name.isNotEmpty &&
              _eq(t, k + 1, [0, 1, 0]) &&
              _eq(t, k + 13, [1, 0, 0, 2]))
        Attribute(
          name: name,
          type: name == 'id' ? 'int' : 'string',
          isId: ids && t[k + 20] == 1,
        ),
  ];

  /// Cardinality of a link, from the one text block of [tx] that carries it,
  /// plus the free text Looping lets the user show next to it.
  (String, String) cardOf(List<_Obj> tx) {
    for (final o in tx) {
      if (o.b - o.a < 838) continue;
      final t = toks(o);
      for (var q = 0; q + 17 < t.length; q++) {
        if (!_eq(t, q, [50, 50, 50, 50, 50, 50, 15, 2])) continue;
        final c = t[q + 9], note = t[q + 17];
        return (
          c is int && c >= 0 && c < cards.length ? cards[c] : '0,n',
          note is String ? note : '',
        );
      }
    }
    return ('0,n', '');
  }

  Document read() {
    split();
    final doc = Document();
    String sid(String prefix, int id) =>
        '$prefix-${id.toString().padLeft(6, '0')}';

    final kids = <int, List<_Obj>>{};
    int? owner;
    for (final MapEntry(key: id, value: o) in objs.entries) {
      if (o.cls == 'CDrawTexte') {
        kids[owner]?.add(o);
      } else {
        owner = _owners.contains(o.cls) ? id : null;
        if (owner != null) kids[id] = [];
      }
    }

    final ents = <int, Entity>{}, assocs = <int, Association>{};
    final node = <int, String>{}; // Looping id -> macgram id
    final notes = <int>{};
    final rects = <(int, int, int, int, int)>[]; // id, left, top, right, bottom
    for (final MapEntry(key: id, value: o) in objs.entries) {
      final texts = [for (final k in kids[id] ?? const <_Obj>[]) toks(k)];
      (String, List<Attribute>) named({required bool ids}) {
        var name = '';
        var list = <Attribute>[];
        for (final t in texts) {
          final found = attrs(t, ids: ids);
          if (found.isNotEmpty) {
            list = found;
          } else if (strings(t).isNotEmpty) {
            name = strings(t).first;
          }
        }
        return (name, list);
      }

      switch (o.cls) {
        case 'CDrawEntite':
          final l = i32(o.a + 172), t = i32(o.a + 176);
          final (name, list) = named(ids: true);
          final e = Entity(id: sid('e', id), name: name, attributes: list);
          doc.entities.add(ents[id] = e);
          doc.layout[node[id] = e.id] = (_grid(l), _grid(t));
          rects.add((id, l, t, i32(o.a + 180), i32(o.a + 184)));
        case 'CDrawRelation':
          // Centre and half-extents.
          final x = i32(o.a + 170), y = i32(o.a + 174);
          final hw = i32(o.a + 178), hh = i32(o.a + 182);
          final (name, list) = named(ids: false);
          final a = Association(id: sid('a', id), name: name, attributes: list);
          doc.associations.add(assocs[id] = a);
          doc.layout[node[id] = a.id] = (_grid(x - hw), _grid(y - hh));
          rects.add((id, x - hw, y - hh, x + hw, y + hh));
        case 'CDrawRegle' || 'CDrawTitre':
          final l = i32(o.a + 172), t = i32(o.a + 176);
          var title = '';
          var body = <String>[];
          for (final (i, k) in kids[id]!.indexed) {
            final s = strings(texts[i]);
            if (o.cls == 'CDrawRegle' && k.b - k.a < 700 && s.length == 1) {
              title = s.first;
            } else if (s.isNotEmpty) {
              body = s;
            }
          }
          final n = Note(
            id: sid('n', id),
            text: [
              if (title.isNotEmpty) title,
              for (final line in body) line.trim(),
            ].join('\n'),
            size: (_grid(i32(o.a + 180) - l), _grid(i32(o.a + 184) - t)),
          );
          doc.notes.add(n);
          notes.add(id);
          doc.layout[node[id] = n.id] = (_grid(l), _grid(t));
      }
    }
    if (doc.entities.isEmpty) {
      throw const FormatException('Fichier Looping non reconnu');
    }

    // Link table, one record per arc: `[text ×3][prev][next][object][1]` at
    // the two ends, `[text ×3][prev][next][0][word 0][x][y]` for a point in
    // between (or for the ends of a free arrow). An arc's id is prev + 1.
    final rec = <int, _Rec>{};
    final maxId = objs.keys.fold(0, max);
    for (var p = objs.values.last.a + 104; p + 16 <= d.length; p++) {
      final prev = i32(p), next = i32(p + 4), o = i32(p + 8);
      if (prev < 0 || next < 0 || (prev == 0 && next == 0)) continue;
      final own = prev != 0 ? prev + 1 : next - 1;
      final tx = [
        for (var q = p - 12; q < p; q += 4)
          if (cls(i32(q)) == 'CDrawTexte') objs[i32(q)]!,
      ];
      final target = cls(o);
      if ((prev == 0 || next == 0) &&
          _arcs.contains(cls(prev | next)) &&
          i32(p + 12) == 1 &&
          target.isNotEmpty &&
          target != 'CDrawTexte' &&
          !_arcs.contains(target)) {
        rec[own] = (obj: o, pt: null, tx: tx, last: next == 0);
      } else if (o == 0 &&
          tx.length == 3 &&
          p + 22 <= d.length &&
          (prev == 0 || next == 0 || next == prev + 2) &&
          (_arcs.contains(cls(own)) ||
              cls(own) == 'CDrawFleche' ||
              (own > 0 && own <= maxId + 8 && !objs.containsKey(own)))) {
        final pt = (i32(p + 14), i32(p + 18));
        rec[own] = (obj: null, pt: pt, tx: tx, last: next == 0);
      }
    }

    int? hit(Pt? pt) {
      if (pt == null) return null;
      for (final (id, l, t, r, b) in rects) {
        if (pt.$1 >= l - 15 &&
            pt.$1 <= r + 15 &&
            pt.$2 >= t - 15 &&
            pt.$2 <= b + 15) {
          return id;
        }
      }
      return null;
    }

    for (final k in rec.keys.toList()..sort()) {
      final before = rec[k - 1];
      if (before != null && !before.last) continue; // not the start of a chain
      final chain = <_Rec>[];
      for (var j = k; rec[j] != null; j++) {
        chain.add(rec[j]!);
        if (rec[j]!.last) break;
      }
      if (chain.length < 2) continue;
      final first = chain.first, last = chain.last;
      // A free arrow is attached to whatever sits under its ends.
      var o1 = first.obj ?? hit(first.pt), o2 = last.obj ?? hit(last.pt);
      var bends = [
        for (final c in chain.sublist(1, chain.length - 1))
          if (c.pt != null && c.pt != first.pt && c.pt != last.pt)
            (_grid(c.pt!.$1), _grid(c.pt!.$2)),
      ];
      final e = ents.containsKey(o1) ? o1 : (ents.containsKey(o2) ? o2 : null);
      final a = assocs.containsKey(o1)
          ? o1
          : (assocs.containsKey(o2) ? o2 : null);
      if (cls(k) == 'CDrawArc' && e != null && a != null) {
        final (card, note) = cardOf([for (final c in chain) ...c.tx]);
        assocs[a]!.legs.add(
          Leg(
            ents[e]!.id,
            card: card,
            note: note,
            bends: o1 == e ? bends.reversed.toList() : bends,
          ),
        );
      } else if (node[o1] != null && node[o2] != null) {
        if (notes.contains(o2)) {
          (o1, o2) = (o2, o1);
          bends = bends.reversed.toList();
        }
        doc.arrows.add(
          Arrow(id: sid('r', k), from: node[o1]!, to: node[o2]!, bends: bends),
        );
      }
    }
    return doc..prune();
  }
}
