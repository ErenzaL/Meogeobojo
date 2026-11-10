import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [content] followed by [footer]; when both together are shorter than [minHeight] the footer sits at the bottom of that
/// height (a short page, a tall window), otherwise it simply follows the content. Both children are laid out for real
/// (no intrinsic-size guessing), so a footer made of wrapping text and responsive columns is measured exactly.
class BottomPinned extends MultiChildRenderObjectWidget {
  BottomPinned({
    super.key,
    required this.minHeight,
    required Widget content,
    required Widget footer,
  }) : super(children: [content, footer]);

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBottomPinned(minHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderBottomPinned).minHeight = minHeight;
}

/// Parent data of the two children (offsets set by the layout).
class _ParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderBottomPinned extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ParentData> {
  _RenderBottomPinned(this._minHeight);

  double _minHeight;
  double get minHeight => _minHeight;
  set minHeight(double v) {
    if (v == _minHeight) return;
    _minHeight = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ParentData) child.parentData = _ParentData();
  }

  @override
  void performLayout() {
    final content = firstChild!;
    final footer = childAfter(content)!;
    final inner = BoxConstraints(maxWidth: constraints.maxWidth);
    content.layout(inner, parentUsesSize: true);
    footer.layout(inner, parentUsesSize: true);
    final natural = content.size.height + footer.size.height;
    final height = natural < _minHeight ? _minHeight : natural;
    size = constraints.constrain(Size(constraints.maxWidth, height));
    (content.parentData! as _ParentData).offset = Offset.zero;
    (footer.parentData! as _ParentData).offset = Offset(
      0,
      size.height - footer.size.height,
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsic(width);
  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsic(width);
  double _intrinsic(double width) {
    final content = firstChild!;
    final footer = childAfter(content)!;
    final h =
        content.getMaxIntrinsicHeight(width) +
        footer.getMaxIntrinsicHeight(width);
    return h < _minHeight ? _minHeight : h;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
