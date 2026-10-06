import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

// Automatic rearrangement: places the boxes so that as few links as possible
// cross. Pure Dart, so it can run in an isolate and be tested on its own.
//
// Each connected component is laid out separately: several starting placements
// (the current one, plus force-directed ones) are each refined by simulated
// annealing on a cost dominated by link crossings; the best one is kept.
// The random generator is seeded, so the same diagram gives the same result.

/// A box to place: top-left corner and size.
typedef LBox = ({String id, double x, double y, double w, double h});

/// [pos] is the new top-left of every box, in whole pixels (centres are
/// lined up, so corners are not on the 10px grid). [before] and
/// [after] count link crossings. [improved] is false when nothing better than
/// the current placement was found; [pos] should then be ignored.
typedef LayoutResult = ({
  Map<String, (int, int)> pos,
  int before,
  int after,
  bool improved,
});

const _wCross = 1000.0, _wOverlap = 600.0, _wThrough = 300.0;
const _ideal = 180.0; // preferred centre-to-centre link length
const _wAlign = 0.4; // preference for horizontal or vertical links
const _wGravity = 0.03; // pull towards the middle, keeps the diagram compact
const _margin = 30.0; // free space wanted around a box

class _Graph {
  final int n;
  final Float64List x, y, w, h; // centres and sizes
  final ea = <int>[], eb = <int>[];
  late List<List<int>> inc; // edges touching each node
  double gx = 0, gy = 0; // where gravity pulls: see [centre]

  _Graph(this.n)
    : x = Float64List(n),
      y = Float64List(n),
      w = Float64List(n),
      h = Float64List(n);

  void addEdge(int a, int b) {
    if (a == b) return;
    for (var e = 0; e < ea.length; e++) {
      if ((ea[e] == a && eb[e] == b) || (ea[e] == b && eb[e] == a)) return;
    }
    ea.add(a);
    eb.add(b);
  }

  void seal() {
    inc = List.generate(n, (_) => <int>[]);
    for (var e = 0; e < ea.length; e++) {
      inc[ea[e]].add(e);
      inc[eb[e]].add(e);
    }
  }

  double _side(int p, int q, int r) =>
      (x[q] - x[p]) * (y[r] - y[p]) - (y[q] - y[p]) * (x[r] - x[p]);

  /// Do the two links properly cross? Links sharing a box never do.
  bool crosses(int e, int f) {
    final a = ea[e], b = eb[e], c = ea[f], d = eb[f];
    if (a == c || a == d || b == c || b == d) return false;
    return _side(c, d, a) * _side(c, d, b) < 0 &&
        _side(a, b, c) * _side(a, b, d) < 0;
  }

