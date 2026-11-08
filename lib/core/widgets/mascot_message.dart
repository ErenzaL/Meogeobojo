import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_palette.dart';

/// Empty / error / placeholder state built around an existing mascot pose.
class MascotMessage extends StatelessWidget {
  const MascotMessage({
    super.key,
    required this.asset,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.imageHeight = 120,
  });

  final String asset;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, height: imageHeight, fit: BoxFit.contain),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: AppText.title),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppText.caption(context).copyWith(fontSize: 13.5),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryLabel != null)
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.textSecondary,
                ),
                child: Text(secondaryLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
