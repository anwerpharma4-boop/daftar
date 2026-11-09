import 'dart:ui' show Offset;

/// Default page size (A4 ratio) in logical page units.
const double kPageWidth = 800;
const double kPageHeight = 1131;

enum PaperType { blank, lined, grid, dotted }

PaperType paperFromName(String? n) => PaperType.values
    .firstWhere((e) => e.name == n, orElse: () => PaperType.lined);

String paperLabel(PaperType t) => switch (t) {
      PaperType.blank => 'فارغ',
      PaperType.lined => 'مسطّر',
      PaperType.grid => 'مربعات',
      PaperType.dotted => 'نقاط',
    };

double _r(double v) => (v * 100).roundToDouble() / 100;

class StrokePoint {
  const StrokePoint(this.x, this.y, this.p);
  final double x;
  final double y;

  /// Pen pressure, 0..1 (0.5 when the device has no pressure).
  final double p;

  Offset get offset => Offset(x, y);

  List<double> toJson() => [_r(x), _r(y), _r(p)];

  factory StrokePoint.fromJson(List<dynamic> j) => StrokePoint(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        j.length > 2 ? (j[2] as num).toDouble() : 0.5,
      );
}

class Stroke {
  Stroke({
    required this.points,
    required this.color,
    required this.width,
    this.highlighter = false,
    this.audioId,
    this.audioMs,
  });

  final List<StrokePoint> points;
  final int color;
  final double width;
  final bool highlighter;

  /// Recording that was running when this stroke was drawn, and the offset
  /// into it. Used to replay the note in sync with the audio.
  final String? audioId;
  final int? audioMs;

  Map<String, dynamic> toJson() => {
        'pts': [for (final p in points) p.toJson()],
        'c': color,
        'w': width,
        if (highlighter) 'h': true,
        if (audioId != null) 'a': audioId,
        if (audioMs != null) 'am': audioMs,
      };

  factory Stroke.fromJson(Map<String, dynamic> j) => Stroke(
        points: [
          for (final p in j['pts'] as List) StrokePoint.fromJson(p as List)
        ],
        color: j['c'] as int,
        width: (j['w'] as num).toDouble(),
        highlighter: j['h'] == true,
        audioId: j['a'] as String?,
        audioMs: j['am'] as int?,
      );
}

class TextItem {
  const TextItem({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    this.color = 0xFF1F1F1F,
    this.size = 22,
  });

  final String id;
  final double x;
  final double y;
  final String text;
  final int color;
  final double size;

  TextItem copyWith({double? x, double? y, String? text, int? color}) =>
      TextItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        text: text ?? this.text,
        color: color ?? this.color,
        size: size,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': _r(x),
        'y': _r(y),
        't': text,
        'c': color,
        's': size,
      };

  factory TextItem.fromJson(Map<String, dynamic> j) => TextItem(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        text: j['t'] as String,
        color: j['c'] as int,
        size: (j['s'] as num).toDouble(),
      );
}

class NotePage {
  NotePage({
    required this.id,
    this.paper = PaperType.lined,
    this.background,
    this.width = kPageWidth,
    this.height = kPageHeight,
    List<Stroke>? strokes,
    List<TextItem>? texts,
  })  : strokes = strokes ?? [],
        texts = texts ?? [];

  final String id;
  PaperType paper;

  /// File name (inside the note folder) of an image drawn under the ink,
  /// e.g. a rendered PDF page.
  String? background;
  double width;
  double height;
  List<Stroke> strokes;
  List<TextItem> texts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'paper': paper.name,
        if (background != null) 'bg': background,
        'w': width,
        'h': height,
        'strokes': [for (final s in strokes) s.toJson()],
        'texts': [for (final t in texts) t.toJson()],
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as String,
        paper: paperFromName(j['paper'] as String?),
        background: j['bg'] as String?,
        width: (j['w'] as num?)?.toDouble() ?? kPageWidth,
        height: (j['h'] as num?)?.toDouble() ?? kPageHeight,
        strokes: [
          for (final s in (j['strokes'] as List? ?? []))
            Stroke.fromJson(s as Map<String, dynamic>)
        ],
        texts: [
          for (final t in (j['texts'] as List? ?? []))
            TextItem.fromJson(t as Map<String, dynamic>)
        ],
      );
}

class AudioClip {
  const AudioClip({
    required this.id,
    required this.file,
    required this.durationMs,
    required this.created,
  });

  final String id;
  final String file;
  final int durationMs;
  final DateTime created;

  Map<String, dynamic> toJson() => {
        'id': id,
        'file': file,
        'ms': durationMs,
        'created': created.toIso8601String(),
      };

  factory AudioClip.fromJson(Map<String, dynamic> j) => AudioClip(
        id: j['id'] as String,
        file: j['file'] as String,
        durationMs: j['ms'] as int,
        created: DateTime.parse(j['created'] as String),
      );
}

class Note {
  Note({
    required this.id,
    required this.title,
    this.subjectId,
    required this.created,
    required this.updated,
    List<NotePage>? pages,
    List<AudioClip>? recordings,
  })  : pages = pages ?? [],
        recordings = recordings ?? [];

  final String id;
  String title;
  String? subjectId;
  DateTime created;
  DateTime updated;
  List<NotePage> pages;
  List<AudioClip> recordings;

  /// Everything searchable in the note (title + typed text).
  String get searchText => [
        title,
        for (final pg in pages)
          for (final t in pg.texts) t.text,
      ].join('\n').toLowerCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subjectId,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'pages': [for (final p in pages) p.toJson()],
        'recordings': [for (final r in recordings) r.toJson()],
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        subjectId: j['subject'] as String?,
        created: DateTime.parse(j['created'] as String),
        updated: DateTime.parse(j['updated'] as String),
        pages: [
          for (final p in (j['pages'] as List? ?? []))
            NotePage.fromJson(p as Map<String, dynamic>)
        ],
        recordings: [
          for (final r in (j['recordings'] as List? ?? []))
            AudioClip.fromJson(r as Map<String, dynamic>)
        ],
      );
}

class Subject {
  Subject({required this.id, required this.name, required this.color});

  final String id;
  String name;
  int color;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as int,
      );
}