  /// Does link [e] run through box [k], which is not one of its ends? (Liang–Barsky)
  bool through(int e, int k) {
    final a = ea[e], b = eb[e];
    if (a == k || b == k) return false;
    final hw = w[k] / 2 + 6, hh = h[k] / 2 + 6;
    final dx = x[b] - x[a], dy = y[b] - y[a];
    var t0 = 0.0, t1 = 1.0;
    bool clip(double p, double q) {
      if (p == 0) return q >= 0;
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    return clip(-dx, x[a] - (x[k] - hw)) &&
        clip(dx, (x[k] + hw) - x[a]) &&
        clip(-dy, y[a] - (y[k] - hh)) &&
        clip(dy, (y[k] + hh) - y[a]);
  }

  /// 0 when the boxes keep their margin, growing with how deep they overlap.
  double overlap(int i, int j) {
    final ox = (w[i] + w[j]) / 2 + _margin - (x[i] - x[j]).abs();
    if (ox <= 0) return 0;
    final oy = (h[i] + h[j]) / 2 + _margin - (y[i] - y[j]).abs();
    if (oy <= 0) return 0;
    return 1 + min(ox, oy) / 20;
  }

  /// How far link [e] is from the ideal: right length, horizontal or vertical.
  double length(int e) {
    final dx = (x[ea[e]] - x[eb[e]]).abs(), dy = (y[ea[e]] - y[eb[e]]).abs();
    final len = sqrt(dx * dx + dy * dy);
    final d = (len - _ideal) / _ideal;
    return d * d + (len == 0 ? 0 : _wAlign * min(dx, dy) / len);
  }

  /// Fixes the gravity centre on the current middle of the boxes. It must not
  /// move during a search, or [nodeCost] deltas would no longer be exact.
  void centre() {
    gx = gy = 0;
    for (var i = 0; i < n; i++) {
      gx += x[i] / n;
      gy += y[i] / n;
    }
  }

  double gravity(int i) {
    final dx = (x[i] - gx) / _ideal, dy = (y[i] - gy) / _ideal;
    return _wGravity * (dx * dx + dy * dy);
  }

  /// Every cost term involving node [i], each counted once: moving [i]
  /// changes the total cost by exactly the change of this value.
  double nodeCost(int i) {
    var c = gravity(i);
    final mine = inc[i];
    for (final e in mine) {
      c += length(e);
      for (var f = 0; f < ea.length; f++) {
        if (crosses(e, f)) c += _wCross;
      }
      for (var k = 0; k < n; k++) {
        if (through(e, k)) c += _wThrough;
      }
    }
    for (var j = 0; j < n; j++) {
      if (j != i) c += _wOverlap * overlap(i, j);
    }
    for (var f = 0; f < ea.length; f++) {
      if (through(f, i)) c += _wThrough;
    }
    return c;
  }

  int crossings() {
    var c = 0;
    for (var e = 0; e < ea.length; e++) {
      for (var f = e + 1; f < ea.length; f++) {
        if (crosses(e, f)) c++;
      }
    }
    return c;
  }

  /// [hard] is what the eye objects to (crossings, overlaps, links through
  /// boxes); [soft] only breaks ties (link lengths and directions, compactness).
  ({double hard, double soft}) cost() {
    var hard = _wCross * crossings(), soft = 0.0;
    for (var e = 0; e < ea.length; e++) {
      soft += length(e);
      for (var k = 0; k < n; k++) {
        if (through(e, k)) hard += _wThrough;
      }
    }
    for (var i = 0; i < n; i++) {
      soft += gravity(i);
      for (var j = i + 1; j < n; j++) {
        hard += _wOverlap * overlap(i, j);
      }
    }
    return (hard: hard, soft: soft);
  }

  double total() {
    final c = cost();
    return c.hard + c.soft;
  }
}

/// Fruchterman–Reingold from random positions: a decent untangled start.
void _forceStart(_Graph g, Random rnd) {
  final n = g.n, side = sqrt(n) * _ideal * 1.2;
  for (var i = 0; i < n; i++) {
    g.x[i] = rnd.nextDouble() * side;
    g.y[i] = rnd.nextDouble() * side;
  }
  final dx = Float64List(n), dy = Float64List(n);
  const rounds = 150;
  for (var it = 0; it < rounds; it++) {
    dx.fillRange(0, n, 0);
    dy.fillRange(0, n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var vx = g.x[i] - g.x[j], vy = g.y[i] - g.y[j];
        var d = sqrt(vx * vx + vy * vy);
        if (d < 1) {
          vx = rnd.nextDouble() - 0.5;
          vy = rnd.nextDouble() - 0.5;
          d = 1;
        }
        final f = _ideal * _ideal / d / d;
        dx[i] += vx * f;
        dy[i] += vy * f;
        dx[j] -= vx * f;
        dy[j] -= vy * f;
      }
    }
    for (var e = 0; e < g.ea.length; e++) {
      final a = g.ea[e], b = g.eb[e];
      final vx = g.x[a] - g.x[b], vy = g.y[a] - g.y[b];
      final f = sqrt(vx * vx + vy * vy) / _ideal;
      dx[a] -= vx * f;
      dy[a] -= vy * f;
      dx[b] += vx * f;
      dy[b] += vy * f;
    }
    final temp = side / 6 * (1 - it / rounds) + 1;
    for (var i = 0; i < n; i++) {
      final d = sqrt(dx[i] * dx[i] + dy[i] * dy[i]);
      if (d == 0) continue;
      final step = min(d, temp) / d;
      g.x[i] += dx[i] * step;
      g.y[i] += dy[i] * step;
    }
  }
}

