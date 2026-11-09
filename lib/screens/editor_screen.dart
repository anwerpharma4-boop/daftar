import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart' show AudioPlayer, DeviceFileSource;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart' show AudioEncoder, AudioRecorder, RecordConfig;

import '../models.dart';
import '../services/export.dart';
import '../storage.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_content.dart';
import '../widgets/painters.dart';
import '../widgets/palette.dart';

enum Tool { pen, highlighter, eraser, text, hand }

class _Snap {
  _Snap(this.page, this.strokes, this.texts);
  final int page;
  final List<Stroke> strokes;
  final List<TextItem> texts;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.lib, required this.note});
  final Library lib;
  final Note note;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Note get note => widget.note;
  Library get lib => widget.lib;
  String get dirPath => lib.noteDir(note.id).path;

  final _scroll = ScrollController();
  final _moreKey = GlobalKey();
  static const _gap = 24.0;
  static const _topPad = 16.0;
  double _maxW = kPageWidth;

  // Tool settings
  Tool _tool = Tool.pen;
  int _penColor = penColors.first;
  double _penWidth = penWidths[1];
  int _hlColor = highlightColors.first;
  double _hlWidth = highlightWidths[1];
  double _eraserR = eraserSizes[1];

  /// When on, a finger writes; when off, a finger scrolls and only the
  /// stylus writes (palm rejection). Turns off by itself when a stylus is used.
  bool _fingerDraw = true;
  bool _stylusSeen = false;

  // Current gesture
  int? _pointer;
  int _gPage = -1;
  Tool? _gTool;
  Offset _downPos = Offset.zero;
  final List<StrokePoint> _pts = [];
  String? _strokeAudioId;
  int? _strokeAudioMs;
  final _tick = ValueNotifier<int>(0);
  bool _erased = false;
  Offset? _cursor;
  String? _dragText;
  Offset _dragOrig = Offset.zero;
  bool _dragMoved = false;

  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  Timer? _saveTimer;

  // Audio
  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  bool _recording = false;
  DateTime? _recStart;
  String? _recId;
  Timer? _recTicker;
  String? _playingId;
  bool _paused = false;
  final _playMs = ValueNotifier<int>(0);
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _doneSub;

  @override
  void initState() {
    super.initState();
    _posSub = _player.onPositionChanged
        .listen((d) => _playMs.value = d.inMilliseconds);
    _doneSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingId = null;
          _paused = false;
        });
      }
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _posSub?.cancel();
    _doneSub?.cancel();
    _player.dispose();
    if (_recording) {
      _finishRecording().whenComplete(_rec.dispose);
    } else {
      _rec.dispose();
    }
    _recTicker?.cancel();
    _saveNow();
    _scroll.dispose();
    _tick.dispose();
    _playMs.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- saving

  void _changed() {
    if (mounted) setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await lib.saveNote(note);
    lib.touch(note);
  }

  void _toast(String msg) {
    if (mounted) showToast(context, msg);
  }

  // ------------------------------------------------------------ undo/redo

  void _pushUndo(int i) {
    final pg = note.pages[i];
    _undo.add(_Snap(i, List.of(pg.strokes), List.of(pg.texts)));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(List<_Snap> from, List<_Snap> to) {
    if (from.isEmpty || _pointer != null) return;
    final s = from.removeLast();
    final pg = note.pages[s.page];
    to.add(_Snap(s.page, List.of(pg.strokes), List.of(pg.texts)));
    pg.strokes = s.strokes;
    pg.texts = s.texts;
    _changed();
  }

  // ------------------------------------------------------------- drawing

  bool _isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  StrokePoint _pt(PointerEvent e) {
    var pr = 0.5;
    if (_isStylus(e) && e.pressureMax > e.pressureMin) {
      pr = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin))
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return StrokePoint(e.localPosition.dx, e.localPosition.dy, pr);
  }

  Stroke? _liveStroke(int i) {
    if (_gPage != i || _pts.isEmpty) return null;
    if (_gTool != Tool.pen && _gTool != Tool.highlighter) return null;
    final hl = _gTool == Tool.highlighter;
    return Stroke(
      points: _pts,
      color: hl ? _hlColor : _penColor,
      width: hl ? _hlWidth : _penWidth,
      highlighter: hl,
    );
  }

  void _onDown(int i, PointerDownEvent e) {
    if (_pointer != null) return;
    final stylus = _isStylus(e);
    if (stylus && !_stylusSeen) {
      _stylusSeen = true;
      if (_fingerDraw) {
        setState(() => _fingerDraw = false);
        _toast('تم اكتشاف قلم: اكتب بالقلم ومرّر الصفحات بإصبعك');
      }
    }
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) {
      return;
    }
    final tool =
        e.kind == PointerDeviceKind.invertedStylus ? Tool.eraser : _tool;
    if (tool == Tool.hand) return;
    if (e.kind == PointerDeviceKind.touch && !_fingerDraw && tool != Tool.text) {
      return;
    }

    _pointer = e.pointer;
    _gPage = i;
    _gTool = tool;
    _downPos = e.localPosition;
    switch (tool) {
      case Tool.pen:
      case Tool.highlighter:
        _pushUndo(i);
        _pts
          ..clear()
          ..add(_pt(e));
        if (_recording && _recStart != null) {
          _strokeAudioId = _recId;
          _strokeAudioMs = DateTime.now().difference(_recStart!).inMilliseconds;
        } else {
          _strokeAudioId = null;
          _strokeAudioMs = null;
        }
        _tick.value++;
      case Tool.eraser:
        _pushUndo(i);
        _erased = false;
        _cursor = e.localPosition;
        _eraseAt(i, e.localPosition);
        _tick.value++;
      case Tool.text:
        _textDown(i, e.localPosition);
      case Tool.hand:
        break;
    }
  }

  void _onMove(int i, PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final pos = e.localPosition;
    switch (_gTool) {
      case Tool.pen:
      case Tool.highlighter:
        if (_pts.isNotEmpty && (_pts.last.offset - pos).distance < 0.8) return;
        _pts.add(_pt(e));
        _tick.value++;
      case Tool.eraser:
        _cursor = pos;
        _eraseAt(i, pos);
        _tick.value++;
      case Tool.text:
        _textMove(i, pos);
      default:
        break;
    }
  }

  void _onUp(int i, PointerEvent e, {bool cancelled = false}) {
    if (e.pointer != _pointer) return;
    final tool = _gTool;
    final page = _gPage;
    _pointer = null;
    _gTool = null;
    _gPage = -1;
    _cursor = null;
    switch (tool) {
      case Tool.pen:
      case Tool.highlighter:
        if (cancelled || _pts.isEmpty) {
          _pts.clear();
          if (_undo.isNotEmpty) _undo.removeLast();
        } else {
          final hl = tool == Tool.highlighter;
          note.pages[page].strokes.add(Stroke(
            points: List.of(_pts),
            color: hl ? _hlColor : _penColor,
            width: hl ? _hlWidth : _penWidth,
            highlighter: hl,
            audioId: _strokeAudioId,
            audioMs: _strokeAudioMs,
          ));
          _pts.clear();
          _changed();
        }
      case Tool.eraser:
        if (_erased) {
          _changed();
        } else if (_undo.isNotEmpty) {
          _undo.removeLast();
        }
      case Tool.text:
        if (cancelled) {
          if (_dragText != null && _dragMoved) _changed();
          _dragText = null;
          setState(() {});
        } else {
          _textUp(page, e.localPosition);
        }
      default:
        break;
    }
    _tick.value++;
  }

  void _eraseAt(int i, Offset pos) {
    final pg = note.pages[i];
    final before = pg.strokes.length;
    pg.strokes.removeWhere((s) => InkPainter.hits(s, pos, _eraserR));
    if (pg.strokes.length != before) {
      _erased = true;
      setState(() {});
    }
  }

  // ---------------------------------------------------------------- text

  TextItem? _textAt(NotePage pg, Offset pos) {
    for (final t in pg.texts.reversed) {
      if (textItemRect(t, pg.width).contains(pos)) return t;
    }
    return null;
  }

  void _textDown(int i, Offset pos) {
    final t = _textAt(note.pages[i], pos);
    _dragMoved = false;
    if (t != null) {
      _pushUndo(i);
      _dragOrig = Offset(t.x, t.y);
      setState(() => _dragText = t.id); // locks scrolling while dragging
    }
  }

  void _textMove(int i, Offset pos) {
    if (_dragText == null) return;
    final d = pos - _downPos;
    if (!_dragMoved && d.distance < 6) return;
    _dragMoved = true;
    final pg = note.pages[i];
    final idx = pg.texts.indexWhere((t) => t.id == _dragText);
    if (idx < 0) return;
    setState(() => pg.texts[idx] = pg.texts[idx]
        .copyWith(x: _dragOrig.dx + d.dx, y: _dragOrig.dy + d.dy));
  }

  Future<void> _textUp(int i, Offset pos) async {
    final pg = note.pages[i];
    if (_dragText != null) {
      final id = _dragText!;
      setState(() => _dragText = null);
      if (_dragMoved) {
        _changed();
        return;
      }
      if (_undo.isNotEmpty) _undo.removeLast();
      final idx = pg.texts.indexWhere((t) => t.id == id);
      if (idx >= 0) await _editText(i, pg.texts[idx]);
      return;
    }
    if ((pos - _downPos).distance > 8) return;
    final r = await showTextEditor(context, title: 'إضافة نص');
    final text = r?.text.trim() ?? '';
    if (text.isEmpty) return;
    var item = TextItem(
        id: newId(), x: pos.dx, y: pos.dy - 14, text: text, color: _penColor);
    if (textDirOf(text) == TextDirection.rtl) {
      // Arabic text grows to the left of where you tapped.
      final w = textItemRect(item, pg.width).width - 12;
      item = item.copyWith(x: math.max(0.0, pos.dx - w));
    }
    _pushUndo(i);
    pg.texts.add(item);
    _changed();
  }

  Future<void> _editText(int i, TextItem t) async {
    final r = await showTextEditor(context,
        title: 'تعديل النص', initial: t.text, allowDelete: true);
    if (r == null) return;
    final pg = note.pages[i];
    final idx = pg.texts.indexWhere((x) => x.id == t.id);
    if (idx < 0) return;
    _pushUndo(i);
    if (r.delete || r.text.trim().isEmpty) {
      pg.texts.removeAt(idx);
    } else {
      pg.texts[idx] = t.copyWith(text: r.text.trim(), color: t.color);
    }
    _changed();
  }

  // --------------------------------------------------------------- pages

  double _pageTop(int k) {
    var y = _topPad;
    for (var j = 0; j < k; j++) {
      final pg = note.pages[j];
      y += pg.height * (_maxW / pg.width) + _gap;
    }
    return y;
  }

  int _currentPage() {
    if (!_scroll.hasClients) return 0;
    final mid = _scroll.offset + _scroll.position.viewportDimension / 3;
    for (var i = note.pages.length - 1; i >= 0; i--) {
      if (mid >= _pageTop(i)) return i;
    }
    return 0;
  }

  void _goToPage(int k) {
    if (!_scroll.hasClients) return;
    k = k.clamp(0, note.pages.length - 1);
    _scroll.animateTo(
      math.min(_pageTop(k) - 8, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _addPage() {
    final last = note.pages.isNotEmpty ? note.pages.last : null;
    setState(() {
      note.pages.add(NotePage(
        id: newId(),
        paper: (last != null && last.background == null)
            ? last.paper
            : PaperType.lined,
      ));
      _undo.clear();
      _redo.clear();
    });
    _scheduleSave();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _goToPage(note.pages.length - 1));
  }

  Future<void> _deletePage() async {
    if (note.pages.length <= 1) {
      _toast('لا يمكن حذف الصفحة الوحيدة');
      return;
    }
    final i = _currentPage();
    if (!await confirm(context, 'حذف الصفحة ${i + 1}؟',
        'لا يمكن التراجع عن هذا الإجراء.')) {
      return;
    }
    final pg = note.pages[i];
    setState(() {
      note.pages.removeAt(i);
      _undo.clear();
      _redo.clear();
    });
    if (pg.background != null) {
      try {
        await File(p.join(dirPath, pg.background!)).delete();
      } catch (_) {}
    }
    _scheduleSave();
  }

  Future<void> _pickPaper() async {
    final t = await showDialog<PaperType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('نوع الورق'),
        children: [
          for (final t in PaperType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(paperLabel(t)),
            ),
        ],
      ),
    );
    if (t == null) return;
    setState(() {
      for (final pg in note.pages) {
        if (pg.background == null) pg.paper = t;
      }
    });
    _scheduleSave();
  }

  Future<void> _rename() async {
    final t = await promptText(context, 'اسم الملاحظة', note.title);
    if (t == null || t.trim().isEmpty) return;
    setState(() => note.title = t.trim());
    _saveNow();
  }

  Future<void> _export() async {
    final origin = shareOriginOf(_moreKey.currentContext ?? context);
    _toast('جارٍ إنشاء ملف PDF…');
    try {
      await _saveNow();
      final f = await exportNotePdf(lib, note);
      await shareFile(f, note.title, origin);
    } catch (e) {
      _toast('فشل التصدير: $e');
    }
  }

  void _menu(String v) {
    switch (v) {
      case 'paper':
        _pickPaper();
      case 'finger':
        setState(() => _fingerDraw = !_fingerDraw);
      case 'add':
        _addPage();
      case 'delete':
        _deletePage();
      case 'export':
        _export();
    }
  }

  // --------------------------------------------------------------- audio

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _finishRecording();
      return;
    }
    try {
      if (!await _rec.hasPermission()) {
        _toast('يجب السماح باستخدام الميكروفون من إعدادات الجهاز');
        return;
      }
      await Directory(dirPath).create(recursive: true);
      final id = newId();
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: p.join(dirPath, 'audio_$id.m4a'),
      );
      setState(() {
        _recording = true;
        _recId = id;
        _recStart = DateTime.now();
      });
      _recTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      _toast('تعذّر بدء التسجيل: $e');
    }
  }

  Future<void> _finishRecording() async {
    final id = _recId;
    final start = _recStart;
    final end = DateTime.now();
    _recTicker?.cancel();
    _recording = false;
    _recId = null;
    _recStart = null;
    if (mounted && !_disposed) setState(() {});
    final path = await _rec.stop();
    if (id == null || start == null || path == null) return;
    note.recordings.add(AudioClip(
      id: id,
      file: p.basename(path),
      durationMs: end.difference(start).inMilliseconds,
      created: start,
    ));
    await _saveNow();
    if (mounted) setState(() {});
  }

  Future<void> _play(AudioClip c) async {
    await _player.stop();
    _playMs.value = 0;
    setState(() {
      _playingId = c.id;
      _paused = false;
    });
    await _player.play(DeviceFileSource(p.join(dirPath, c.file)));
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _player.resume();
    } else {
      await _player.pause();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _stopPlay() async {
    await _player.stop();
    setState(() {
      _playingId = null;
      _paused = false;
    });
  }

  Future<void> _deleteClip(AudioClip c) async {
    if (_playingId == c.id) await _stopPlay();
    note.recordings.remove(c);
    try {
      await File(p.join(dirPath, c.file)).delete();
    } catch (_) {}
    await _saveNow();
    if (mounted) setState(() {});
  }

  void _showRecordings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (note.recordings.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(32, 8, 32, 40),
              child: Text(
                'لا توجد تسجيلات بعد.\nاضغط زر الميكروفون لتسجيل المحاضرة أثناء الكتابة، '
                'ثم شغّل التسجيل لترى كتابتك تظهر بالتزامن مع الصوت.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (i, c) in note.recordings.indexed)
                  ListTile(
                    leading: Icon(_playingId == c.id
                        ? Icons.graphic_eq
                        : Icons.play_circle_outline),
                    title: Text('تسجيل ${i + 1}'),
                    subtitle: Text(
                        '${fmtDuration(c.durationMs)} • ${fmtDate(c.created)}'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _play(c);
                    },
                    trailing: IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(ctx, 'حذف هذا التسجيل؟')) {
                          await _deleteClip(c);
                          if (ctx.mounted) setSheet(() {});
                        }
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _playerBar() {
    final clip =
        note.recordings.where((c) => c.id == _playingId).firstOrNull;
    if (clip == null) return const SizedBox.shrink();
    final total = math.max(1, clip.durationMs).toDouble();
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(children: [
            IconButton(
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              onPressed: _togglePause,
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _playMs,
                builder: (context, ms, child) => Row(children: [
                  Text(fmtDuration(ms)),
                  Expanded(
                    child: Slider(
                      value: ms.clamp(0, total).toDouble(),
                      max: total,
                      onChanged: (v) {
                        _playMs.value = v.round();
                        _player.seek(Duration(milliseconds: v.round()));
                      },
                    ),
                  ),
                  Text(fmtDuration(clip.durationMs)),
                ]),
              ),
            ),
            IconButton(
              tooltip: 'إيقاف',
              icon: const Icon(Icons.close),
              onPressed: _stopPlay,
            ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- toolbar

  List<Widget> _colorRow(
          List<int> colors, int current, void Function(int) onPick) =>
      [
        for (final c in colors)
          ColorDot(
            color: c,
            selected: c == current,
            onTap: () => setState(() => onPick(c)),
          ),
        if (!colors.contains(current))
          ColorDot(color: current, selected: true, onTap: () {}),
        Center(
          child: IconButton(
            tooltip: 'ألوان أخرى',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () async {
              final c = await pickColor(context, current);
              if (c != null) setState(() => onPick(c));
            },
          ),
        ),
      ];

  List<Widget> _widthRow(List<double> widths, double current,
      void Function(double) onPick, Color color) {
    final maxW = widths.reduce(math.max);
    return [
      const Center(child: SizedBox(height: 28, child: VerticalDivider(width: 16))),
      for (final w in widths)
        Center(
          child: InkResponse(
            onTap: () => setState(() => onPick(w)),
            radius: 20,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: w == current
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              child: Container(
                width: (w / maxW * 20).clamp(5.0, 20.0).toDouble(),
                height: (w / maxW * 20).clamp(5.0, 20.0).toDouble(),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _toolbar() {
    final cs = Theme.of(context).colorScheme;
    Widget tool(Tool t, IconData icon, String tip) {
      final sel = _tool == t;
      return Center(
        child: IconButton(
          tooltip: tip,
          onPressed: () => setState(() => _tool = t),
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: sel ? cs.primaryContainer : null,
            foregroundColor: sel ? cs.onPrimaryContainer : null,
          ),
        ),
      );
    }

    final children = <Widget>[
      tool(Tool.pen, Icons.edit_outlined, 'قلم'),
      tool(Tool.highlighter, Icons.border_color_outlined, 'قلم تظليل'),
      tool(Tool.eraser, Icons.cleaning_services_outlined, 'ممحاة'),
      tool(Tool.text, Icons.text_fields, 'نص'),
      tool(Tool.hand, Icons.pan_tool_outlined, 'تمرير'),
      const Center(child: SizedBox(height: 28, child: VerticalDivider(width: 20))),
    ];
    switch (_tool) {
      case Tool.pen:
        children
          ..addAll(_colorRow(penColors, _penColor, (c) => _penColor = c))
          ..addAll(_widthRow(
              penWidths, _penWidth, (w) => _penWidth = w, Color(_penColor)));
      case Tool.text:
        children.addAll(_colorRow(penColors, _penColor, (c) => _penColor = c));
      case Tool.highlighter:
        children
          ..addAll(_colorRow(highlightColors, _hlColor, (c) => _hlColor = c))
          ..addAll(_widthRow(highlightWidths, _hlWidth, (w) => _hlWidth = w,
              Color(_hlColor)));
      case Tool.eraser:
        children.addAll(_widthRow(
            eraserSizes, _eraserR, (w) => _eraserR = w, Colors.grey));
      case Tool.hand:
        children.add(Center(
          child: Text('اسحب لتصفّح الصفحات',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ));
    }
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: children,
      ),
    );
  }

  // ---------------------------------------------------------------- build

  Widget _pageWidget(int i) {
    final page = note.pages[i];
    final h = page.height * (_maxW / page.width);
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Center(
        child: Container(
          width: _maxW,
          height: h,
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.fill,
            child: NotePageContent(
              page: page,
              dirPath: dirPath,
              playingId: _playingId,
              playMs: _playMs,
              overlay: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _onDown(i, e),
                onPointerMove: (e) => _onMove(i, e),
                onPointerUp: (e) => _onUp(i, e),
                onPointerCancel: (e) => _onUp(i, e, cancelled: true),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: LiveInkPainter(
                    stroke: () => _liveStroke(i),
                    cursor: () => _gPage == i ? _cursor : null,
                    cursorRadius: () => _eraserR,
                    repaint: _tick,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawTool = _tool == Tool.pen ||
        _tool == Tool.highlighter ||
        _tool == Tool.eraser;
    final locked = (_fingerDraw && drawTool) || _dragText != null;
    final recMs = _recStart == null
        ? 0
        : DateTime.now().difference(_recStart!).inMilliseconds;

    return Scaffold(
      backgroundColor: const Color(0xFFE6E9EF),
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _rename,
          child: Text(note.title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            tooltip: 'تراجع',
            icon: const Icon(Icons.undo),
            onPressed: _undo.isEmpty ? null : () => _restore(_undo, _redo),
          ),
          IconButton(
            tooltip: 'إعادة',
            icon: const Icon(Icons.redo),
            onPressed: _redo.isEmpty ? null : () => _restore(_redo, _undo),
          ),
          IconButton(
            tooltip: _recording ? 'إيقاف التسجيل' : 'تسجيل صوتي',
            icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none,
                color: _recording ? Colors.red : null),
            onPressed: _toggleRecord,
          ),
          IconButton(
            tooltip: 'التسجيلات',
            icon: Badge(
              isLabelVisible: note.recordings.isNotEmpty,
              label: Text('${note.recordings.length}'),
              child: const Icon(Icons.headphones_outlined),
            ),
            onPressed: _showRecordings,
          ),
          PopupMenuButton<String>(
            key: _moreKey,
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'paper', child: Text('نوع الورق')),
              CheckedPopupMenuItem(
                value: 'finger',
                checked: _fingerDraw,
                child: const Text('الكتابة بالإصبع'),
              ),
              const PopupMenuItem(value: 'add', child: Text('إضافة صفحة')),
              const PopupMenuItem(
                  value: 'delete', child: Text('حذف الصفحة الحالية')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'export', child: Text('تصدير PDF ومشاركة')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _toolbar(),
        ),
      ),
      body: Column(children: [
        if (_recording)
          Container(
            color: Colors.red.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
              const SizedBox(width: 8),
              Text('جارٍ التسجيل  ${fmtDuration(recMs)}'),
              const Spacer(),
              TextButton(onPressed: _toggleRecord, child: const Text('إيقاف')),
            ]),
          ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            _maxW = math.max(200.0, math.min(c.maxWidth - 24, 1000.0));
            return Stack(children: [
              ScrollConfiguration(
                // A stylus never scrolls: it always writes.
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.builder(
                  controller: _scroll,
                  physics:
                      locked ? const NeverScrollableScrollPhysics() : null,
                  padding: const EdgeInsets.only(top: _topPad, bottom: 24),
                  itemCount: note.pages.length + 1,
                  itemBuilder: (_, i) => i == note.pages.length
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 48),
                            child: OutlinedButton.icon(
                              onPressed: _addPage,
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة صفحة'),
                            ),
                          ),
                        )
                      : _pageWidget(i),
                ),
              ),
              PositionedDirectional(
                end: 12,
                bottom: 12,
                child: Column(children: [
                  IconButton.filledTonal(
                    tooltip: 'الصفحة السابقة',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: () => _goToPage(_currentPage() - 1),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'الصفحة التالية',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => _goToPage(_currentPage() + 1),
                  ),
                ]),
              ),
            ]);
          }),
        ),
        if (_playingId != null) _playerBar(),
      ]),
    );
  }
}
