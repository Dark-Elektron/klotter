# klotter

A scientific graphing calculator in Flutter. Each plot holds a stack of
expression rows typed on a custom keypad, and every edit redraws the plot live
(2D curves, surfaces, level sets, inequalities, vector fields, parametric
sweeps, complex functions).

klotter shares its origins with **klator**, the plain calculator, which lives
in a separate repository. The two forked at their first commit, so shared code
is ported by hand; the plan is one repository with two build flavours.

## Commands

```
flutter pub get
flutter analyze          # must report no issues; CI fails on warnings
flutter test             # the whole suite, about 70 s
flutter test test/plotting/plot_cache_test.dart   # one file
flutter run
```

Release builds: `flutter build appbundle --release`, then work through
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) on a device. Debug and release
measure geometry differently (see the checklist), so check release builds.

## Where things are

| Path | What it holds |
|---|---|
| `lib/notebook/notebook.dart` | The document: the plots in order (each with a stable `id`, its rows and its view), the open plot and row, adding and removing, saving and restoring, undo history |
| `lib/main.dart` | `HomePage`: draws the notebook, the page strip, the keypad handle, export. What it keeps per plot is keyed by `Plot.id` |
| `lib/keypad/` | The keypad. Layouts are authored by key name, right-handed, in `keypad.dart` |
| `lib/math_renderer/` | The node tree (`math_nodes.dart`), the editor (`math_editor_controller.dart` plus its `editor_*.dart` parts), drawing (`renderer.dart`), selection, persistence |
| `lib/math_engine/` | Plain Dart, no Flutter (`core_is_plain_dart_test` enforces it). `math_engine_exact.dart` turns nodes into `Expr` trees and simplifies them; `compiled_eval.dart` compiles an `Expr` into closures for sampling, with `expr_eval.dart` as the reference walk; `real_functions.dart` holds the hyperbolic functions; `number_format.dart` says how numbers are written |
| `lib/plotting/parsers/plot_expression.dart` | Compiles one row into something drawable: the coordinate system, relation and error |
| `lib/plotting/painters/` | The 2D painter, and the 3D painter with its `plot_3d_*.dart` parts by what they draw |
| `lib/plotting/utils/` | Marching squares and tetrahedra (`level_set.dart`), caches, colour maps, picking |
| `lib/settings/`, `lib/walkthrough/` | Settings, and the first-run tour |

A row's path to the screen: `List<MathNode>` → `MathNodeToExpr.convert(...)
.simplify()` → `PlotExpression.compile` (once per edit) → compiled to closures
on first use → `evaluate(x, y, z)` per sample. Geometry is cached against the
compiled expression's identity (`PlotCacheKey`), so keep compiled expressions
alive rather than recompiling per frame.

Large classes are split across `part` files as extensions on the class, by
what each part does. Statics stay in the class and are qualified from the
parts, and a `ChangeNotifier`'s parts notify through a private forwarder.

## Rules that are easy to break

- **Handedness.** Every UI change must respect the left-handed setting
  (`SettingsProvider.handedness`): anything anchored to one side, such as row
  chrome, plot controls and parameter chips, mirrors. Centred or full-width
  elements do not.
- **The phone keypad is klotter's own.** Two halves of 5×4 keys: the number
  pad under the dominant thumb (the right half for right-handers), the
  scientific and extras pages swiping in the other half, and ☰ and clear-all
  at the far outer edge. CE stays away from ⌫. Never copy klator's layout over
  it. `keypad_geometry_test`, `keypad_coordinates_test` and
  `keypad_tablet_test` guard it.
- **New nodes must be selectable.** A node drawn without a box in the layout
  registry cannot be tapped into, selected, copied or deleted. A node gets one
  by being wrapped in a `LayoutReporter`, which reports where it is painted;
  `LiteralWidget`, `AtomWidget` (π, x̂, z̲) and the composite wrapper all are.
  An atomic symbol is selected whole, never by character.
- **Plot performance is judged on devices.** The test VM runs two to three
  times faster than a mid-range phone. The benchmark shapes are Inigo
  Quilez's degree-4 surfaces, such as `x^4+y^4+z^4-x^2-y^2-z^2+0.4=0`.
- **The app works offline.** No network access; nothing leaves the device.

## Conventions

- Comments explain why, often with the bug that prompted the code. Keep that
  style, and name tests after the behaviour they pin down.
- Tests live under `test/` and must end in `_test.dart`, or they never run.
- Commits: `type: summary` in lowercase (`fix:`, `feat:`, `perf:`,
  `refactor:`, `test:`), with a body saying why. No AI attribution or
  co-author trailers.
- Line endings are LF (`.gitattributes`).
- A push to `main` builds the APK in CI and publishes it as the `latest`
  release when the signing secrets are configured.
