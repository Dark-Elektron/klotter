import '../parsers/plot_expression.dart';

/// Which variable a 2D view of a 3D plot holds fixed.
enum SliceAxis {
  x,
  y,
  z;

  String get label => switch (this) {
    SliceAxis.x => 'x',
    SliceAxis.y => 'y',
    SliceAxis.z => 'z',
  };
}

/// The plane a 2D view of a 3D plot is showing.
///
/// A flat view of something three-dimensional is always a slice of it, and
/// until this existed the slice was fixed and unstated — and it was not even
/// the same slice twice. A level set was drawn by marching squares, which
/// samples `f(x, y)` and lets the third argument default, so it showed z = 0.
/// A height surface was drawn by evaluating `f(x, 0)`, so it showed y = 0.
/// Two plot types, two different planes, and nothing on screen naming either.
///
/// The two free variables keep their usual order — x before y before z — so
/// the plane you are looking at is decided entirely by [axis]: hold z and you
/// are looking at x across and y up, which is the view every 2D plot in the
/// app already had.
class PlaneSlice {
  const PlaneSlice({this.axis = SliceAxis.z, this.offset = 0});

  /// The variable held fixed; the normal of the plane on show.
  final SliceAxis axis;

  /// What it is held at.
  final double offset;

  /// The variable running left to right.
  String get horizontalName => axis == SliceAxis.x ? 'y' : 'x';

  /// The variable running bottom to top.
  ///
  /// For a height surface this is the value of the function rather than a free
  /// variable, but it is still z: `z = f(x, y)` sliced at y = c is a curve of
  /// z against x, and the axis it is drawn against means the same thing.
  String get verticalName => axis == SliceAxis.z ? 'y' : 'z';

  /// The variable pointing out of the plane, which is the one being held.
  ///
  /// Named rather than just read off [axis] because for a vector field it is
  /// the component the flat view cannot draw as a direction — it points at the
  /// reader — and that is worth saying where it is used.
  String get outOfPlaneName => axis.label;

  /// Whether this is the plane a plot opens on.
  bool get isDefault => axis == SliceAxis.z && offset == 0;

  /// Sample [f] at a point in the plane.
  ///
  /// A method rather than a `(x, y, z)` record because this is the hot path —
  /// marching squares asks for tens of thousands of values a frame — and a
  /// record per sample is an allocation per sample.
  double sample(PlotExpression f, double horizontal, double vertical) =>
      switch (axis) {
        SliceAxis.x => f.evaluate(offset, horizontal, vertical),
        SliceAxis.y => f.evaluate(horizontal, offset, vertical),
        SliceAxis.z => f.evaluate(horizontal, vertical, offset),
      };

  PlaneSlice withAxis(SliceAxis a) => PlaneSlice(axis: a, offset: offset);
  PlaneSlice withOffset(double o) => PlaneSlice(axis: axis, offset: o);

  @override
  bool operator ==(Object other) =>
      other is PlaneSlice && other.axis == axis && other.offset == offset;

  @override
  int get hashCode => Object.hash(axis, offset);

  @override
  String toString() => '${axis.label} = $offset';
}
