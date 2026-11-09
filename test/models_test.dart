import 'package:daftar/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('note survives a JSON round trip', () {
    final now = DateTime(2026, 11, 9, 10, 30);
    final note = Note(
      id: 'n1',
      title: 'محاضرة الفيزياء',
      subjectId: 's1',
      created: now,
      updated: now,
      pages: [
        NotePage(
          id: 'p1',
          paper: PaperType.grid,
          strokes: [
            Stroke(
              points: const [StrokePoint(1, 2, 0.5), StrokePoint(3, 4, 0.9)],
              color: 0xFF2F5BD3,
              width: 3.5,
              audioId: 'a1',
              audioMs: 1200,
            ),
            Stroke(
              points: const [StrokePoint(5, 6, 0.5)],
              color: 0xFFFFE34D,
              width: 22,
              highlighter: true,
            ),
          ],
          texts: const [TextItem(id: 't1', x: 10, y: 20, text: 'مرحبا')],
        ),
      ],
      recordings: [
        AudioClip(id: 'a1', file: 'audio_a1.m4a', durationMs: 5000, created: now),
      ],
    );

    final back = Note.fromJson(note.toJson());

    expect(back.title, 'محاضرة الفيزياء');
    expect(back.pages.single.paper, PaperType.grid);
    expect(back.pages.single.strokes.length, 2);
    expect(back.pages.single.strokes.first.audioMs, 1200);
    expect(back.pages.single.strokes.last.highlighter, isTrue);
    expect(back.pages.single.texts.single.text, 'مرحبا');
    expect(back.recordings.single.durationMs, 5000);
    expect(back.searchText, contains('مرحبا'));
  });
}
