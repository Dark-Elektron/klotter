/// How a 3D plot is sized and placed inside its panel.
///
/// The two half-extents make the world box a cuboid — z is the long axis,
/// because a plot lives in a portrait panel and z is the only axis with
/// anywhere to grow. The offsets centre what those extents actually draw,
/// which is not the same as centring the origin they are measured from:
/// perspective throws the near-bottom corner much further from the origin
/// than the far-top one, so a box centred on the origin hangs low.
class ViewFit {
  const ViewFit({
    required this.planar,
    required this.vertical,
    required this.offsetX,
    required this.offsetY,
  });

  /// Half-extent of the box in x and y.
  final double planar;

  /// Half-extent of the box in z.
  final double vertical;

  /// Screen-space shift that puts the drawing in the middle of the panel.
  final double offsetX, offsetY;
}
