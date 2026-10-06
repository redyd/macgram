import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'model.dart';

// The diagram is turned into plain shapes by a pure function; the canvas, the
// PNG export and the SVG export all draw the same list.

// ponytail: text width is estimated (monospace, 0.6em per char), not measured.
// Boxes can be a bit wide with a proportional fallback font; measure with
// TextPainter if pixel-exact boxes ever matter.
const fontSize = 13.0, charW = 7.9, rowH = 20.0, headH = 28.0, padX = 12.0;

const _ink = 0xFF263238, _grey = 0xFF78909C, _sel = 0xFF1565C0, _pend = 0xFFEF6C00, _arrow = 0xFF6D4C41;

sealed class Shape {
  const Shape();
}

class Box extends Shape {
  final Rect rect;
  final double radius, strokeWidth;
  final int fill, stroke;
  const Box(this.rect, {this.radius = 0, this.fill = 0xFFFFFFFF, this.stroke = _ink, this.strokeWidth = 1.2});
}

class Line extends Shape {
  final Offset a, b;
  final int color;
  const Line(this.a, this.b, [this.color = _ink]);
}

class Poly extends Shape {
  final List<Offset> points;
  final int fill;
  const Poly(this.points, [this.fill = _ink]);
}

class Label extends Shape {
  /// Top of the text line; [align] says which x it is: -1 left, 0 centre, 1 right.
  final Offset pos;
  final String text;
  final int align, color;
  final bool bold, underline;
  const Label(this.pos, this.text, {this.align = -1, this.color = _ink, this.bold = false, this.underline = false});
}

class Scene {
  final shapes = <Shape>[];

  /// Clickable regions, later entries on top. Keys are item ids, or `leg:<associationId>:<index>`.
  final hits = <(String, Rect)>[];

  String? hit(Offset p) => hits.reversed.where((h) => h.$2.contains(p)).firstOrNull?.$1;

  Rect get bounds => hits.isEmpty
      ? const Rect.fromLTWH(0, 0, 400, 300)
      : hits.map((h) => h.$2).reduce((a, b) => a.expandToInclude(b)).inflate(30);
}

typedef _Row = (String left, String right, bool underline);

const _umlCard = {'0,1': '0..1', '1,1': '1', '0,n': '*', '1,n': '1..*'};

/// Where the segment from the centre of [r] towards [to] leaves [r].
Offset edge(Rect r, Offset to) {
  final d = to - r.center;
  if (d == Offset.zero) return r.center;
  final k = min(r.width / 2 / max(d.dx.abs(), 1e-9), r.height / 2 / max(d.dy.abs(), 1e-9));
  return r.center + d * min(k, 1);
}

Offset _unit(Offset v) => v.distance == 0 ? const Offset(1, 0) : v / v.distance;
Offset _normal(Offset u) => Offset(-u.dy, u.dx);

/// Centre for the text [t] placed next to point [p] of a link running along [u]:
/// above a horizontal link, beside a vertical one, never on the line.
Offset _beside(Offset p, Offset u, String t) {
  var n = _normal(u);
  if (n.dy > 0) n = -n;
  return p + n * (n.dx.abs() * (t.length * charW / 2 + 6) + n.dy.abs() * 13);
}

