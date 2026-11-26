import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/embed/preview_bridge.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_palette.dart';

/// The phone's size in logical pixels: an iPhone 17 Pro, the simulator the app is developed on.
const kPhoneWidth = 402.0;
const kPhoneHeight = 874.0;

/// Corner radius of the screen, and the bezel around it, in the preview's own (unscaled) pixels.
const kPhoneScreenRadius = 55.0;
const kPhoneBezel = 12.0;

/// How much to shrink the phone so it fits the window. Never below 0.45, never above 1, always leaving room for the
/// frame and the buttons.
double previewScale(Size window) {
  const marginY = 2 * 56.0, marginX = 2 * 24.0;
  final fitH = (window.height - marginY) / (kPhoneHeight + 2 * kPhoneBezel);
  final fitW = (window.width - marginX) / (kPhoneWidth + 2 * kPhoneBezel);
  return math.max(0.45, math.min(1.0, math.min(fitH, fitW)));
}

/// The page the preview shows: THE SAME website, in its phone mode. Same origin, so the Supabase session, the language
/// and the campus are shared with the page that opened it.
String previewUrl(Uri base, {String tab = 'home'}) {
  // only a web page has an origin; anything else (tests) gets a page-relative address
  final web = base.scheme == 'http' || base.scheme == 'https';
  return '${web ? base.origin : ''}/?embed=phone#/$tab';
}

/// What a frame builder gets: the page to show, how it is scaled and rounded, and a call for when it has loaded.
class PreviewFrameConfig {
  const PreviewFrameConfig({
    required this.url,
    required this.scale,
    required this.onLoaded,
  });

  final String url;
  final double scale;
  final VoidCallback onLoaded;
}

typedef PreviewFrameBuilder = Widget Function(PreviewFrameConfig config);

/// Builds the iframe. Overridable: tests (which have no browser) put a plain box here.
final previewFrameBuilderProvider = Provider<PreviewFrameBuilder>(
  (_) =>
      (config) => _IframeFrame(config: config),
);

/// A real `<iframe>` of the site, 390 x 844 CSS pixels, scaled visually.
class _IframeFrame extends StatefulWidget {
  const _IframeFrame({required this.config});

  final PreviewFrameConfig config;

  @override
  State<_IframeFrame> createState() => _IframeFrameState();
}

class _IframeFrameState extends State<_IframeFrame> {
  Object? _element;

  @override
  void didUpdateWidget(_IframeFrame old) {
    super.didUpdateWidget(old);
    final el = _element;
    if (el != null && old.config.scale != widget.config.scale) {
      scalePreviewIframe(el, widget.config.scale);
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      _element = element;
      configurePreviewIframe(
        element,
        src: widget.config.url,
        width: kPhoneWidth,
        height: kPhoneHeight,
        scale: widget.config.scale,
        radius: kPhoneScreenRadius,
        onLoaded: widget.config.onLoaded,
      );
    },
  );
}

/// The preview: the real app in a phone-sized frame over the website. [onClose] ends it.
class PhonePreviewDialog extends ConsumerStatefulWidget {
  const PhonePreviewDialog({super.key, required this.url});

  final String url;

  @override
  ConsumerState<PhonePreviewDialog> createState() => _PhonePreviewDialogState();
}

class _PhonePreviewDialogState extends ConsumerState<PhonePreviewDialog> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final build = ref.watch(previewFrameBuilderProvider);
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, box) {
            final s = previewScale(box.biggest);
            final w = kPhoneWidth * s, h = kPhoneHeight * s;
            return Stack(
              children: [
                // a click on the dim area closes the preview
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('preview-backdrop'),
                    behavior: HitTestBehavior.opaque,
                    onTap: close,
                  ),
                ),
                Center(
                  child: _SideButtons(
                    scale: s,
                    child: DecoratedBox(
                      key: const ValueKey('preview-frame'),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(
                          (kPhoneScreenRadius + kPhoneBezel) * s,
                        ),
                        border: Border.all(
                          color: Colors.grey.shade800,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(kPhoneBezel * s),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            kPhoneScreenRadius * s,
                          ),
                          child: SizedBox(
                            key: const ValueKey('preview-screen'),
                            width: w,
                            height: h,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(color: p.background),
                                if (!_loaded)
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 26,
                                          height: 26,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          l10n.previewLoading,
                                          style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                build(
                                  PreviewFrameConfig(
                                    url: widget.url,
                                    scale: s,
                                    onLoaded: () {
                                      if (mounted) {
                                        setState(() => _loaded = true);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 16,
                  child: Row(
                    children: [
                      _RoundButton(
                        key: const ValueKey('preview-close'),
                        tooltip: l10n.previewClose,
                        icon: Icons.close_rounded,
                        onPressed: close,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.grey.shade900,
    ),
    icon: Icon(icon),
  );
}

/// The hardware buttons on the phone's edge (action + volume on the left, power on the right), so it reads as a phone.
class _SideButtons extends StatelessWidget {
  const _SideButtons({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget bar({
      required double top,
      required double height,
      required bool left,
    }) => Positioned(
      top: (kPhoneBezel + top) * scale,
      left: left ? -3.5 * scale : null,
      right: left ? null : -3.5 * scale,
      width: 4 * scale,
      height: height * scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(2 * scale),
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        bar(top: 118, height: 30, left: true), // action button
        bar(top: 170, height: 58, left: true), // volume up
        bar(top: 240, height: 58, left: true), // volume down
        bar(top: 200, height: 92, left: false), // side button
      ],
    );
  }
}
