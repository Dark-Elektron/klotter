import 'dart:async';

/// When a result is written in scientific notation.
enum NumberFormat {
  automatic, // Scientific only for very large/small numbers
  scientific, // Always scientific notation
  plain, // Commas, never scientific
}

/// How the engine writes numbers: how many decimal places, and when it
/// switches to scientific notation.
///
/// Given to a call rather than set on the engine. It used to be two static
/// fields on MathSolverNew that the settings wrote into, which had the engine
/// import the settings — a Flutter class — for one enum, let every test that
/// changed them leak into the next, and left an isolate on the defaults
/// whatever the settings said.
///
/// Numbers are formatted deep inside the engine (every exact value formats
/// its own digits when it becomes nodes), so rather than thread a parameter
/// through all of it, [apply] makes a formatting the current one for the
/// duration of a call, everything it calls included.
class NumberFormatting {
  const NumberFormatting({
    this.precision = 6,
    this.format = NumberFormat.automatic,
  });

  /// Decimal places.
  final int precision;

  final NumberFormat format;

  /// The formatting in force: the one [apply] was given around this call, or
  /// the defaults.
  static NumberFormatting get current =>
      Zone.current[_key] as NumberFormatting? ?? const NumberFormatting();

  /// [body], with numbers written as this says throughout it.
  R apply<R>(R Function() body) =>
      runZoned(body, zoneValues: <Object, Object>{_key: this});

  static final Object _key = Object();

  @override
  bool operator ==(Object other) =>
      other is NumberFormatting &&
      other.precision == precision &&
      other.format == format;

  @override
  int get hashCode => Object.hash(precision, format);

  @override
  String toString() => 'NumberFormatting($precision, ${format.name})';
}