Scene buildScene(Document d, {bool uml = false, String? selected, String? pending}) {
  final s = Scene();
  final rects = <String, Rect>{};
  final linkHits = <(String, Rect)>[];
  int stroke(String id) => id == selected ? _sel : (id == pending ? _pend : _ink);

  // In UML a plain binary association is just a line between the two classes.
  bool direct(Association a) =>
      uml && a.legs.length == 2 && a.attributes.isEmpty && a.legs[0].entityId != a.legs[1].entityId;

  List<_Row> rows(List<Attribute> attrs) => [
        for (final a in attrs)
          uml
              ? ('${a.name}: ${d.typeName(a.type)}${a.nullable ? '?' : ''}', a.isId ? '{id}' : (a.unique ? '{unique}' : ''), false)
              : (a.name, '${d.typeName(a.type)}${a.nullable ? '?' : ''}', a.isId),
      ];

  final nodes = <(String id, String title, List<_Row> rows, int fill, double radius)>[
    for (final e in d.entities) (e.id, e.name, rows(e.attributes), 0xFFFFFFFF, 0),
    for (final a in d.associations)
      if (!direct(a)) (a.id, uml ? '«association» ${a.name}' : a.name, rows(a.attributes), 0xFFE3F2FD, uml ? 0 : 14),
    for (final e in d.enums)
      (e.id, uml ? '«enumeration» ${e.name}' : '«enum» ${e.name}', [for (final v in e.values) (v, '', false)], 0xFFF3E5F5, 0),
    for (final n in d.notes) (n.id, '', [for (final l in n.text.split('\n')) (l, '', false)], 0xFFFFF9C4, 3),
  ];

  for (final (id, title, rws, _, _) in nodes) {
    final chars = [title.length, for (final r in rws) r.$1.length + (r.$2.isEmpty ? 0 : r.$2.length + 2)].reduce(max);
    final p = d.layout[id] ?? (0, 0);
    rects[id] = Rect.fromLTWH(
      p.$1.toDouble(),
      p.$2.toDouble(),
      max(80, chars * charW + 2 * padX),
      (title.isEmpty ? 6 : headH) + (rws.isEmpty ? 0 : rws.length * rowH + 6),
    );
  }

  void text(Offset centre, String t, String key, [int color = _ink]) {
    s.shapes.add(Label(centre - const Offset(0, 8), t, align: 0, color: color));
    linkHits.add((key, Rect.fromCenter(center: centre, width: max(26, t.length * charW + 8), height: 22)));
  }

  // A cardinality sits beside the link, a little way from the end it describes.
  void card(Offset near, Offset far, String t, String key) {
    final u = _unit(far - near);
    text(_beside(near + u * 24, u, t), t, key);
  }

  for (final a in d.associations) {
    if (direct(a)) {
      final ra = rects[a.legs[0].entityId]!, rb = rects[a.legs[1].entityId]!;
      final pa = edge(ra, rb.center), pb = edge(rb, ra.center);
      s.shapes.add(Line(pa, pb, stroke(a.id)));
      text(_beside((pa + pb) / 2, _unit(pb - pa), a.name), a.name, a.id, stroke(a.id));
      // UML multiplicities are read at the opposite end from Merise cardinalities.
      card(pb, pa, _umlCard[a.legs[0].card]!, 'leg:${a.id}:0');
      card(pa, pb, _umlCard[a.legs[1].card]!, 'leg:${a.id}:1');
      // A weak entity is a composition: filled diamond on the owner's side.
      for (final (owner, other, leg) in [(pb, pa, a.legs[0]), (pa, pb, a.legs[1])]) {
        if (!leg.relative) continue;
        final u = _unit(other - owner), n = _normal(u);
        s.shapes.add(Poly([owner, owner + u * 8 + n * 5, owner + u * 16, owner + u * 8 - n * 5]));
      }
      continue;
    }
    final ra = rects[a.id]!;
    for (final (i, leg) in a.legs.indexed) {
      final re = rects[leg.entityId]!;
      // Several legs to the same entity (reflexive association) are fanned out.
      final same = [for (final (j, l) in a.legs.indexed) if (l.entityId == leg.entityId) j];
      final off = _normal(_unit(re.center - ra.center)) * ((same.indexOf(i) - (same.length - 1) / 2) * 34);
      s.shapes.add(Line(ra.center + off, re.center + off));
      final pa = edge(ra, re.center) + off, pe = edge(re, ra.center) + off;
      if (uml) {
        card(pa, pe, '${_umlCard[leg.card]}${leg.relative ? ' {id}' : ''}', 'leg:${a.id}:$i');
      } else {
        card(pe, pa, leg.relative ? '(${leg.card})' : leg.card, 'leg:${a.id}:$i');
      }
    }
  }

  for (final r in d.arrows) {
    final rf = rects[r.from], rt = rects[r.to];
    if (rf == null || rt == null) continue; // an end is a UML-inlined association
    final pa = edge(rf, rt.center), pb = edge(rt, rf.center);
    final u = _unit(pb - pa), n = _normal(u), c = r.id == selected ? _sel : _arrow;
    s.shapes
      ..add(Line(pa, pb, c))
      ..add(Poly([pb, pb - u * 11 + n * 5, pb - u * 11 - n * 5], c));
    text(_beside((pa + pb) / 2, u, r.label), r.label, r.id, c);
  }

  for (final (id, title, rws, fill, radius) in nodes) {
    final r = rects[id]!;
    final hot = id == selected || id == pending;
    s.shapes.add(Box(r, radius: radius, fill: fill, stroke: stroke(id), strokeWidth: hot ? 2.5 : 1.2));
    s.hits.add((id, r));
    if (title.isNotEmpty) {
      s.shapes.add(Label(Offset(r.center.dx, r.top + 6), title, align: 0, bold: true));
      if (rws.isNotEmpty) s.shapes.add(Line(Offset(r.left, r.top + headH), Offset(r.right, r.top + headH)));
    }
    for (final (i, row) in rws.indexed) {
      final y = r.top + (title.isEmpty ? 6 : headH + 4) + i * rowH;
      s.shapes.add(Label(Offset(r.left + padX, y), row.$1, underline: row.$3));
      if (row.$2.isNotEmpty) s.shapes.add(Label(Offset(r.right - padX, y), row.$2, align: 1, color: _grey));
    }
  }
  s.hits.addAll(linkHits);
  return s;
}

