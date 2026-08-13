import 'dart:math';
import 'dart:ui';

class Point3D {
  final double x, y, z;
  const Point3D(this.x, this.y, this.z);

  Point3D rotateX(double angle) {
    final c = cos(angle), s = sin(angle);
    return Point3D(x, y * c - z * s, y * s + z * c);
  }

  Point3D rotateZ(double angle) {
    final c = cos(angle), s = sin(angle);
    return Point3D(x * c - y * s, x * s + y * c, z);
  }

  Offset project(double focalLength, Size size, double panX, double panY) {
    final scale = focalLength / (focalLength + y);
    return Offset(
      size.width / 2 + x * scale + panX,
      size.height / 2 - z * scale + panY,
    );
  }
}

class Quad {
  final Point3D p1, p2, p3, p4;
  final double avgDepth, avgValue;
  Quad(this.p1, this.p2, this.p3, this.p4, this.avgDepth, this.avgValue);
}

class FieldPoint3D {
  final Point3D point;
  final double value;
  FieldPoint3D(this.point, this.value);
}

class Arrow3D {
  final Point3D start;
  final double dx, dy, dz;
  final double magnitude;
  Arrow3D(this.start, this.dx, this.dy, this.dz, this.magnitude);
}
