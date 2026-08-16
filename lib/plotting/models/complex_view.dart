/// Which components of a complex function are on show.
///
/// A set rather than a choice: the domain colouring says what f *is* at every
/// point and the Pólya field says where it is *going*, and the two read best
/// together — the arrows converge on the dark spots and stream out of the
/// bright ones. In 3D the same set picks which height surfaces are drawn, so
/// real, imaginary and modulus can be compared on one pair of axes.
class ComplexView {
  const ComplexView({
    this.colouring = true,
    this.polya = false,
    this.real = false,
    this.imaginary = false,
    this.modulus = true,
  });

  /// Domain colouring, in 2D.
  final bool colouring;

  /// The Pólya vector field, in 2D.
  final bool polya;

  /// Height surfaces, in 3D.
  final bool real, imaginary, modulus;

  /// What a newly drawn complex plot shows: the colouring in 2D, the modulus
  /// in 3D. Both are the reading that needs least explaining.
  static const ComplexView initial = ComplexView();

  bool get showsColouring => colouring;
  bool get showsPolya => polya;

  /// True when nothing at all is selected, which callers draw as bare axes
  /// rather than as an empty picture with no explanation.
  bool get isEmpty => !colouring && !polya && !real && !imaginary && !modulus;

  ComplexView copyWith({
    bool? colouring,
    bool? polya,
    bool? real,
    bool? imaginary,
    bool? modulus,
  }) => ComplexView(
    colouring: colouring ?? this.colouring,
    polya: polya ?? this.polya,
    real: real ?? this.real,
    imaginary: imaginary ?? this.imaginary,
    modulus: modulus ?? this.modulus,
  );

  /// Packed into an int so it can travel with the rest of the saved view.
  int get bits =>
      (colouring ? 1 : 0) |
      (polya ? 2 : 0) |
      (real ? 4 : 0) |
      (imaginary ? 8 : 0) |
      (modulus ? 16 : 0);

  factory ComplexView.fromBits(int bits) => ComplexView(
    colouring: bits & 1 != 0,
    polya: bits & 2 != 0,
    real: bits & 4 != 0,
    imaginary: bits & 8 != 0,
    modulus: bits & 16 != 0,
  );

  @override
  bool operator ==(Object other) => other is ComplexView && other.bits == bits;

  @override
  int get hashCode => bits;
}
