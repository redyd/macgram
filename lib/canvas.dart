import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'dialogs.dart';
import 'scene.dart';

void paintScene(Canvas canvas, Scene s) {
  for (final shape in s.shapes) {
    switch (shape) {
      case Box(
        :final rect,
        :final radius,
        :final fill,
        :final stroke,
        :final strokeWidth,
      ):
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        canvas
          ..drawRRect(rr, Paint()..color = Color(fill))
          ..drawRRect(
            rr,
            Paint()
              ..color = Color(stroke)
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth,
          );
      case Line(:final a, :final b, :final color, :final width):
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = Color(color)
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
      case Poly(:final points, :final fill):
        canvas.drawPath(
          Path()..addPolygon(points, true),
          Paint()..color = Color(fill),
        );
      case Label(
        :final pos,
        :final text,
        :final align,
        :final color,
        :final bold,
        :final underline,
      ):
        final tp = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: monoFont,
              fontSize: fontSize,
              color: Color(color),
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              // Explicit axis value: the bundled font is a variable font.
              fontVariations: [ui.FontVariation.weight(bold ? 700 : 400)],
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        )..layout();
        tp.paint(canvas, Offset(pos.dx - tp.width * (align + 1) / 2, pos.dy));
    }
  }
}

Future<Uint8List> toPng(Scene s, {double scale = 2}) async {
  final b = s.bounds;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(-b.left, -b.top)
    ..drawRect(b, Paint()..color = Color(s.pal.canvas));
  paintScene(canvas, s);
  final image = await recorder.endRecording().toImage(
    (b.width * scale).ceil(),
    (b.height * scale).ceil(),
  );
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

class _Painter extends CustomPainter {
  final Palette pal;
  final Scene scene;
  final Offset pan;
  final double zoom;

  /// Rubber band being drawn, in scene coordinates.
  final Rect? band;
  _Painter(this.scene, this.pan, this.zoom, this.pal, this.band);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    if (zoom >= 0.5) {
      // Dot grid, anchored to the scene so it pans and zooms with it.
      final step = 20 * zoom;
      canvas.drawPoints(
        ui.PointMode.points,
        [
          for (var x = pan.dx % step; x < size.width; x += step)
            for (var y = pan.dy % step; y < size.height; y += step)
              Offset(x, y),
        ],
        Paint()
          ..color = Color(pal.dot)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas
      ..translate(pan.dx, pan.dy)
      ..scale(zoom);
    paintScene(canvas, scene);
    if (band case final band?) {
      canvas
        ..drawRect(band, Paint()..color = Color(pal.sel).withValues(alpha: 0.1))
        ..drawRect(
          band,
          Paint()
            ..color = Color(pal.sel)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / zoom,
        );
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}

class DiagramCanvas extends StatefulWidget {
  final Controller c;
  const DiagramCanvas(this.c, {super.key});

  @override
  State<DiagramCanvas> createState() => _DiagramCanvasState();
}

class _DiagramCanvasState extends State<DiagramCanvas> {
  static const _doubleClick = Duration(milliseconds: 300);

  final _focus = FocusNode();
  Offset _pan = Offset.zero, _raw = Offset.zero;
  double _zoom = 1;
  String? _down, _drag, _lastTap, _hover;
  bool _panning = false;

  // Rubber-band selection: where the left button went down on empty canvas,
  // and where the pointer is now (scene coordinates).
  Offset _downAt = Offset.zero;
  Offset? _bandFrom, _bandTo;
  Rect? get _band =>
      _bandFrom == null ? null : Rect.fromPoints(_bandFrom!, _bandTo!);
  DateTime _lastTapAt = DateTime(0);
  Timer? _legTimer;
  MouseCursor _cursor = SystemMouseCursors.basic;
  late Scene _scene;

  Controller get c => widget.c;
  Offset _toScene(Offset p) => (p - _pan) / _zoom;

  @override
  void dispose() {
    _legTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _tap(Offset local) {
    final p = _toScene(local), key = _scene.hit(p);
    final wasSelect = c.tool == Tool.select;
    c.tap(key, p);
    if (!wasSelect ||
        key == null ||
        key.startsWith('bend|') ||
        key.startsWith('resize|')) {
      return;
    }

    // Double click is detected here rather than with onDoubleTap, which would delay every single click.
    final target = Controller.linkOf(key) ?? key;
    final now = DateTime.now();
    final twice =
        target == _lastTap && now.difference(_lastTapAt) < _doubleClick;
    _lastTap = twice ? null : target;
    _lastTapAt = now;

    if (target.startsWith('leg:')) {
      // Only links wait for a possible second click: one click edits the
      // cardinality, two go straight to the note.
      _legTimer?.cancel();
      if (twice) {
        showLegDialog(context, c, target, focusNote: true);
      } else {
        _legTimer = Timer(_doubleClick, () {
          if (mounted) showLegDialog(context, c, target);
        });
      }
    } else if (twice) {
      showItemDialog(context, c, target);
    }
  }

  void _dragStart() {
    final key = _down;
    if (c.tool != Tool.select) return;
    if (key == null) {
      setState(() => _bandFrom = _bandTo = _downAt);
      return;
    }
    if (c.group.contains(key)) {
      c.startGroupMove();
    } else if (key.startsWith('bend|')) {
      _raw = _scene.hits.firstWhere((h) => h.$1 == key).$2.center;
    } else if (key.startsWith('resize|')) {
      final r = _scene.hits.firstWhere((h) => h.$1 == key.substring(7)).$2;
      _raw = Offset(r.width, r.height);
    } else if (c.doc.layout[key] case (final x, final y)) {
      _raw = Offset(x.toDouble(), y.toDouble());
      c.select(key);
    } else {
      return;
    }
    _drag = key;
  }

  void _dragUpdate(Offset delta, Offset at) => setState(() {
    if (_bandFrom != null) {
      _bandTo = at;
      c.selectGroup({
        for (final (id, r) in _scene.hits)
          if (c.doc.layout.containsKey(id) && r.overlaps(_band!)) id,
      });
      return;
    }
    final key = _drag;
    if (key == null) return;
    _raw += delta / _zoom;
    if (c.group.contains(key)) {
      c.moveGroup(at - _downAt);
    } else if (key.startsWith('bend|')) {
      c.moveBend(key, _raw);
    } else if (key.startsWith('resize|')) {
      c.resizeNote(key.substring(7), _raw);
    } else {
      c.move(key, _raw);
    }
  });

  /// The cursor says what a click or drag would do at [local].
  MouseCursor _cursorAt(Offset local) {
    final key = _scene.hit(_toScene(local));
    if (c.tool != Tool.select) {
      return key != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.precise;
    }
    if (key == null) return SystemMouseCursors.basic;
    if (key.startsWith('resize|')) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }
    if (key.startsWith('bend|') || c.doc.layout.containsKey(key)) {
      return SystemMouseCursors.grab;
    }
    return SystemMouseCursors.click;
  }

  @override
  Widget build(BuildContext context) {
    final pal = Theme.of(context).brightness == Brightness.dark
        ? Palette.dark
        : Palette.light;
    _scene = buildScene(
      c.doc,
      uml: c.uml,
      selected: c.selected,
      group: c.group,
      pending: c.pending,
      hover: _hover,
      pal: pal,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): c.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.escape): c.cancel,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            c.selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): c.selectAll,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Listener(
          onPointerDown: (_) => _focus.requestFocus(),
          // Navigation: drag with the right button, scroll vertically,
          // Shift+scroll horizontally, Ctrl+scroll to zoom on the cursor.
          onPointerMove: (e) {
            if (e.buttons & kSecondaryMouseButton != 0) {
              setState(() {
                _pan += e.delta;
                _panning = true;
              });
            }
          },
          onPointerUp: (_) {
            if (_panning) setState(() => _panning = false);
          },
          onPointerCancel: (_) {
            if (_panning) setState(() => _panning = false);
          },
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            final keys = HardwareKeyboard.instance;
            setState(() {
              if (keys.isControlPressed || keys.isMetaPressed) {
                final z = (_zoom * exp(-e.scrollDelta.dy / 400)).clamp(
                  0.2,
                  4.0,
                );
                _pan = e.localPosition - (e.localPosition - _pan) * (z / _zoom);
                _zoom = z;
              } else if (keys.isShiftPressed && e.scrollDelta.dx == 0) {
                // A plain wheel only reports dy; some platforms already swap it.
                _pan -= Offset(e.scrollDelta.dy, 0);
              } else {
                _pan -= e.scrollDelta;
              }
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition),
            // Right click breaks a link, or removes the break point under the cursor.
            onSecondaryTapUp: (d) {
              final p = _toScene(d.localPosition), key = _scene.hit(p);
              if (key != null &&
                  (key.startsWith('seg|') || key.startsWith('bend|'))) {
                c.toggleBend(key, p);
              }
            },
            onPanDown: (d) {
              _downAt = _toScene(d.localPosition);
              _down = _scene.hit(_downAt);
            },
            onPanStart: (_) => _dragStart(),
            onPanUpdate: (d) => _dragUpdate(d.delta, _toScene(d.localPosition)),
            onPanEnd: (_) {
              setState(() => _drag = _bandFrom = _bandTo = null);
              c.endCoalesce();
            },
            child: MouseRegion(
              // A drag in progress wins over what is under the pointer.
              cursor: _panning || _drag != null
                  ? SystemMouseCursors.grabbing
                  : _cursor,
              onHover: (e) {
                final cursor = _cursorAt(e.localPosition);
                final key = _scene.hit(_toScene(e.localPosition));
                final hover = c.doc.layout.containsKey(key) ? key : null;
                if (cursor != _cursor || hover != _hover) {
                  setState(() {
                    _cursor = cursor;
                    _hover = hover;
                  });
                }
              },
              onExit: (_) {
                if (_hover != null) setState(() => _hover = null);
              },
              child: ColoredBox(
                color: Color(pal.canvas),
                child: CustomPaint(
                  painter: _Painter(_scene, _pan, _zoom, pal, _band),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
