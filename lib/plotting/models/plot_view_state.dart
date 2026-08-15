/// How a cell's plot is currently being looked at.
///
/// Kept apart from the expression because it survives differently: the
/// expression is what you typed, this is where you got to by dragging. Losing
/// it on restart meant carefully framing `x` over `[0, 2π]`, closing the app,
/// and finding `[-5, 5]` again.
class PlotViewState {
  const PlotViewState({
    this.show3D = false,
    this.xMin = -5,
    this.xMax = 5,
    this.yMin = -5,
    this.yMax = 5,
    this.rotationX = 0.6,
    this.rotationZ = 0.8,
    this.panX = 0,
    this.panY = 0,
    this.rangeX = 5,
    this.rangeY = 5,
    this.rangeZ = 5,
    this.uMin = 0,
    this.uMax = 1,
    this.vMin = 0,
    this.vMax = 1,
  });

  /// Which view the cell was left showing.
  final bool show3D;

  /// The 2D window.
  final double xMin, xMax, yMin, yMax;

  /// The 3D camera and box.
  final double rotationX, rotationZ, panX, panY, rangeX, rangeY, rangeZ;

  /// What u and v are swept over. Part of the view rather than of the
  /// expression: the sweep is something you dialled in, and swiping to the
  /// next plot and back used to hand it silently back to the default.
  final double uMin, uMax, vMin, vMax;

  static const PlotViewState initial = PlotViewState();

  /// True when this is still the untouched default, so a cell that was never
  /// dragged does not need storing.
  bool get isInitial =>
      show3D == initial.show3D &&
      xMin == initial.xMin &&
      xMax == initial.xMax &&
      yMin == initial.yMin &&
      yMax == initial.yMax &&
      rotationX == initial.rotationX &&
      rotationZ == initial.rotationZ &&
      panX == initial.panX &&
      panY == initial.panY &&
      rangeX == initial.rangeX &&
      rangeY == initial.rangeY &&
      rangeZ == initial.rangeZ &&
      uMin == initial.uMin &&
      uMax == initial.uMax &&
      vMin == initial.vMin &&
      vMax == initial.vMax;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'show3D': show3D,
    'xMin': xMin,
    'xMax': xMax,
    'yMin': yMin,
    'yMax': yMax,
    'rotationX': rotationX,
    'rotationZ': rotationZ,
    'panX': panX,
    'panY': panY,
    'rangeX': rangeX,
    'rangeY': rangeY,
    'rangeZ': rangeZ,
    'uMin': uMin,
    'uMax': uMax,
    'vMin': vMin,
    'vMax': vMax,
  };

  /// Restore a view, falling back to the default for anything missing or
  /// unusable.
  ///
  /// Every field is defended individually rather than the whole record being
  /// discarded on one bad value: a saved view is a convenience, and half of it
  /// is better than dropping the user back to the origin. A window with zero
  /// or negative width is rejected outright, since it renders as a blank plot
  /// with nothing to explain it.
  factory PlotViewState.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback) {
      final Object? v = json[key];
      if (v is num && v.isFinite) return v.toDouble();
      return fallback;
    }

    double xMin = read('xMin', initial.xMin);
    double xMax = read('xMax', initial.xMax);
    double yMin = read('yMin', initial.yMin);
    double yMax = read('yMax', initial.yMax);
    if (xMax - xMin < 1e-9) {
      xMin = initial.xMin;
      xMax = initial.xMax;
    }
    if (yMax - yMin < 1e-9) {
      yMin = initial.yMin;
      yMax = initial.yMax;
    }

    double positive(String key, double fallback) {
      final double v = read(key, fallback);
      return v > 0 ? v : fallback;
    }

    // A zero-width sweep draws nothing, so it is rejected the same way a
    // zero-width window is.
    double uMin = read('uMin', initial.uMin);
    double uMax = read('uMax', initial.uMax);
    double vMin = read('vMin', initial.vMin);
    double vMax = read('vMax', initial.vMax);
    if ((uMax - uMin).abs() < 1e-9) {
      uMin = initial.uMin;
      uMax = initial.uMax;
    }
    if ((vMax - vMin).abs() < 1e-9) {
      vMin = initial.vMin;
      vMax = initial.vMax;
    }

    return PlotViewState(
      show3D: json['show3D'] == true,
      xMin: xMin,
      xMax: xMax,
      yMin: yMin,
      yMax: yMax,
      rotationX: read('rotationX', initial.rotationX),
      rotationZ: read('rotationZ', initial.rotationZ),
      panX: read('panX', initial.panX),
      panY: read('panY', initial.panY),
      rangeX: positive('rangeX', initial.rangeX),
      rangeY: positive('rangeY', initial.rangeY),
      rangeZ: positive('rangeZ', initial.rangeZ),
      uMin: uMin,
      uMax: uMax,
      vMin: vMin,
      vMax: vMax,
    );
  }

  PlotViewState copyWith({
    bool? show3D,
    double? xMin,
    double? xMax,
    double? yMin,
    double? yMax,
    double? rotationX,
    double? rotationZ,
    double? panX,
    double? panY,
    double? rangeX,
    double? rangeY,
    double? rangeZ,
    double? uMin,
    double? uMax,
    double? vMin,
    double? vMax,
  }) {
    return PlotViewState(
      show3D: show3D ?? this.show3D,
      xMin: xMin ?? this.xMin,
      xMax: xMax ?? this.xMax,
      yMin: yMin ?? this.yMin,
      yMax: yMax ?? this.yMax,
      rotationX: rotationX ?? this.rotationX,
      rotationZ: rotationZ ?? this.rotationZ,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      rangeX: rangeX ?? this.rangeX,
      rangeY: rangeY ?? this.rangeY,
      rangeZ: rangeZ ?? this.rangeZ,
      uMin: uMin ?? this.uMin,
      uMax: uMax ?? this.uMax,
      vMin: vMin ?? this.vMin,
      vMax: vMax ?? this.vMax,
    );
  }
}
