import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../storage.dart';
import '../widgets/page_content.dart';
import '../widgets/painters.dart';

/// Renders one page (paper, PDF background, text, ink) to an image.
Future<ui.Image> renderPageImage(NotePage page, String dirPath,
    {double scale = 2}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(scale);
  final size = Size(page.width, page.height);
  PaperPainter.paintPaper(canvas, size, page.paper);

  if (page.background != null) {
    final f = File(p.join(dirPath, page.background!));
    if (await f.exists()) {
      final codec = await ui.instantiateImageCodec(await f.readAsBytes());
      final img = (await codec.getNextFrame()).image;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.high,
      );
      img.dispose();
    }
  }

  for (final t in page.texts) {
    final tp = layoutTextItem(t, page.width);
    tp.paint(canvas, Offset(t.x, t.y));
    tp.dispose();
  }
  for (final s in page.strokes) {
    InkPainter.paintStroke(canvas, s);
  }

  final picture = rec.endRecording();
  final image = await picture.toImage(
      (page.width * scale).round(), (page.height * scale).round());
  picture.dispose();
  return image;
}

Future<File> exportNotePdf(Library lib, Note note) async {
  final doc = pw.Document(title: note.title);
  final dirPath = lib.noteDir(note.id).path;
  for (final page in note.pages) {
    final img = await renderPageImage(page, dirPath);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    final mem = pw.MemoryImage(data!.buffer.asUint8List());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
      build: (ctx) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Image(mem, fit: pw.BoxFit.fill),
      ),
    ));
  }
  final tmp = await getTemporaryDirectory();
  final safe = note.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final file =
      File(p.join(tmp.path, '${safe.isEmpty ? 'note' : safe}.pdf'));
  await file.writeAsBytes(await doc.save());
  return file;
}

/// Where the iPad share popover points to (required on iPad).
Rect shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final s = MediaQuery.sizeOf(context);
  return Rect.fromCenter(center: s.center(Offset.zero), width: 1, height: 1);
}

Future<void> shareFile(File f, String subject, Rect origin) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path, mimeType: 'application/pdf')],
    subject: subject,
    sharePositionOrigin: origin,
  ));
}
