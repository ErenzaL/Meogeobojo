import 'package:flutter/material.dart';

/// Kakao Login button following Kakao's published button guideline: yellow
/// (#FEE500) container, 12px corners, symbol + label in 85% black.
///
/// NOTE: the symbol below is drawn in code as a speech-bubble approximation.
/// Before store submission, replace [_KakaoSymbol] with the official symbol
/// asset from Kakao Developers (Kakao requires the unmodified symbol).
class KakaoLoginButton extends StatelessWidget {
  const KakaoLoginButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  static const yellow = Color(0xFFFEE500);
  static const ink = Color(0xD9000000); // #000000 @ 85%

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Material(
        color: onPressed == null ? yellow.withValues(alpha: 0.5) : yellow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _KakaoSymbol(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KakaoSymbol extends StatelessWidget {
  const _KakaoSymbol();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _SymbolPainter()),
    ),
  );
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Path()
      ..addOval(Rect.fromLTWH(0, h * 0.04, w, h * 0.78))
      ..moveTo(w * 0.22, h * 0.72)
      ..lineTo(w * 0.16, h * 0.97)
      ..lineTo(w * 0.46, h * 0.8)
      ..close();
    canvas.drawPath(body, Paint()..color = KakaoLoginButton.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
