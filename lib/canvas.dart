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
      case Line(:final a, :final b, :final color):
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = Color(color)
            ..strokeWidth = 1.2,
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
              fontFamily: 'monospace',
              fontFamilyFallback: const [
                'DejaVu Sans Mono',
                'Consolas',
                'Menlo',
              ],
              fontSize: fontSize,
              color: Color(color),
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
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
    ..drawRect(b, Paint()..color = Colors.white);
  paintScene(canvas, s);
  final image = await recorder.endRecording().toImage(
    (b.width * scale).ceil(),
    (b.height * scale).ceil(),
  );
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

class _Painter extends CustomPainter {
  final Scene scene;
  final Offset pan;
  final double zoom;
  _Painter(this.scene, this.pan, this.zoom);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..translate(pan.dx, pan.dy)
      ..scale(zoom);
    paintScene(canvas, scene);
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
  String? _down, _drag, _lastTap;
  DateTime _lastTapAt = DateTime(0);
  Timer? _legTimer;
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
    if (c.tool != Tool.select || key == null) return;
    if (key.startsWith('bend|')) {
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

  void _dragUpdate(Offset delta) => setState(() {
    final key = _drag;
    if (key == null) {
      _pan += delta;
      return;
    }
    _raw += delta / _zoom;
    if (key.startsWith('bend|')) {
      c.moveBend(key, _raw);
    } else if (key.startsWith('resize|')) {
      c.resizeNote(key.substring(7), _raw);
    } else {
      c.move(key, _raw);
    }
  });

  @override
  Widget build(BuildContext context) {
    _scene = buildScene(
      c.doc,
      uml: c.uml,
      selected: c.selected,
      pending: c.pending,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): c.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.escape): c.cancel,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Listener(
          onPointerDown: (_) => _focus.requestFocus(),
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            setState(() {
              final z = (_zoom * exp(-e.scrollDelta.dy / 400)).clamp(0.2, 4.0);
              _pan = e.localPosition - (e.localPosition - _pan) * (z / _zoom);
              _zoom = z;
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
            onPanDown: (d) => _down = _scene.hit(_toScene(d.localPosition)),
            onPanStart: (_) => _dragStart(),
            onPanUpdate: (d) => _dragUpdate(d.delta),
            onPanEnd: (_) {
              _drag = null;
              c.endCoalesce();
            },
            child: ColoredBox(
              color: const Color(0xFFF5F5F2),
              child: CustomPaint(
                painter: _Painter(_scene, _pan, _zoom),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
