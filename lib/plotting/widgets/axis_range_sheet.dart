import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// The window a plot is showing.
typedef AxisRanges = ({double xMin, double xMax, double yMin, double yMax});

/// Numeric entry for the plot window.
///
/// Pinching can get you *near* a range but never onto one — there is no
/// gesture that lands exactly on x ∈ [0, 2π]. Accepts the constants and simple
/// arithmetic you would actually type for a bound, so `2pi` and `-pi/2` work
/// without leaving the sheet to compute them.
class AxisRangeSheet extends StatefulWidget {
  final AxisRanges initial;
  final AppColors colors;

  const AxisRangeSheet({
    super.key,
    required this.initial,
    required this.colors,
  });

  @override
  State<AxisRangeSheet> createState() => _AxisRangeSheetState();

  /// Show the sheet and return the chosen ranges, or null if dismissed.
  static Future<AxisRanges?> show(
    BuildContext context, {
    required AxisRanges initial,
    required AppColors colors,
  }) {
    return showModalBottomSheet<AxisRanges>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AxisRangeSheet(initial: initial, colors: colors),
    );
  }
}

class _AxisRangeSheetState extends State<AxisRangeSheet> {
  late final TextEditingController _xMin;
  late final TextEditingController _xMax;
  late final TextEditingController _yMin;
  late final TextEditingController _yMax;
  String? _error;

  @override
  void initState() {
    super.initState();
    String f(double v) {
      final String s = v.toStringAsFixed(4);
      return s.contains('.')
          ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
          : s;
    }

    _xMin = TextEditingController(text: f(widget.initial.xMin));
    _xMax = TextEditingController(text: f(widget.initial.xMax));
    _yMin = TextEditingController(text: f(widget.initial.yMin));
    _yMax = TextEditingController(text: f(widget.initial.yMax));
  }

  @override
  void dispose() {
    _xMin.dispose();
    _xMax.dispose();
    _yMin.dispose();
    _yMax.dispose();
    super.dispose();
  }

  void _apply() {
    final double? x0 = parseBound(_xMin.text);
    final double? x1 = parseBound(_xMax.text);
    final double? y0 = parseBound(_yMin.text);
    final double? y1 = parseBound(_yMax.text);

    if (x0 == null || x1 == null || y0 == null || y1 == null) {
      setState(() => _error = 'Enter a number, or something like 2pi or -pi/2');
      return;
    }
    if (x1 - x0 < 1e-9 || y1 - y0 < 1e-9) {
      setState(() => _error = 'Each maximum must be greater than its minimum');
      return;
    }
    Navigator.pop<AxisRanges>(context, (
      xMin: x0,
      xMax: x1,
      yMin: y0,
      yMax: y1,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.containerBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Plot range',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field('x min', _xMin, c)),
                const SizedBox(width: 10),
                Expanded(child: _field('x max', _xMax, c)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _field('y min', _yMin, c)),
                const SizedBox(width: 10),
                Expanded(child: _field('y max', _yMax, c)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _apply, child: const Text('Apply')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, AppColors c) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: TextStyle(color: c.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 13),
        isDense: true,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.divider),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.accent),
        ),
      ),
      onSubmitted: (_) => _apply(),
    );
  }
}

/// Parse an axis bound.
///
/// Deliberately small: a signed decimal, optionally with `pi`/`e`, and at most
/// one multiply or divide. That covers what people actually type for a bound
/// (`2pi`, `-pi/2`, `1e3`) without pulling the full expression engine into a
/// text field, where a half-typed expression would have to mean something.
double? parseBound(String input) {
  String t = input.trim().toLowerCase().replaceAll(' ', '');
  if (t.isEmpty) return null;
  t = t.replaceAll('π', 'pi').replaceAll('×', '*').replaceAll('÷', '/');

  double? atom(String s) {
    if (s.isEmpty) return null;
    bool negative = false;
    while (s.startsWith('-') || s.startsWith('+')) {
      if (s.startsWith('-')) negative = !negative;
      s = s.substring(1);
    }
    if (s.isEmpty) return null;

    double? value;
    if (s == 'pi') {
      value = math.pi;
    } else if (s == 'e') {
      value = math.e;
    } else if (s.endsWith('pi')) {
      final double? k = double.tryParse(s.substring(0, s.length - 2));
      if (k != null) value = k * math.pi;
    } else if (s.endsWith('e') && s.length > 1) {
      final double? k = double.tryParse(s.substring(0, s.length - 1));
      if (k != null) value = k * math.e;
    } else {
      value = double.tryParse(s);
    }
    if (value == null) return null;
    return negative ? -value : value;
  }

  // One optional operator, searched from index 1 so a leading sign is not it.
  for (int i = 1; i < t.length; i++) {
    final String ch = t[i];
    if (ch != '*' && ch != '/') continue;
    final double? a = atom(t.substring(0, i));
    final double? b = atom(t.substring(i + 1));
    if (a == null || b == null) return null;
    if (ch == '/') {
      if (b == 0) return null;
      return a / b;
    }
    return a * b;
  }

  return atom(t);
}
