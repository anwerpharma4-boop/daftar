import 'package:flutter/material.dart';

String fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

String fmtDuration(int ms) {
  final s = (ms / 1000).floor();
  final m = s ~/ 60;
  return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

Future<String?> promptText(BuildContext context, String title,
    [String initial = '']) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('حفظ')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, [String? body]) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  return r ?? false;
}

typedef TextEditResult = ({String text, bool delete});

Future<TextEditResult?> showTextEditor(
  BuildContext context, {
  required String title,
  String initial = '',
  bool allowDelete = false,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<TextEditResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'اكتب هنا…',
        ),
      ),
      actions: [
        if (allowDelete)
          TextButton(
            onPressed: () => Navigator.pop(ctx, (text: '', delete: true)),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, (text: c.text, delete: false)),
          child: const Text('تم'),
        ),
      ],
    ),
  );
}
