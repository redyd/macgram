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

/// Diagram colours (ARGB). Exports always use [light].
class Palette {
  final int ink, grey, sel, pend, arrow, entity, association, enumType, note;
  final int canvas, dot;
  const Palette({
    required this.ink,
    required this.grey,
    required this.sel,
    required this.pend,
    required this.arrow,
    required this.entity,
    required this.association,
    required this.enumType,
    required this.note,
    required this.canvas,
    required this.dot,
  });

  static const light = Palette(
    ink: 0xFF263238,
    grey: 0xFF78909C,
    sel: 0xFF1565C0,
    pend: 0xFFEF6C00,
    arrow: 0xFF6D4C41,
    entity: 0xFFFFFFFF,
    association: 0xFFE3F2FD,
    enumType: 0xFFF3E5F5,
    note: 0xFFFFF9C4,
    canvas: 0xFFF4F4F0,
    dot: 0xFFD6D6CE,
  );

  static const dark = Palette(
    ink: 0xFFE4E7EE,
    grey: 0xFF8892A6,
    sel: 0xFF7AB7FF,
    pend: 0xFFFFB454,
    arrow: 0xFFD7A77B,
    entity: 0xFF232831,
    association: 0xFF1C3350,
    enumType: 0xFF37285A,
    note: 0xFF4A4020,
    canvas: 0xFF14171C,
    dot: 0xFF2A303B,
  );
}

sealed class Shape {
  const Shape();
}

class Box extends Shape {
  final Rect rect;
  final double radius, strokeWidth;
  final int fill, stroke;
  const Box(
    this.rect, {
    this.radius = 0,
    required this.fill,
    required this.stroke,
    this.strokeWidth = 1.2,
  });
}

class Line extends Shape {
  final Offset a, b;
  final int color;
  const Line(this.a, this.b, this.color);
}

class Poly extends Shape {
  final List<Offset> points;
  final int fill;
  const Poly(this.points, this.fill);
}

class Label extends Shape {
  /// Top of the text line; [align] says which x it is: -1 left, 0 centre, 1 right.
  final Offset pos;
  final String text;
  final int align, color;
  final bool bold, underline;
  const Label(
    this.pos,
    this.text, {
    this.align = -1,
    required this.color,
    this.bold = false,
    this.underline = false,
  });
}

class Scene {
  final shapes = <Shape>[];

  /// Clickable regions, later entries on top. Keys are item ids,
  /// `leg:<associationId>:<index>` (a cardinality or link note),
  /// `bend|<link>|<index>` (a break point) or `resize|<noteId>`.
  final hits = <(String, Rect)>[];

  /// Clickable link segments, below every region: `seg|<link>|<index>`.
  final segs = <(String, Offset, Offset)>[];

  String? hit(Offset p) =>
      hits.reversed.where((h) => h.$2.contains(p)).firstOrNull?.$1 ??
      segs.where((s) => _distance(p, s.$2, s.$3) < 6).firstOrNull?.$1;

  Rect get bounds => hits.isEmpty
      ? const Rect.fromLTWH(0, 0, 400, 300)
      : hits
            .map((h) => h.$2)
            .reduce((a, b) => a.expandToInclude(b))
            .inflate(30);
}

