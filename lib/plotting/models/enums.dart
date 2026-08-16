enum Tool3DMode { zoom, pan }

enum PlotMode { function, field }

enum FieldType { scalar, vector }

enum SurfaceMode { none, magnitude, x, y, z }

enum ZoomAxis { free, x, y, z }

/// Which real-valued reading of a complex function a 3D surface shows.
///
/// A complex function has no single height, so the vertical axis has to be
/// told which of these to stand for. Any of them can be drawn at once, on the
/// same axes.
enum ComplexPart { real, imaginary, modulus }
