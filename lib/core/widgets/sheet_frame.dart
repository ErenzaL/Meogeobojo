import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Opens a draggable, scrollable bottom sheet. [builder] gets the scroll
/// controller to attach to its main scrollable.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
  double initialSize = 0.92,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: context.palette.card,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, controller) => Column(
        children: [
          const _Grabber(),
          Expanded(child: builder(ctx, controller)),
        ],
      ),
    ),
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: context.palette.hairline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
