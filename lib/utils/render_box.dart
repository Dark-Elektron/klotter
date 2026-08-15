import 'package:flutter/widgets.dart';

/// The [RenderBox] for [context], but only when its geometry can be read.
///
/// `RenderBox.size` and `localToGlobal` assert `!debugNeedsLayout`: a box that
/// has been rebuilt but not yet laid out has no honest answer to give, so
/// asking throws
/// `'debugNeedsLayout': is not true` rather than returning a stale value. That
/// is easy to hit from a gesture callback, which can run between a rebuild and
/// the layout that follows it.
///
/// Returns null instead, so callers skip the frame rather than crash. The
/// debug-only flag is read inside an `assert` because `debugNeedsLayout` is
/// only assigned in debug builds — reading it directly in release throws a
/// late-initialisation error.
RenderBox? laidOutBox(BuildContext? context) {
  final RenderObject? object = context?.findRenderObject();
  if (object is! RenderBox) return null;
  if (!object.attached || !object.hasSize) return null;

  bool needsLayout = false;
  assert(() {
    needsLayout = object.debugNeedsLayout;
    return true;
  }());
  return needsLayout ? null : object;
}
