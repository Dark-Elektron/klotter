import 'package:flutter/painting.dart';

import '../plotting/utils/plot_cache.dart';

/// What was let go of, so the caller can say so and a test can check it.
typedef ReleasedMemory = ({int plotEntries, int images});

/// Give back everything that can be recomputed.
///
/// Called when the app is backgrounded and when the platform asks for memory.
/// Android decides what to kill by how much a process is holding, and an app in
/// the background is holding it for nothing: the plot geometry is not being
/// drawn and the decoded images are not being shown. Keeping them is what makes
/// the app the obvious thing to kill after a long spell in another app — which
/// the user then meets as a crash on the way back.
///
/// Everything dropped here is derived, so the cost of returning is recomputing
/// it: a resample per plot, in single-digit milliseconds, and a re-decode of
/// whatever is on screen.
ReleasedMemory releaseMemoryForBackground() {
  final int plotEntries = releasePlotGeometry();

  final ImageCache cache = PaintingBinding.instance.imageCache;
  final int images = cache.liveImageCount + cache.currentSize;
  // Both halves. `clear` empties the cache of images nothing is using;
  // `clearLiveImages` releases those still referenced by a widget, which is
  // most of them while a screen is built and is where the megabytes are. They
  // re-decode from their providers when next painted.
  cache.clear();
  cache.clearLiveImages();

  return (plotEntries: plotEntries, images: images);
}