double _distance(Offset p, Offset a, Offset b) {
  final ab = b - a, ap = p - a;
  final t = ab.distanceSquared == 0
      ? 0.0
      : ((ap.dx * ab.dx + ap.dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Word wrap to [cols] characters. ponytail: a word longer than the line overflows, it is not split.
List<String> wrap(String text, int cols) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    var cur = '';
    for (final w in line.split(' ')) {
      if (cur.isEmpty) {
        cur = w;
      } else if (cur.length + 1 + w.length <= cols) {
        cur = '$cur $w';
      } else {
        out.add(cur);
        cur = w;
      }
    }
    out.add(cur);
  }
  return out;
}

typedef _Row = (String left, String right, bool underline);

const _umlCard = {'0,1': '0..1', '1,1': '1', '0,n': '*', '1,n': '1..*'};

/// Where the segment from the centre of [r] towards [to] leaves [r].
Offset edge(Rect r, Offset to) {
  final d = to - r.center;
  if (d == Offset.zero) return r.center;
  final k = min(
    r.width / 2 / max(d.dx.abs(), 1e-9),
    r.height / 2 / max(d.dy.abs(), 1e-9),
  );
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

Scene buildScene(
  Document d, {
  bool uml = false,
  String? selected,
  String? pending,
  Palette pal = Palette.light,

  /// Editing handles (break points, note resize grip); off for exports.
  bool handles = true,
}) {
  final s = Scene();
  final rects = <String, Rect>{};
  final linkHits = <(String, Rect)>[];
  int stroke(String id) =>
      id == selected ? pal.sel : (id == pending ? pal.pend : pal.ink);

  // In UML a plain binary association is just a line between the two classes.
  bool direct(Association a) =>
      uml &&
      a.legs.length == 2 &&
      a.attributes.isEmpty &&
      a.legs[0].entityId != a.legs[1].entityId;

  List<_Row> rows(List<Attribute> attrs) => [
    for (final a in attrs)
      uml
          ? (
              '${a.name}: ${d.typeName(a.type)}${a.nullable ? '?' : ''}',
              a.isId ? '{id}' : (a.unique ? '{unique}' : ''),
              false,
            )
          : (a.name, '${d.typeName(a.type)}${a.nullable ? '?' : ''}', a.isId),
  ];

  List<_Row> noteRows(Note n) {
    final cols = n.size == null
        ? 1 << 20
        : max(1, ((n.size!.$1 - 2 * padX) / charW).floor());
    return [for (final l in wrap(n.text, cols)) (l, '', false)];
  }

  final nodes =
      <
        (
          String id,
          String title,
          List<_Row> rows,
          int fill,
          double radius,
          Pt? size,
        )
      >[
        for (final e in d.entities)
          (e.id, e.name, rows(e.attributes), pal.entity, 0, null),
        for (final a in d.associations)
          if (!direct(a))
            (
              a.id,
              uml ? '«association» ${a.name}' : a.name,
              rows(a.attributes),
              pal.association,
              uml ? 0 : 14,
              null,
            ),
        for (final e in d.enums)
          (
            e.id,
            e.name,
            [for (final v in e.values) (v, '', false)],
            pal.enumType,
            0,
            null,
          ),
        for (final n in d.notes) (n.id, '', noteRows(n), pal.note, 3, n.size),
      ];

  for (final (id, title, rws, _, _, size) in nodes) {
    final chars = [
      title.length,
      for (final r in rws) r.$1.length + (r.$2.isEmpty ? 0 : r.$2.length + 2),
    ].reduce(max);
    final p = d.layout[id] ?? (0, 0);
    final h =
        (title.isEmpty ? 6 : headH) + (rws.isEmpty ? 0 : rws.length * rowH + 6);
    rects[id] = Rect.fromLTWH(
      p.$1.toDouble(),
      p.$2.toDouble(),
      size?.$1.toDouble() ?? max(80, chars * charW + 2 * padX),
      max(h.toDouble(), size?.$2.toDouble() ?? 0),
    );
  }

  void text(Offset centre, String t, String key, [int? color]) {
    s.shapes.add(
      Label(centre - const Offset(0, 8), t, align: 0, color: color ?? pal.ink),
    );
    linkHits.add((
      key,
      Rect.fromCenter(
        center: centre,
        width: max(26, t.length * charW + 8),
        height: 22,
      ),
    ));
  }

  // A cardinality sits beside the link, a little way from the end it describes.
  void card(Offset near, Offset far, String t, String key) {
    final u = _unit(far - near);
    text(_beside(near + u * 24, u, t), t, key);
  }

  // Draws the link [key] from ra to rb through its break points and returns
  // its points, the first and last being on the edges of the two boxes.
  // [hideEnds] runs the line to the box centres, under the boxes.
  List<Offset> link(
    String key,
    Rect ra,
    Rect rb,
    List<Pt> bends,
    int color, {
    Offset off = Offset.zero,
    bool hideEnds = false,
  }) {
    final inner = [
      for (final (x, y) in bends) Offset(x.toDouble(), y.toDouble()),
    ];
    if (inner.isNotEmpty) off = Offset.zero;
    final pts = [
      edge(ra, inner.isEmpty ? rb.center : inner.first) + off,
      ...inner,
      edge(rb, inner.isEmpty ? ra.center : inner.last) + off,
    ];
    final drawn = hideEnds ? [ra.center + off, ...inner, rb.center + off] : pts;
    for (var j = 0; j + 1 < drawn.length; j++) {
      s.shapes.add(Line(drawn[j], drawn[j + 1], color));
      s.segs.add(('seg|$key|$j', drawn[j], drawn[j + 1]));
    }
    for (final (j, b) in handles ? inner.indexed : const <(int, Offset)>[]) {
      s.shapes.add(
        Box(
          Rect.fromCircle(center: b, radius: 4.5),
          radius: 4.5,
          fill: pal.entity,
          stroke: color,
        ),
      );
      linkHits.add(('bend|$key|$j', Rect.fromCircle(center: b, radius: 8)));
    }
    return pts;
  }

  // Middle of a link and its direction there, to hang a label on it.
  (Offset, Offset) middle(List<Offset> p) {
    final j = (p.length - 2) ~/ 2;
    return ((p[j] + p[j + 1]) / 2, _unit(p[j + 1] - p[j]));
  }

  for (final a in d.associations) {
    if (direct(a)) {
      // ponytail: this straight class-to-class line ignores the legs' break
      // points, which are relative to the Merise association box.
      final ra = rects[a.legs[0].entityId]!, rb = rects[a.legs[1].entityId]!;
      final pa = edge(ra, rb.center),
          pb = edge(rb, ra.center),
          mid = (pa + pb) / 2;
      s.shapes.add(Line(pa, pb, stroke(a.id)));
      text(_beside(mid, _unit(pb - pa), a.name), a.name, a.id, stroke(a.id));
      // UML multiplicities are read at the opposite end from Merise cardinalities.
      card(pb, pa, _umlCard[a.legs[0].card]!, 'leg:${a.id}:0');
      card(pa, pb, _umlCard[a.legs[1].card]!, 'leg:${a.id}:1');
      s.segs
        ..add(('leg:${a.id}:1', pa, mid))
        ..add(('leg:${a.id}:0', mid, pb));
      // A weak entity is a composition: filled diamond on the owner's side.
      for (final (owner, other, leg) in [
        (pb, pa, a.legs[0]),
        (pa, pb, a.legs[1]),
      ]) {
        if (!leg.relative) continue;
        final u = _unit(other - owner), n = _normal(u);
        s.shapes.add(
          Poly([
            owner,
            owner + u * 8 + n * 5,
            owner + u * 16,
            owner + u * 8 - n * 5,
          ], pal.ink),
        );
      }
      continue;
    }
    final ra = rects[a.id]!;
    for (final (i, leg) in a.legs.indexed) {
      final re = rects[leg.entityId]!, key = 'leg:${a.id}:$i';
      // Several legs to the same entity (reflexive association) are fanned out.
      final same = [
        for (final (j, l) in a.legs.indexed)
          if (l.entityId == leg.entityId) j,
      ];
      final off =
          _normal(_unit(re.center - ra.center)) *
          ((same.indexOf(i) - (same.length - 1) / 2) * 34);
      final pts = link(
        key,
        ra,
        re,
        leg.bends,
        pal.ink,
        off: off,
        hideEnds: true,
      );
      if (uml) {
        card(
          pts.first,
          pts[1],
          '${_umlCard[leg.card]}${leg.relative ? ' {id}' : ''}',
          key,
        );
      } else {
        card(
          pts.last,
          pts[pts.length - 2],
          leg.relative ? '(${leg.card})' : leg.card,
          key,
        );
      }
      if (leg.note.isNotEmpty) {
        final (m, u) = middle(pts);
        text(_beside(m, u, leg.note), leg.note, key, pal.grey);
      }
    }
  }

  for (final r in d.arrows) {
    final rf = rects[r.from], rt = rects[r.to];
    if (rf == null || rt == null) {
      continue; // an end is a UML-inlined association
    }
    final c = r.id == selected ? pal.sel : pal.arrow;
    final pts = link(r.id, rf, rt, r.bends, c);
    final tip = pts.last, u = _unit(tip - pts[pts.length - 2]), n = _normal(u);
    s.shapes.add(Poly([tip, tip - u * 11 + n * 5, tip - u * 11 - n * 5], c));
    if (r.label.isNotEmpty) {
      final (m, dir) = middle(pts);
      text(_beside(m, dir, r.label), r.label, r.id, c);
    }
  }

  for (final (id, title, rws, fill, radius, _) in nodes) {
    final r = rects[id]!;
    final hot = id == selected || id == pending;
    s.shapes.add(
      Box(
        r,
        radius: radius,
        fill: fill,
        stroke: stroke(id),
        strokeWidth: hot ? 2.5 : 1.2,
      ),
    );
    s.hits.add((id, r));
    if (title.isNotEmpty) {
      s.shapes.add(
        Label(
          Offset(r.center.dx, r.top + 6),
          title,
          align: 0,
          bold: true,
          color: pal.ink,
        ),
      );
      if (rws.isNotEmpty) {
        s.shapes.add(
          Line(
            Offset(r.left, r.top + headH),
            Offset(r.right, r.top + headH),
            pal.ink,
          ),
        );
      }
    }
    for (final (i, row) in rws.indexed) {
      final y = r.top + (title.isEmpty ? 6 : headH + 4) + i * rowH;
      s.shapes.add(
        Label(
          Offset(r.left + padX, y),
          row.$1,
          underline: row.$3,
          color: pal.ink,
        ),
      );
      if (row.$2.isNotEmpty) {
        s.shapes.add(
          Label(Offset(r.right - padX, y), row.$2, align: 1, color: pal.grey),
        );
      }
    }
    if (handles && id.startsWith('n-')) {
      // Resize grip in the bottom-right corner of a note.
      final c = r.bottomRight;
      s.shapes.add(
        Poly([
          c - const Offset(11, 2),
          c - const Offset(2, 11),
          c - const Offset(2, 2),
        ], pal.grey),
      );
      linkHits.add((
        'resize|$id',
        Rect.fromLTRB(c.dx - 13, c.dy - 13, c.dx + 3, c.dy + 3),
      ));
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
    '<rect x="${n(b.left)}" y="${n(b.top)}" width="${n(b.width)}" height="${n(b.height)}" fill="#ffffff"/>\n',
  );
  for (final shape in s.shapes) {
    out.writeln(switch (shape) {
      Box(
        :final rect,
        :final radius,
        :final fill,
        :final stroke,
        :final strokeWidth,
      ) =>
        '<rect x="${n(rect.left)}" y="${n(rect.top)}" width="${n(rect.width)}" height="${n(rect.height)}" '
            'rx="${n(radius)}" fill="${c(fill)}" stroke="${c(stroke)}" stroke-width="$strokeWidth"/>',
      Line(:final a, :final b, :final color) =>
        '<line x1="${n(a.dx)}" y1="${n(a.dy)}" x2="${n(b.dx)}" y2="${n(b.dy)}" stroke="${c(color)}" stroke-width="1.2"/>',
      Poly(:final points, :final fill) =>
        '<polygon points="${points.map((p) => '${n(p.dx)},${n(p.dy)}').join(' ')}" fill="${c(fill)}"/>',
      Label(
        :final pos,
        :final text,
        :final align,
        :final color,
        :final bold,
        :final underline,
      ) =>
        '<text x="${n(pos.dx)}" y="${n(pos.dy + fontSize * 0.9)}" text-anchor="${const ['start', 'middle', 'end'][align + 1]}" '
            'fill="${c(color)}"${bold ? ' font-weight="bold"' : ''}${underline ? ' text-decoration="underline"' : ''}>'
            '${const HtmlEscape().convert(text)}</text>',
    });
  }
  return (out..writeln('</svg>')).toString();
}
