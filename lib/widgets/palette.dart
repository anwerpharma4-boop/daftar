import 'package:flutter/material.dart';

const penColors = <int>[
  0xFF1F1F1F,
  0xFF2F5BD3,
  0xFFD93A2B,
  0xFF1E9E5A,
  0xFFF08A00,
  0xFF8A3FD1,
];

const highlightColors = <int>[
  0xFFFFE34D,
  0xFF7CF29A,
  0xFFFF8FC8,
  0xFF7FD3FF,
  0xFFFFB566,
];

const allColors = <int>[
  0xFF000000, 0xFF4A4A4A, 0xFF8E8E8E, 0xFFFFFFFF,
  0xFF1F3A93, 0xFF2F5BD3, 0xFF4FA3F7, 0xFF7FD3FF,
  0xFF0B7A4B, 0xFF1E9E5A, 0xFF7CF29A, 0xFFB6E36B,
  0xFF8B1A10, 0xFFD93A2B, 0xFFFF6B5A, 0xFFFF8FC8,
  0xFF8A3FD1, 0xFFB98AF0, 0xFFF08A00, 0xFFFFB566,
  0xFF8C5A2B, 0xFFC8A06A, 0xFFFFE34D, 0xFFFFF3A8,
];

const penWidths = <double>[2, 3.5, 6];
const highlightWidths = <double>[14, 22, 34];
const eraserSizes = <double>[8, 16, 32];

class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 28,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? cs.primary : Colors.black12,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<int?> pickColor(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('اختر لوناً'),
      content: SizedBox(
        width: 280,
        child: Wrap(
          spacing: 6,
          runSpacing: 10,
          children: [
            for (final c in allColors)
              ColorDot(
                color: c,
                selected: c == current,
                size: 36,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    ),
  );
}
