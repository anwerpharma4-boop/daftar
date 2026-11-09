import 'package:flutter/material.dart';

import '../models.dart';
import '../services/export.dart';
import '../services/pdf_import.dart';
import '../storage.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_content.dart';
import 'editor_screen.dart';

enum _Sort { updated, created, title }

/// Home screen: subjects on the side, notes as a grid of page previews.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.lib});
  final Library lib;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Library get lib => widget.lib;
  String? _subjectId; // null = all notes
  String _query = '';
  _Sort _sort = _Sort.updated;

  List<Note> get _visible {
    final q = _query.trim().toLowerCase();
    final list = lib.notes
        .where((n) => _subjectId == null || n.subjectId == _subjectId)
        .where((n) => q.isEmpty || n.searchText.contains(q))
        .toList();
    switch (_sort) {
      case _Sort.updated:
        list.sort((a, b) => b.updated.compareTo(a.updated));
      case _Sort.created:
        list.sort((a, b) => b.created.compareTo(a.created));
      case _Sort.title:
        list.sort((a, b) => a.title.compareTo(b.title));
    }
    return list;
  }

  Future<void> _open(Note n) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(lib: lib, note: n),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _newNote() async {
    final n = await lib.createNote(subjectId: _subjectId);
    if (mounted) _open(n);
  }

  Future<void> _importPdf() async {
    final picked = await pickPdf();
    if (picked == null || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جارٍ استيراد الملف…'),
              ]),
            ),
          ),
        ),
      ),
    );
    Note? note;
    Object? error;
    try {
      note = await noteFromPdf(lib, picked, subjectId: _subjectId);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (note != null) {
      _open(note);
    } else {
      showToast(context, 'تعذّر استيراد الملف: $error');
    }
  }

  // ---------- subjects ----------

  Future<void> _addSubject() async {
    final name = await promptText(context, 'موضوع جديد');
    if (name == null || name.trim().isEmpty) return;
    final s = await lib.addSubject(name.trim());
    setState(() => _subjectId = s.id);
  }

  Future<void> _subjectAction(Subject s, String action) async {
    switch (action) {
      case 'rename':
        final name = await promptText(context, 'إعادة تسمية الموضوع', s.name);
        if (name != null && name.trim().isNotEmpty) {
          await lib.updateSubject(s, name: name.trim());
        }
      case 'color':
        final c = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('لون الموضوع'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final c in subjectColors)
                    InkWell(
                      onTap: () => Navigator.pop(ctx, c),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                          radius: 18, backgroundColor: Color(c)),
                    ),
                ]),
              ),
            ],
          ),
        );
        if (c != null) await lib.updateSubject(s, color: c);
      case 'delete':
        final ok = await confirm(context, 'حذف الموضوع "${s.name}"؟',
            'لن تُحذف الملاحظات، بل ستبقى في "كل الملاحظات".');
        if (ok) {
          if (_subjectId == s.id) setState(() => _subjectId = null);
          await lib.deleteSubject(s);
        }
    }
  }

  Widget _sidebar(BuildContext context, {required bool inDrawer}) {
    final theme = Theme.of(context);
    void select(String? id) {
      setState(() => _subjectId = id);
      if (inDrawer) Scaffold.of(context).closeDrawer();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(children: [
            Icon(Icons.menu_book_rounded,
                color: theme.colorScheme.primary, size: 30),
            const SizedBox(width: 10),
            Text('دفتر',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.notes_rounded),
          title: const Text('كل الملاحظات'),
          trailing: Text('${lib.notes.length}'),
          selected: _subjectId == null,
          onTap: () => select(null),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(children: [
            Text('المواضيع', style: theme.textTheme.labelLarge),
            const Spacer(),
            IconButton(
              tooltip: 'موضوع جديد',
              icon: const Icon(Icons.add),
              onPressed: _addSubject,
            ),
          ]),
        ),
        for (final s in lib.subjects)
          ListTile(
            leading: CircleAvatar(radius: 8, backgroundColor: Color(s.color)),
            title: Text(s.name, overflow: TextOverflow.ellipsis),
            selected: _subjectId == s.id,
            onTap: () => select(s.id),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${lib.countIn(s.id)}'),
              PopupMenuButton<String>(
                onSelected: (v) => _subjectAction(s, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                  PopupMenuItem(value: 'color', child: Text('تغيير اللون')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ]),
          ),
      ],
    );
  }

  // ---------- notes ----------

  Future<void> _noteMenu(Note n) async {
    final origin = shareOriginOf(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(n.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final (value, icon, label) in const [
            ('rename', Icons.edit_outlined, 'إعادة تسمية'),
            ('move', Icons.drive_file_move_outline, 'نقل إلى موضوع'),
            ('duplicate', Icons.copy_outlined, 'نسخة مكررة'),
            ('export', Icons.ios_share, 'تصدير PDF ومشاركة'),
            ('delete', Icons.delete_outline, 'حذف'),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, value),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        final t = await promptText(context, 'اسم الملاحظة', n.title);
        if (t != null && t.trim().isNotEmpty) {
          await lib.renameNote(n, t.trim());
        }
      case 'move':
        final target = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('نقل إلى'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('بدون موضوع'),
              ),
              for (final s in lib.subjects)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s.id),
                  child: Row(children: [
                    CircleAvatar(radius: 7, backgroundColor: Color(s.color)),
                    const SizedBox(width: 12),
                    Text(s.name),
                  ]),
                ),
            ],
          ),
        );
        if (target != null) {
          await lib.moveNote(n, target.isEmpty ? null : target);
        }
      case 'duplicate':
        await lib.duplicateNote(n);
      case 'export':
        showToast(context, 'جارٍ إنشاء ملف PDF…');
        try {
          final f = await exportNotePdf(lib, n);
          await shareFile(f, n.title, origin);
        } catch (e) {
          if (mounted) showToast(context, 'فشل التصدير: $e');
        }
      case 'delete':
        if (await confirm(context, 'حذف "${n.title}"؟',
            'سيتم حذف الملاحظة وتسجيلاتها نهائياً.')) {
          await lib.deleteNote(n);
        }
    }
  }

  Widget _noteCard(Note n) {
    final theme = Theme.of(context);
    final subj = lib.subjectById(n.subjectId);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(n),
      onLongPress: () => _noteMenu(n),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: n.pages.isEmpty
                    ? const SizedBox()
                    : FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        child: NotePageContent(
                          page: n.pages.first,
                          dirPath: lib.noteDir(n.id).path,
                          thumbnail: true,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(n.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            Row(children: [
              if (subj != null) ...[
                CircleAvatar(radius: 4, backgroundColor: Color(subj.color)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(fmtDate(n.updated),
                    style: theme.textTheme.bodySmall),
              ),
              if (n.recordings.isNotEmpty)
                Icon(Icons.mic, size: 14, color: theme.colorScheme.primary),
              InkResponse(
                onTap: () => _noteMenu(n),
                radius: 16,
                child: const Icon(Icons.more_horiz, size: 20),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_note_rounded,
              size: 72, color: theme.colorScheme.primary.withValues(alpha: .5)),
          const SizedBox(height: 12),
          Text(_query.isEmpty ? 'لا توجد ملاحظات بعد' : 'لا توجد نتائج',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          if (_query.isEmpty)
            const Text(
              'اضغط "ملاحظة جديدة" لتبدأ الكتابة، أو استورد ملف PDF لتكتب عليه.',
              textAlign: TextAlign.center,
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 720;
        final notes = _visible;
        final title =
            lib.subjectById(_subjectId)?.name ?? 'كل الملاحظات';
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              PopupMenuButton<_Sort>(
                tooltip: 'ترتيب',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: _Sort.updated, child: Text('آخر تعديل')),
                  PopupMenuItem(
                      value: _Sort.created, child: Text('تاريخ الإنشاء')),
                  PopupMenuItem(value: _Sort.title, child: Text('الاسم')),
                ],
              ),
              IconButton(
                tooltip: 'استيراد PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: _importPdf,
              ),
            ],
          ),
          drawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: Builder(
                        builder: (ctx) => _sidebar(ctx, inDrawer: true)),
                  ),
                ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                SizedBox(
                  width: 270,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: _sidebar(context, inDrawer: false),
                  ),
                ),
              Expanded(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'ابحث في العناوين والنصوص',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  Expanded(
                    child: notes.isEmpty
                        ? _empty()
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              childAspectRatio: 0.62,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemCount: notes.length,
                            itemBuilder: (_, i) => _noteCard(notes[i]),
                          ),
                  ),
                ]),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _newNote,
            icon: const Icon(Icons.add),
            label: const Text('ملاحظة جديدة'),
          ),
        );
      },
    );
  }
}
