import 'package:flutter/material.dart';

class PopupDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final double? width;
  final double? height;

  const PopupDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: width ?? 400,
        height: height,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[title!, const SizedBox(height: 16)],
            if (content != null) ...[
              Flexible(child: content!),
              const SizedBox(height: 24),
            ],
            if (actions != null) ...[
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions!),
            ],
          ],
        ),
      ),
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    Widget? title,
    Widget? content,
    List<Widget>? actions,
    double? width,
    double? height,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => PopupDialog(
        title: title,
        content: content,
        actions: actions,
        width: width,
        height: height,
      ),
    );
  }
}