String toSvg(Scene s) {
  final b = s.bounds;
  String c(int v) => '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  String n(double v) => v.toStringAsFixed(1);
  final out = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${n(b.left)} ${n(b.top)} ${n(b.width)} ${n(b.height)}" '
      'width="${n(b.width)}" height="${n(b.height)}" font-family="monospace" font-size="$fontSize">\n'
      '<rect x="${n(b.left)}" y="${n(b.top)}" width="${n(b.width)}" height="${n(b.height)}" fill="#ffffff"/>\n');
  for (final shape in s.shapes) {
    out.writeln(switch (shape) {
      Box(:final rect, :final radius, :final fill, :final stroke, :final strokeWidth) =>
        '<rect x="${n(rect.left)}" y="${n(rect.top)}" width="${n(rect.width)}" height="${n(rect.height)}" '
            'rx="${n(radius)}" fill="${c(fill)}" stroke="${c(stroke)}" stroke-width="$strokeWidth"/>',
      Line(:final a, :final b, :final color) =>
        '<line x1="${n(a.dx)}" y1="${n(a.dy)}" x2="${n(b.dx)}" y2="${n(b.dy)}" stroke="${c(color)}" stroke-width="1.2"/>',
      Poly(:final points, :final fill) =>
        '<polygon points="${points.map((p) => '${n(p.dx)},${n(p.dy)}').join(' ')}" fill="${c(fill)}"/>',
      Label(:final pos, :final text, :final align, :final color, :final bold, :final underline) =>
        '<text x="${n(pos.dx)}" y="${n(pos.dy + fontSize * 0.9)}" text-anchor="${const ['start', 'middle', 'end'][align + 1]}" '
            'fill="${c(color)}"${bold ? ' font-weight="bold"' : ''}${underline ? ' text-decoration="underline"' : ''}>'
            '${const HtmlEscape().convert(text)}</text>',
    });
  }
  return (out..writeln('</svg>')).toString();
}