/// Simulated annealing; leaves [g] on the best placement met.
void _anneal(_Graph g, Random rnd, int moves, void Function(int done) tick) {
  final n = g.n;
  g.centre();
  var cur = g.total(), best = cur;
  final bx = Float64List.fromList(g.x), by = Float64List.fromList(g.y);
  const hot = 1500.0, cold = 0.5;

  bool accept(double delta, double temp) =>
      delta <= 0 || rnd.nextDouble() < exp(-delta / temp);

  for (var m = 0; m < moves; m++) {
    final t = m / moves;
    final temp = hot * pow(cold / hot, t);
    final reach = 400 * (1 - t) + 15;
    final kind = rnd.nextDouble();
    final i = rnd.nextInt(n);
    var moved = false;

    if (kind < 0.08) {
      // Swap two boxes: untangles what small shifts cannot.
      final j = rnd.nextInt(n);
      if (j != i) {
        void swap() {
          final tx = g.x[i], ty = g.y[i];
          g.x[i] = g.x[j];
          g.y[i] = g.y[j];
          g.x[j] = tx;
          g.y[j] = ty;
        }

        swap();
        final next = g.total();
        if (accept(next - cur, temp)) {
          cur = next;
          moved = true;
        } else {
          swap();
        }
      }
    } else {
      final before = g.nodeCost(i), ox = g.x[i], oy = g.y[i];
      final links = g.inc[i];
      if (kind < 0.25 && links.length >= 2) {
        // Pull a box to the middle of what it is linked to.
        var sx = 0.0, sy = 0.0;
        for (final e in links) {
          final o = g.ea[e] == i ? g.eb[e] : g.ea[e];
          sx += g.x[o];
          sy += g.y[o];
        }
        g.x[i] = sx / links.length + (rnd.nextDouble() - 0.5) * 20;
        g.y[i] = sy / links.length + (rnd.nextDouble() - 0.5) * 20;
      } else {
        g.x[i] += (rnd.nextDouble() - 0.5) * 2 * reach;
        g.y[i] += (rnd.nextDouble() - 0.5) * 2 * reach;
      }
      final delta = g.nodeCost(i) - before;
      if (accept(delta, temp)) {
        cur += delta;
        moved = true;
      } else {
        g.x[i] = ox;
        g.y[i] = oy;
      }
    }

    if (moved && cur < best - 1e-9) {
      best = cur;
      bx.setAll(0, g.x);
      by.setAll(0, g.y);
    }
    if (m & 4095 == 4095) tick(m + 1);
  }
  g.x.setAll(0, bx);
  g.y.setAll(0, by);
}

/// Snaps top-left corners to the 10px grid and pushes apart boxes still touching.
void _tidy(_Graph g) {
  double snap(double v) => (v / 10).round() * 10.0;
  for (var i = 0; i < g.n; i++) {
    g.x[i] = snap(g.x[i] - g.w[i] / 2) + g.w[i] / 2;
    g.y[i] = snap(g.y[i] - g.h[i] / 2) + g.h[i] / 2;
  }
  const gap = 20.0;
  for (var pass = 0; pass < 60; pass++) {
    var clean = true;
    for (var i = 0; i < g.n; i++) {
      for (var j = i + 1; j < g.n; j++) {
        final ox = (g.w[i] + g.w[j]) / 2 + gap - (g.x[i] - g.x[j]).abs();
        final oy = (g.h[i] + g.h[j]) / 2 + gap - (g.y[i] - g.y[j]).abs();
        if (ox <= 0 || oy <= 0) continue;
        clean = false;
        if (ox < oy) {
          final d = (ox / 20).ceil() * 10.0 * (g.x[i] < g.x[j] ? 1 : -1);
          g.x[i] -= d;
          g.x[j] += d;
        } else {
          final d = (oy / 20).ceil() * 10.0 * (g.y[i] < g.y[j] ? 1 : -1);
          g.y[i] -= d;
          g.y[j] += d;
        }
      }
    }
    if (clean) break;
  }
}

/// Makes nearly horizontal or vertical links exactly so, by lining up the
/// centres of their two boxes whenever that costs nothing else.
void _straighten(_Graph g) {
  for (var pass = 0; pass < 3; pass++) {
    for (var e = 0; e < g.ea.length; e++) {
      final a = g.ea[e], b = g.eb[e];
      // Move the less connected box: it drags fewer other links along.
      final i = g.inc[a].length <= g.inc[b].length ? a : b, j = i == a ? b : a;
      for (final axis in [g.x, g.y]) {
        final off = (axis[i] - axis[j]).abs();
        if (off == 0 || off > 40) continue;
        final before = g.nodeCost(i), old = axis[i];
        axis[i] = axis[j];
        if (g.nodeCost(i) > before + 0.05) axis[i] = old;
      }
    }
  }
}

