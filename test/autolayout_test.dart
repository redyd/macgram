import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:macgram/autolayout.dart';

/// Boxes for [n] nodes scattered at random, so the links start tangled.
List<LBox> scatter(int n, [int seed = 1]) {
  final rnd = Random(seed);
  return [
    for (var i = 0; i < n; i++)
      (
        id: 'n$i',
        x: rnd.nextDouble() * 900,
        y: rnd.nextDouble() * 900,
        w: 110.0 + (i % 3) * 30,
        h: 50.0 + (i % 4) * 20,
      ),
  ];
}

/// Entities joined through an association box each, like a real MCD.
(List<LBox>, List<(String, String)>) mcd(
  int entities,
  List<(int, int)> relations, [
  int seed = 1,
]) {
  final boxes = scatter(entities + relations.length, seed);
  return (
    boxes,
    [
      for (final (i, (a, b)) in relations.indexed) ...[
        ('n${entities + i}', 'n$a'),
        ('n${entities + i}', 'n$b'),
      ],
    ],
  );
}

bool overlapping(List<LBox> boxes, Map<String, (int, int)> pos) {
  for (final a in boxes) {
    for (final b in boxes) {
      if (a.id.compareTo(b.id) >= 0) continue;
      final (ax, ay) = pos[a.id]!;
      final (bx, by) = pos[b.id]!;
      if (ax < bx + b.w && bx < ax + a.w && ay < by + b.h && by < ay + a.h) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  final planar = {
    'ring of 6': mcd(6, [for (var i = 0; i < 6; i++) (i, (i + 1) % 6)]),
    'star of 7': mcd(8, [for (var i = 1; i < 8; i++) (0, i)]),
    'grid 3x3': mcd(9, [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) ...[
          if (c < 2) (r * 3 + c, r * 3 + c + 1),
          if (r < 2) (r * 3 + c, r * 3 + c + 3),
        ],
    ]),
  };
  for (final MapEntry(key: name, value: (boxes, edges)) in planar.entries) {
    test('planar $name: untangled completely, no overlap', () {
      final r = autoLayout(boxes, edges);
      expect(
        r.before,
        greaterThan(0),
        reason: 'the scattered start should be tangled',
      );
      expect(r.after, 0);
      expect(r.improved, isTrue);
      expect(overlapping(boxes, r.pos), isFalse);
      expect(r.pos.values.every((p) => p.$1 >= 0 && p.$2 >= 0), isTrue);
    });
  }

  test(
    'non-planar (K5 through associations): never worse, and deterministic',
    () {
      final (boxes, edges) = mcd(5, [
        for (var a = 0; a < 5; a++)
          for (var b = a + 1; b < 5; b++) (a, b),
      ]);
      final r = autoLayout(boxes, edges);
      expect(r.after, lessThanOrEqualTo(r.before));
      expect(
        r.after,
        greaterThan(0),
        reason: 'K5 cannot be drawn without crossings',
      );
      expect(autoLayout(boxes, edges).pos, r.pos);
    },
  );

  test('rearranging the result again leaves it alone', () {
    final (boxes, edges) = planar['grid 3x3']!;
    final first = autoLayout(boxes, edges);
    final placed = [
      for (final b in boxes)
        (
          id: b.id,
          x: first.pos[b.id]!.$1.toDouble(),
          y: first.pos[b.id]!.$2.toDouble(),
          w: b.w,
          h: b.h,
        ),
    ];
    expect(autoLayout(placed, edges).improved, isFalse);
  });

  test('spacing: a wider setting spreads the same diagram further out', () {
    final (boxes, edges) = planar['ring of 6']!;
    double span(double spacing) {
      final r = autoLayout(boxes, edges, spacing: spacing);
      expect(r.after, 0);
      expect(overlapping(boxes, r.pos), isFalse);
      final xs = r.pos.values.map((p) => p.$1),
          ys = r.pos.values.map((p) => p.$2);
      return (xs.reduce(max) - xs.reduce(min) + ys.reduce(max) - ys.reduce(min))
          .toDouble();
    }

    final tight = span(0.5), normal = span(1), wide = span(2.5);
    expect(tight, lessThan(normal));
    expect(normal, lessThan(wide));
  });

  test('separate components and lone boxes do not land on each other', () {
    final (a, ea) = mcd(4, [(0, 1), (1, 2), (2, 3)]);
    final boxes = [
      ...a,
      for (var i = 0; i < 4; i++)
        (id: 'lone$i', x: 100.0, y: 100.0, w: 120.0, h: 60.0),
    ];
    final r = autoLayout(boxes, ea);
    expect(r.after, 0);
    expect(overlapping(boxes, r.pos), isFalse);
  });

  test('a 40-entity schema finishes in reasonable time and reports progress', () {
    final rnd = Random(7);
    final (boxes, edges) = mcd(40, [
      for (var i = 1; i < 40; i++) (rnd.nextInt(i), i),
      for (var i = 0; i < 8; i++) (rnd.nextInt(40), rnd.nextInt(40)),
    ]);
    final seen = <double>[];
    final watch = Stopwatch()..start();
    final r = autoLayout(boxes, edges, onProgress: (p, _) => seen.add(p));
    printOnFailure(
      'took ${watch.elapsed}, crossings ${r.before} -> ${r.after}',
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 60)));
    expect(r.after, lessThan(r.before ~/ 4));
    expect(seen.last, 1);
    expect(
      [for (var i = 1; i < seen.length; i++) seen[i] >= seen[i - 1]]
          .every((x) => x),
      isTrue,
    );
    // ignore: avoid_print
    print(
      '40 entities: ${watch.elapsedMilliseconds} ms, crossings ${r.before} -> ${r.after}',
    );
  });
}
