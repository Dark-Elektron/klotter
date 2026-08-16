import 'package:flutter/material.dart';

/// What the user decided about clearing everything.
///
/// [dontAskAgain] is reported separately from [confirmed] so the caller can
/// act on the tick only if the clear actually went ahead. Ticking the box and
/// then backing out should not quietly disable a warning you just declined.
typedef ClearAllChoice = ({bool confirmed, bool dontAskAgain});

/// Ask before wiping every cell.
///
/// Returns null when the dialog is dismissed without an answer, which is the
/// same as cancelling.
Future<ClearAllChoice?> showConfirmClearDialog(BuildContext context) {
  return showDialog<ClearAllChoice>(
    context: context,
    builder: (_) => const ConfirmClearDialog(),
  );
}

class ConfirmClearDialog extends StatefulWidget {
  const ConfirmClearDialog({super.key});

  @override
  State<ConfirmClearDialog> createState() => _ConfirmClearDialogState();
}

class _ConfirmClearDialogState extends State<ConfirmClearDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Clear all plots?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Every expression and its plot will be removed.'),
          const SizedBox(height: 12),
          // The reason this dialog exists. The key is undoable already and
          // always has been; nobody was told, so the loss felt permanent
          // whether or not it was.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.undo, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('You can bring them back with undo (⎌).'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Padding trimmed to nothing on the left so the checkbox lines up
          // with the text above rather than sitting in a dialog-sized inset.
          CheckboxListTile(
            value: _dontAskAgain,
            onChanged: (v) => setState(() => _dontAskAgain = v ?? false),
            title: const Text("Don't ask again"),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              () => Navigator.of(
                context,
              ).pop((confirmed: false, dontAskAgain: _dontAskAgain)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(
                context,
              ).pop((confirmed: true, dontAskAgain: _dontAskAgain)),
          child: const Text('Clear all'),
        ),
      ],
    );
  }
}