/// Rearranges [boxes] linked by [edges] (pairs of box ids).
/// [onProgress] gets a 0..1 fraction and the best crossing count so far.
LayoutResult autoLayout(
  List<LBox> boxes,
  List<(String, String)> edges, {
  void Function(double progress, int crossings)? onProgress,
}) {
  final index = {for (final (i, b) in boxes.indexed) b.id: i};
  final n = boxes.length;

  _Graph build(List<int> nodes) {
    final local = {for (final (i, v) in nodes.indexed) v: i};
    final g = _Graph(nodes.length);
    for (final (i, v) in nodes.indexed) {
      final b = boxes[v];
      g.w[i] = b.w;
      g.h[i] = b.h;
      g.x[i] = b.x + b.w / 2;
      g.y[i] = b.y + b.h / 2;
    }
    for (final (a, b) in edges) {
      final ia = local[index[a]], ib = local[index[b]];
      if (ia != null && ib != null) g.addEdge(ia, ib);
    }
    return g..seal();
  }

  final whole = build([for (var i = 0; i < n; i++) i])..centre();
  final before = whole.cost(), crossBefore = whole.crossings();

  // Connected components, biggest first; lone boxes end up last.
  final comp = List.filled(n, -1);
  final comps = <List<int>>[];
  for (var s = 0; s < n; s++) {
    if (comp[s] != -1) continue;
    final members = <int>[s];
    comp[s] = comps.length;
    for (var q = 0; q < members.length; q++) {
      for (final e in whole.inc[members[q]]) {
        final o = whole.ea[e] == members[q] ? whole.eb[e] : whole.ea[e];
        if (comp[o] == -1) {
          comp[o] = comps.length;
          members.add(o);
        }
      }
    }
    comps.add(members);
  }
  comps.sort((a, b) => b.length.compareTo(a.length));

  int starts(int size) => size <= 2 ? 1 : (size > 60 ? 3 : 6);
  int moves(int size) =>
      size < 2 ? 0 : (size * 3000).clamp(15000, 250000).toInt();
  final work = comps.fold(0, (s, c) => s + starts(c.length) * moves(c.length));
  var done = 0;
  // Crossings of components not optimised yet, for the live counter.
  final graphs = [for (final c in comps) build(c)];
  final pending = [for (final g in graphs) g.crossings()];
  var settled = 0;

  final px = Float64List(n), py = Float64List(n); // new top-left corners
  var shelfX = 0.0, shelfY = 0.0, shelfH = 0.0;
  final shelfW = max(1400.0, sqrt(n) * 420);

  for (final (ci, nodes) in comps.indexed) {
    final g = graphs[ci], size = nodes.length;
    final rnd = Random(20240607 + size * 31 + g.ea.length);
    var bestCost = double.infinity, bestCross = pending[ci];
    final bx = Float64List.fromList(g.x), by = Float64List.fromList(g.y);
    final upcoming = pending.skip(ci + 1).fold(0, (a, b) => a + b);

    for (var s = 0; s < starts(size); s++) {
      if (s > 0) _forceStart(g, rnd); // start 0 is the current placement
      final base = done;
      _anneal(g, rnd, moves(size), (m) {
        onProgress?.call((base + m) / work, settled + bestCross + upcoming);
      });
      done = base + moves(size);
      _tidy(g);
      g.centre();
      _straighten(g);
      final c = g.total();
      if (c < bestCost) {
        bestCost = c;
        bestCross = g.crossings();
        bx.setAll(0, g.x);
        by.setAll(0, g.y);
      }
    }
    settled += bestCross;

    // Shelf-pack the components next to each other.
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    for (var i = 0; i < size; i++) {
      left = min(left, bx[i] - g.w[i] / 2);
      top = min(top, by[i] - g.h[i] / 2);
      right = max(right, bx[i] + g.w[i] / 2);
      bottom = max(bottom, by[i] + g.h[i] / 2);
    }
    if (shelfX > 0 && shelfX + (right - left) > shelfW) {
      shelfX = 0;
      shelfY += shelfH + 60;
      shelfH = 0;
    }
    for (final (i, v) in nodes.indexed) {
      px[v] = bx[i] - g.w[i] / 2 - left + shelfX + 40;
      py[v] = by[i] - g.h[i] / 2 - top + shelfY + 40;
    }
    shelfX += right - left + 60;
    shelfH = max(shelfH, bottom - top);
  }

  for (var i = 0; i < n; i++) {
    whole.x[i] = px[i] + whole.w[i] / 2;
    whole.y[i] = py[i] + whole.h[i] / 2;
  }
  whole.centre();
  final after = whole.cost();
  onProgress?.call(1, whole.crossings());
  return (
    pos: {
      for (final (i, b) in boxes.indexed) b.id: (px[i].round(), py[i].round()),
    },
    before: crossBefore,
    after: whole.crossings(),
    // A clean placement is only replaced when link lengths get clearly
    // better (mean squared relative error down by 0.05), so rearranging an
    // already arranged diagram does not reshuffle it.
    improved:
        after.hard < before.hard - 1e-6 ||
        (after.hard <= before.hard + 1e-6 &&
            after.soft < before.soft - 0.05 * whole.ea.length),
  );
}

/// Isolate entry point: sends `(progress, crossings)` records, then the [LayoutResult].
void layoutIsolate((SendPort, List<LBox>, List<(String, String)>) message) {
  final (port, boxes, edges) = message;
  port.send(
    autoLayout(boxes, edges, onProgress: (p, cross) => port.send((p, cross))),
  );
}
