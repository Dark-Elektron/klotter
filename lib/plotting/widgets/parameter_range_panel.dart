import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/parametric.dart';

/// Read a parameter bound the way it is most often written.
///
/// Parametric ranges are nearly always multiples of π — a full turn, a half
/// turn, a quarter — so `2π`, `-π/2` and `pi` are accepted alongside plain
/// numbers. Returns null when the text is not a bound, which the caller shows
/// as a rejected field rather than silently substituting a value.
double? parseParameterBound(String text) {
  final String t = text.trim().replaceAll('pi', 'π').replaceAll(' ', '');
  if (t.isEmpty) return null;

  final double? plain = double.tryParse(t);
  if (plain != null) return plain;

  // [sign][coefficient]π[/divisor]
  final RegExpMatch? m = RegExp(
    r'^([+-]?)(\d*\.?\d*)π(?:/(\d*\.?\d+))?$',
  ).firstMatch(t);
  if (m == null) return null;

  final double coefficient =
      m.group(2)!.isEmpty ? 1.0 : (double.tryParse(m.group(2)!) ?? 1.0);
  final double divisor =
      m.group(3) == null ? 1.0 : (double.tryParse(m.group(3)!) ?? 1.0);
  if (divisor == 0) return null;

  final double value = coefficient * math.pi / divisor;
  return m.group(1) == '-' ? -value : value;
}

/// Render a bound back in the notation it was probably typed in.
String formatParameterBound(double value) {
  if (value == 0) return '0';
  final double turns = value / math.pi;
  // Only for the fractions worth naming; anything else reads better as a
  // decimal than as a ratio of π nobody recognises.
  for (final int d in const <int>[1, 2, 3, 4, 6]) {
    for (int n = 1; n <= 4 * d; n++) {
      if ((turns.abs() - n / d).abs() < 1e-9) {
        final String sign = value < 0 ? '-' : '';
        final String top = n == 1 ? 'π' : '$nπ';
        return d == 1 ? '$sign$top' : '$sign$top/$d';
      }
    }
  }
  // Two decimals at most, with trailing zeros dropped, so 2.5 reads as "2.5"
  // and 1 as "1" rather than "2.50" and "1.00".
  final String s = value.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// The translucent chip showing what one parameter is swept over.
///
/// Bottom left of the plot, stacked with u above v, and only for the
/// parameters the expression actually uses — a curve in u has nothing to say
/// about v.
class ParameterRangeChip extends StatelessWidget {
  const ParameterRangeChip({
    super.key,
    required this.name,
    required this.range,
    required this.onChanged,
  });

  /// 'u' or 'v'.
  final String name;
  final ParameterRange range;
  final ValueChanged<ParameterRange> onChanged;

  Future<void> _edit(BuildContext context) async {
    final ParameterRange? next = await showDialog<ParameterRange>(
      context: context,
      builder: (_) => _ParameterRangeDialog(name: name, range: range),
    );
    if (next != null) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$name range',
      child: GestureDetector(
        onTap: () => _edit(context),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$name ∈ [${formatParameterBound(range.min)}, '
            '${formatParameterBound(range.max)}]',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class _ParameterRangeDialog extends StatefulWidget {
  const _ParameterRangeDialog({required this.name, required this.range});

  final String name;
  final ParameterRange range;

  @override
  State<_ParameterRangeDialog> createState() => _ParameterRangeDialogState();
}

class _ParameterRangeDialogState extends State<_ParameterRangeDialog> {
  late final TextEditingController _min = TextEditingController(
    text: formatParameterBound(widget.range.min),
  );
  late final TextEditingController _max = TextEditingController(
    text: formatParameterBound(widget.range.max),
  );
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _submit() {
    final double? lo = parseParameterBound(_min.text);
    final double? hi = parseParameterBound(_max.text);
    if (lo == null || hi == null) {
      setState(() => _error = 'Use a number or a multiple of π, like 2π.');
      return;
    }
    if (lo == hi) {
      // A zero-width sweep is a single point, which draws nothing — better to
      // say so than to accept it and leave an empty plot.
      setState(() => _error = 'The range needs a width.');
      return;
    }
    Navigator.of(context).pop((min: lo, max: hi));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c) => TextField(
      controller: c,
      autocorrect: false,
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) => _submit(),
    );

    return AlertDialog(
      title: Text('Range of ${widget.name}'),
      // Scrollable, because in landscape the keyboard leaves a dialog barely
      // taller than its own two fields — 12 px short, on the tablet.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            field('Minimum', _min),
            field('Maximum', _max),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(defaultParameterRange),
          child: const Text('Reset'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Apply')),
      ],
    );
  }
}
