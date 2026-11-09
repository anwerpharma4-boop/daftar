import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';

/// Draws the paper: white background plus lines / grid / dots.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.type);
  final PaperType type;

  static void paintPaper(Canvas c, Size s, PaperType t) {
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xFFD3E2F2)
      ..strokeWidth = 1;
    const gap = 32.0;
    switch (t) {
      case PaperType.blank:
        break;
      case PaperType.lined:
        for (double y = 96; y < s.height - 8; y += gap) {
          c.drawLine(Offset(0, y), Offset(s.width, y), line);
        }
        // Margin line on the right side (Arabic writing starts on the right).
        c.drawLine(
          Offset(s.width - 72, 0),
          Offset(s.width - 72, s.height),
          Paint()
            ..color = const Color(0xFFF3B7B7)
            ..strokeWidth = 1.2,
        );
      case PaperType.grid:
        const g = 28.0;
        for (double y = g; y < s.height; y += g) {
          c.drawLine(Offset(0, y), Offset(s.width, y), line);
        }
        for (double x = g; x < s.width; x += g) {
          c.drawLine(Offset(x, 0), Offset(x, s.height), line);
        }
      case PaperType.dotted:
        const g = 28.0;
        final dot = Paint()..color = const Color(0xFFB9C6D6);
        for (double y = g; y < s.height; y += g) {
          for (double x = g; x < s.width; x += g) {
            c.drawCircle(Offset(x, y), 1.5, dot);
          }
        }
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintPaper(canvas, size, type);

  @override
  bool shouldRepaint(covariant PaperPainter old) => old.type != type;
}

/// Draws finished strokes. While a recording plays back, strokes written
/// later in that recording are drawn faded, so the note "replays".
class InkPainter extends CustomPainter {
  InkPainter(this.strokes, {this.playingId, this.playMs})
      : super(repaint: playMs);

  final List<Stroke> strokes;
  final String? playingId;
  final ValueListenable<int>? playMs;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = playMs?.value ?? 0;
    for (final s in strokes) {
      final faded =
          playingId != null && s.audioId == playingId && (s.audioMs ?? 0) > ms;
      paintStroke(canvas, s, faded: faded);
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter old) => true;

  static double _w(Stroke s, StrokePoint pt) =>
      s.highlighter ? s.width : s.width * (0.45 + pt.p * 1.1);

  static void paintStroke(Canvas canvas, Stroke s, {bool faded = false}) {
    final pts = s.points;
    if (pts.isEmpty) return;
    var color = Color(s.color);
    if (faded) color = Color.lerp(color, Colors.white, 0.8)!;
    if (s.highlighter) color = color.withValues(alpha: 0.38);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = s.highlighter ? StrokeCap.butt : StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (pts.length == 1) {
      canvas.drawCircle(
          pts[0].offset, _w(s, pts[0]) / 2, paint..style = PaintingStyle.fill);
      return;
    }

    if (s.highlighter) {
      // One path with constant width so overlapping parts don't darken.
      final path = Path()..moveTo(pts[0].x, pts[0].y);
      for (var i = 1; i < pts.length; i++) {
        final end = i < pts.length - 1
            ? (pts[i].offset + pts[i + 1].offset) / 2
            : pts[i].offset;
        path.quadraticBezierTo(pts[i].x, pts[i].y, end.dx, end.dy);
      }
      canvas.drawPath(path, paint..strokeWidth = s.width);
      return;
    }

    // Pen: smooth curve through midpoints, width follows pressure.
    var start = pts[0].offset;
    for (var i = 1; i < pts.length; i++) {
      final end = i < pts.length - 1
          ? (pts[i].offset + pts[i + 1].offset) / 2
          : pts[i].offset;
      final seg = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(pts[i].x, pts[i].y, end.dx, end.dy);
      canvas.drawPath(seg, paint..strokeWidth = _w(s, pts[i]));
      start = end;
    }
  }

  /// True if a circle at [q] with radius [r] touches the stroke.
  static bool hits(Stroke s, Offset q, double r) {
    final rr = r + s.width / 2;
    final pts = s.points;
    if (pts.length == 1) return (pts[0].offset - q).distance <= rr;
    for (var i = 1; i < pts.length; i++) {
      if (_segDist(pts[i - 1].offset, pts[i].offset, q) <= rr) return true;
    }
    return false;
  }

  static double _segDist(Offset a, Offset b, Offset q) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (q - a).distance;
    final t = (((q.dx - a.dx) * ab.dx + (q.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0)
        .toDouble();
    return (q - (a + ab * t)).distance;
  }
}

/// Draws the stroke currently being written and the eraser cursor.
class LiveInkPainter extends CustomPainter {
  LiveInkPainter({
    required this.stroke,
    required this.cursor,
    required this.cursorRadius,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Stroke? Function() stroke;
  final Offset? Function() cursor;
  final double Function() cursorRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final s = stroke();
    if (s != null) InkPainter.paintStroke(canvas, s);
    final c = cursor();
    if (c != null) {
      canvas.drawCircle(
        c,
        cursorRadius(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.black45,
      );
    }
  }

  @override
  bool shouldRepaint(covariant LiveInkPainter old) => true;
}
