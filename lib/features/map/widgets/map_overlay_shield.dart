import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Keeps browser pointer events on Flutter overlays from reaching the HTML map.
class MapOverlayShield extends StatelessWidget {
  const MapOverlayShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => !kIsWeb
      ? child
      : Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: HtmlElementView.fromTagName(
                tagName: 'div',
                isVisible: false,
              ),
            ),
            child,
          ],
        );
}
