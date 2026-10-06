import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'scene.dart';

void paintScene(Canvas canvas, Scene s) {
  for (final shape in s.shapes) {
    switch (shape) {
      case Box(:final rect, :final radius, :final fill, :final stroke, :final strokeWidth):
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        canvas
          ..drawRRect(rr, Paint()..color = Color(fill))
          ..drawRRect(
              rr,
              Paint()
                ..color = Color(stroke)
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth);
      case Line(:final a, :final b, :final color):
        canvas.drawLine(
            a,
            b,
            Paint()
              ..color = Color(color)
              ..strokeWidth = 1.2);
      case Poly(:final points, :final fill):
        canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = Color(fill));
      case Label(:final pos, :final text, :final align, :final color, :final bold, :final underline):
        final tp = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['DejaVu Sans Mono', 'Consolas', 'Menlo'],
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
  final image = await recorder.endRecording().toImage((b.width * scale).ceil(), (b.height * scale).ceil());
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
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
  final _focus = FocusNode();
  Offset _pan = Offset.zero, _raw = Offset.zero;
  double _zoom = 1;
  String? _down, _drag;
  late Scene _scene;

  Controller get c => widget.c;
  Offset _toScene(Offset p) => (p - _pan) / _zoom;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scene = buildScene(c.doc, uml: c.uml, selected: c.selected, pending: c.pending);
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
            onTapUp: (d) => c.tap(_scene.hit(_toScene(d.localPosition)), _toScene(d.localPosition)),
            onPanDown: (d) => _down = _scene.hit(_toScene(d.localPosition)),
            onPanStart: (_) {
              final pos = c.doc.layout[_down];
              if (c.tool != Tool.select || pos == null) return;
              _drag = _down;
              _raw = Offset(pos.$1.toDouble(), pos.$2.toDouble());
              c.select(_drag);
            },
            onPanUpdate: (d) => setState(() {
              if (_drag == null) {
                _pan += d.delta;
              } else {
                _raw += d.delta / _zoom;
                c.move(_drag!, _raw);
              }
            }),
            onPanEnd: (_) {
              _drag = null;
              c.endCoalesce();
            },
            child: ColoredBox(
              color: const Color(0xFFF5F5F2),
              child: CustomPaint(painter: _Painter(_scene, _pan, _zoom), size: Size.infinite),
            ),
          ),
        ),
      ),
    );
  }
}
