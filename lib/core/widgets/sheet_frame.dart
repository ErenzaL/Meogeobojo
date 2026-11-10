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

/// Opens a bottom sheet that is only as tall as its content (capped at 80% of
/// the screen, then [builder]'s own scrollable takes over). For small pickers.
Future<T?> showCompactSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: context.palette.card,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Grabber(),
        Flexible(child: builder(ctx)),
      ],
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
