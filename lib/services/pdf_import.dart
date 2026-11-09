import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

import '../models.dart';
import '../storage.dart';

typedef PickedPdf = ({String name, Uint8List bytes});

/// Lets the user choose a PDF file. Returns null if cancelled.
Future<PickedPdf?> pickPdf() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.single;
  final bytes =
      f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
  if (bytes == null) return null;
  return (name: p.basenameWithoutExtension(f.name), bytes: bytes);
}

/// Creates a note whose pages show the PDF pages, so you can write on them.
Future<Note> noteFromPdf(Library lib, PickedPdf pdf, {String? subjectId}) async {
  final note = lib.newDraft(subjectId: subjectId, title: pdf.name);
  final dir = lib.noteDir(note.id);
  await dir.create(recursive: true);

  final doc = await PdfDocument.openData(pdf.bytes);
  try {
    for (var i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final ratio = page.height / page.width;
      final img = await page.render(
        width: 1600,
        height: 1600 * ratio,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      if (img == null) continue;
      final name = 'pdf_page_$i.png';
      await File(p.join(dir.path, name)).writeAsBytes(img.bytes);
      note.pages.add(NotePage(
        id: newId(),
        paper: PaperType.blank,
        background: name,
        width: kPageWidth,
        height: kPageWidth * ratio,
      ));
    }
  } finally {
    await doc.close();
  }

  if (note.pages.isEmpty) note.pages.add(NotePage(id: newId()));
  await lib.addNote(note);
  return note;
}
