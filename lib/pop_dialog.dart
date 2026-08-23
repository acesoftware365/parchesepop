import 'package:flutter/material.dart';

/// The shared modal surface for Parchís Pop. It keeps confirmations, room
/// prompts and setup screens visually connected to the Pop home screen.
class PopDialogSurface extends StatelessWidget {
  const PopDialogSurface({
    super.key,
    required this.child,
    this.borderRadius = 30,
  });

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF102D61), Color(0xFF17284D), Color(0xFF382A78)],
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: const Color(0xFF8C78FF), width: 1.6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x73020B27),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _PopGridPainter())),
        ),
        child,
      ],
    ),
  );
}

class _PopGridPainter extends CustomPainter {
  const _PopGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    const step = 34.0;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PopGridPainter oldDelegate) => false;
}

class PopDialog extends StatelessWidget {
  const PopDialog({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.maxHeight,
    this.insetPadding = const EdgeInsets.all(16),
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final double? maxHeight;
  final EdgeInsets insetPadding;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final constraints = maxHeight == null
        ? BoxConstraints(maxWidth: maxWidth)
        : BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight!);
    return Dialog(
      insetPadding: insetPadding,
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: constraints,
        child: PopDialogSurface(
          borderRadius: 30,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Drop-in replacement for AlertDialog that preserves the familiar title,
/// content and actions API while applying the Pop surface and typography.
class PopAlertDialog extends StatelessWidget {
  const PopAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => PopDialog(
    maxWidth: 520,
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
    child: Theme(
      data: Theme.of(context).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: Colors.white),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null || title != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7257E9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: IconTheme(
                        data: const IconThemeData(
                          color: Colors.white,
                          size: 28,
                        ),
                        child: icon!,
                      ),
                    ),
                  if (icon != null && title != null) const SizedBox(width: 12),
                  if (title != null)
                    Expanded(
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Arial',
                        ),
                        child: title!,
                      ),
                    ),
                ],
              ),
            if (icon != null || title != null) const SizedBox(height: 14),
            if (content != null)
              DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFFEAF0FF),
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Arial',
                ),
                child: content!,
              ),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
