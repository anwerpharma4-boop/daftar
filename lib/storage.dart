import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

final _uuid = Uuid();
String newId() => _uuid.v4();

const subjectColors = <int>[
  0xFF3B6FD8,
  0xFFE0533D,
  0xFF2E9E6A,
  0xFFF0A020,
  0xFF8E5BD6,
  0xFF1AA6B7,
  0xFFD6487E,
  0xFF6B7280,
];

/// Everything stored on the device. Layout:
///   <documents>/daftar/subjects.json
///   <documents>/daftar/notes/<noteId>/note.json   (+ PDF page images, audio)
class Library extends ChangeNotifier {
  late final Directory root;
  final List<Subject> subjects = [];
  final List<Note> notes = [];

  Future<void> _saving = Future.value();

  Directory get _notesDir => Directory(p.join(root.path, 'notes'));
  File get _subjectsFile => File(p.join(root.path, 'subjects.json'));
  Directory noteDir(String id) => Directory(p.join(_notesDir.path, id));

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    root = Directory(p.join(docs.path, 'daftar'));
    await _notesDir.create(recursive: true);

    if (await _subjectsFile.exists()) {
      try {
        final list = jsonDecode(await _subjectsFile.readAsString()) as List;
        subjects.addAll(
            list.map((e) => Subject.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('Could not read subjects: $e');
      }
    } else {
      subjects.add(Subject(id: newId(), name: 'عام', color: subjectColors[0]));
      await saveSubjects();
    }

    await for (final ent in _notesDir.list()) {
      if (ent is! Directory) continue;
      final f = File(p.join(ent.path, 'note.json'));
      if (!await f.exists()) continue;
      try {
        notes.add(Note.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Could not read ${f.path}: $e');
      }
    }
    notifyListeners();
  }

  static Future<void> _writeAtomic(File f, String data) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }

  Future<void> saveSubjects() => _writeAtomic(
      _subjectsFile, jsonEncode([for (final s in subjects) s.toJson()]));

  /// Saves are queued so two writes of the same file never overlap.
  Future<void> saveNote(Note n) {
    final next = _saving.catchError((Object _) {}).then((_) async {
      final dir = noteDir(n.id);
      await dir.create(recursive: true);
      await _writeAtomic(
          File(p.join(dir.path, 'note.json')), jsonEncode(n.toJson()));
    });
    _saving = next;
    return next;
  }

  void touch(Note n) {
    n.updated = DateTime.now();
    notifyListeners();
  }

  Note newDraft({String? subjectId, String? title}) {
    final now = DateTime.now();
    return Note(
      id: newId(),
      title: (title == null || title.trim().isEmpty)
          ? 'ملاحظة بدون عنوان'
          : title.trim(),
      subjectId: subjectId,
      created: now,
      updated: now,
    );
  }

  Future<void> addNote(Note n) async {
    notes.add(n);
    notifyListeners();
    await saveNote(n);
  }

  Future<Note> createNote({String? subjectId}) async {
    final n = newDraft(subjectId: subjectId)
      ..pages.add(NotePage(id: newId()));
    await addNote(n);
    return n;
  }

  Future<void> deleteNote(Note n) async {
    notes.remove(n);
    notifyListeners();
    final d = noteDir(n.id);
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<Note> duplicateNote(Note n) async {
    await saveNote(n);
    final json = n.toJson();
    json['id'] = newId();
    json['title'] = '${n.title} (نسخة)';
    final copy = Note.fromJson(json);
    copy.created = copy.updated = DateTime.now();
    final src = noteDir(n.id);
    final dst = noteDir(copy.id);
    await dst.create(recursive: true);
    await for (final f in src.list()) {
      final name = p.basename(f.path);
      if (f is File && name != 'note.json' && !name.endsWith('.tmp')) {
        await f.copy(p.join(dst.path, name));
      }
    }
    await addNote(copy);
    return copy;
  }

  Future<void> renameNote(Note n, String title) async {
    n.title = title;
    touch(n);
    await saveNote(n);
  }

  Future<void> moveNote(Note n, String? subjectId) async {
    n.subjectId = subjectId;
    touch(n);
    await saveNote(n);
  }

  Subject? subjectById(String? id) {
    if (id == null) return null;
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  int countIn(String? subjectId) => subjectId == null
      ? notes.length
      : notes.where((n) => n.subjectId == subjectId).length;

  Future<Subject> addSubject(String name) async {
    final s = Subject(
      id: newId(),
      name: name,
      color: subjectColors[subjects.length % subjectColors.length],
    );
    subjects.add(s);
    notifyListeners();
    await saveSubjects();
    return s;
  }

  Future<void> updateSubject(Subject s, {String? name, int? color}) async {
    if (name != null) s.name = name;
    if (color != null) s.color = color;
    notifyListeners();
    await saveSubjects();
  }

  /// Deletes the subject only; its notes stay, without a subject.
  Future<void> deleteSubject(Subject s) async {
    subjects.remove(s);
    for (final n in notes.where((n) => n.subjectId == s.id).toList()) {
      n.subjectId = null;
      await saveNote(n);
    }
    notifyListeners();
    await saveSubjects();
  }
}
