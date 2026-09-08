import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/hearth_spacing.dart';

/// A centred message on an otherwise empty screen (spec §5.8, §6.3).
///
/// Every empty state in the app is the same shape — a heading, a sentence
/// explaining the way out, sometimes a button — and every one of them was
/// written as a `Center` wrapping a `Column`. That clips: at accessibility
/// text sizes the words become taller than the screen, and a Column has
/// nowhere to put the overflow, so the bottom of the message is simply gone.
///
/// Scrollable, therefore, but only when it needs to be: the content stays
/// vertically centred while it fits, which is what makes an empty screen look
/// deliberate rather than top-aligned and forgotten. Dynamic type is honoured
/// by letting the layout give way, never by capping the text (§6.3).
class CentredMessage extends StatelessWidget {
  const CentredMessage({
    required this.children,
    this.gutter = HearthSpacing.lg,
    this.maxWidth = 380,
    this.scrollable = true,
    super.key,
  });

  final List<Widget> children;
  final double gutter;

  /// A line of prose is unreadable when it runs the full width of a tablet.
  final double maxWidth;

  /// Whether this should scroll when it does not fit.
  ///
  /// False when the caller is already handling that — a
  /// `SliverFillRemaining(hasScrollBody: false)`, say, which asks its child
  /// for an intrinsic height and cannot get one through a `LayoutBuilder`.
  /// Saying so up front is what lets that caller size itself properly, rather
  /// than claiming a whole viewport of scroll it does not need.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final Widget content = _CappedWidth(
      maxWidth: maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );

    if (!scrollable) {
      return Padding(
        padding: EdgeInsets.all(gutter),
        child: Center(child: content),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Unbounded height means this is already inside something that scrolls
        // — a sliver, or another scroll view. Adding a second scrollable there
        // is both wrong and, because the minimum height would be infinite, a
        // hard layout error. Just lay the content out.
        if (!constraints.hasBoundedHeight) {
          return Padding(
            padding: EdgeInsets.all(gutter),
            child: Center(child: content),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(gutter),
          child: ConstrainedBox(
            // Centres while it fits; scrolls once it does not.
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - gutter * 2).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

/// A width cap that is honoured when the height is *measured*, not only when
/// it is laid out.
///
/// A `ConstrainedBox` would be the obvious way to say "no wider than this",
/// and it is wrong here in a way that only shows up on a wide window at a
/// large text size. Its intrinsic methods pass the incoming width straight
/// to the child (`RenderConstrainedBox.computeMaxIntrinsicHeight` calls
/// `super` with the unclamped width), so a caller asking "how tall are you at
/// 950 points across?" is answered for text that will then be laid out at
/// 380 and wrap two and a half times taller.
///
/// The caller doing the asking is
/// `SliverFillRemaining(hasScrollBody: false)`, which sizes itself from that
/// answer. On a desktop window at 3x type it sized the Recipes empty state
/// from a measurement 318 points short, and the sentence explaining how to
/// add a first recipe was cut off — on the one screen that exists to explain
/// it, to the reader least able to guess what was missing.
class _CappedWidth extends SingleChildRenderObjectWidget {
  const _CappedWidth({required this.maxWidth, required Widget super.child});

  final double maxWidth;

  @override
  _RenderCappedWidth createRenderObject(BuildContext context) =>
      _RenderCappedWidth(maxWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCappedWidth renderObject,
  ) {
    renderObject.maxWidth = maxWidth;
  }
}

class _RenderCappedWidth extends RenderProxyBox {
  _RenderCappedWidth(this._maxWidth);

  double _maxWidth;
  double get maxWidth => _maxWidth;
  set maxWidth(double value) {
    if (_maxWidth == value) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  /// The one place the cap is applied, so measuring and laying out cannot
  /// disagree — which is the entire bug this widget exists for.
  ///
  /// `enforce` rather than `copyWith(maxWidth:)`, which is the same choice
  /// `ConstrainedBox` makes and for a reason worth keeping: a parent that
  /// hands down a *tight* width wider than the cap would give `copyWith` a
  /// minimum above its own maximum, and constraints in that state are a
  /// layout assertion rather than a narrow box. `enforce` clamps the cap into
  /// the incoming range instead, so the cap yields to a width it is not
  /// allowed to argue with. Nothing hands down such a width today — every
  /// path here passes through a `Center`, which loosens — but this widget
  /// lives in `app/widgets` and the next caller need not.
  BoxConstraints _cap(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: _maxWidth).enforce(constraints);

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.min(super.computeMinIntrinsicWidth(height), _maxWidth);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.min(super.computeMaxIntrinsicWidth(height), _maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(math.min(width, _maxWidth));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(math.min(width, _maxWidth));

  @override
  Size computeDryLayout(BoxConstraints constraints) => child == null
      ? _cap(constraints).smallest
      : child!.getDryLayout(_cap(constraints));

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => child?.getDryBaseline(_cap(constraints), baseline);

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = _cap(constraints).smallest;
      return;
    }
    child.layout(_cap(constraints), parentUsesSize: true);
    size = child.size;
  }
}
