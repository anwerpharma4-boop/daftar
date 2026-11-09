import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import 'painters.dart';

final _rtlChars = RegExp(r'[֐-ࣿ]');

TextDirection textDirOf(String s) =>
    _rtlChars.hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

TextStyle textItemStyle(TextItem t) =>
    TextStyle(fontSize: t.size, color: Color(t.color), height: 1.3);

double textMaxWidth(TextItem t, double pageWidth) =>
    math.max(60.0, pageWidth - t.x);

/// Measures a text item the same way it is rendered.
TextPainter layoutTextItem(TextItem t, double pageWidth) => TextPainter(
      text: TextSpan(text: t.text, style: textItemStyle(t)),
      textDirection: textDirOf(t.text),
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: textMaxWidth(t, pageWidth));

Rect textItemRect(TextItem t, double pageWidth) {
  final tp = layoutTextItem(t, pageWidth);
  final r = Rect.fromLTWH(t.x, t.y, tp.width, tp.height).inflate(6);
  tp.dispose();
  return r;
}

/// One page drawn at its own size (page units). Scale it with FittedBox.
class NotePageContent extends StatelessWidget {
  const NotePageContent({
    super.key,
    required this.page,
    required this.dirPath,
    this.overlay,
    this.playingId,
    this.playMs,
    this.thumbnail = false,
  });

  final NotePage page;
  final String dirPath;
  final Widget? overlay;
  final String? playingId;
  final ValueListenable<int>? playMs;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: page.width,
      height: page.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: PaperPainter(page.paper)),
          ),
          if (page.background != null)
            Positioned.fill(
              child: Image.file(
                File(p.join(dirPath, page.background!)),
                fit: BoxFit.fill,
                gaplessPlayback: true,
                cacheWidth: thumbnail ? 360 : null,
                errorBuilder: (context, error, stack) => const SizedBox(),
              ),
            ),
          for (final t in page.texts)
            Positioned(
              left: t.x,
              top: t.y,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: textMaxWidth(t, page.width)),
                child: Text(
                  t.text,
                  style: textItemStyle(t),
                  textDirection: textDirOf(t.text),
                  textWidthBasis: TextWidthBasis.longestLine,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: InkPainter(
                  page.strokes,
                  playingId: playingId,
                  playMs: playMs,
                ),
              ),
            ),
          ),
          if (overlay != null) Positioned.fill(child: overlay!),
        ],
      ),
    );
  }
}
