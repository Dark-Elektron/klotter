## Copilot / AI Agent Instructions — Klotter

Short, actionable guidance to be immediately productive in this repo.

1. Big picture
- Flutter app (multi-platform) that provides a multi-cell scientific calculator.
- UI bootstrap: [lib/main.dart](../lib/main.dart) — uses `SettingsProvider` (provider package) to control theme and numeric precision.
- Expression model and editor: [lib/renderer.dart](../lib/renderer.dart) — core `MathNode` tree types, `MathEditorController`, cursor/layout registry, and rendering helpers.
- Serialization: [lib/math_expression_serializer.dart](../lib/math_expression_serializer.dart) — converts node trees to PEMDAS-friendly strings and JSON for persistence.
- Evaluation & solving: [lib/math_engine.dart](../lib/math_engine.dart) — `MathSolverNew` takes expression strings (uses `ansX` expansion) and returns formatted results or equation solutions.
- Persistence: see [lib/cell_persistence_service.dart](../lib/cell_persistence_service.dart) used from `main.dart` to save/load cells and active index.

2. Key data flows & conventions
- In-memory expression = List<`MathNode`> (start point: `LiteralNode`).
- To persist: `MathExpressionSerializer.serializeToJson(expression)` and later `deserializeFromJson`.
- To evaluate/solve: convert tree to solver string with `MathExpressionSerializer.toSolverFormat(expression)` then call `MathSolverNew.solve(string, ansValues: {...})`.
- ANS references use literal tokens like `ans0`, `ans1` — `HomePage._cascadeUpdates` (in `main.dart`) demonstrates how newer cells re-evaluate when earlier answers change.
- Implicit multiplication and normalization rules live in the serializer (`_addImplicitMultiplication`) — follow its logic when adding new literal or operator nodes.
- Display formatting (padded operators, custom multiply sign) lives in `MathTextStyle` in `renderer.dart` — use `MathTextStyle.setMultiplySign(...)` to change UI representation.

3. Developer workflows (commands)
- Install deps and run: `flutter pub get` then `flutter run -d <device>`.
- Run unit tests: `flutter test` (all tests) or `flutter test test/math_engine_test.dart` (single file).
- Integration tests: see `test/integration_test.dart` and use Flutter's integration tooling when needed.
- Build artifacts: Android APK CI is configured in `.github/workflows/build_apk.yml` — local builds use `flutter build apk` (Android) or `flutter build windows` (Windows).

4. Project-specific patterns and gotchas
- Many editor operations mutate the `List<MathNode>` directly and notify via `MathEditorController` — prefer using controller helper methods (e.g., `setExpression`, `onCalculate`, `updateAnswer`) rather than raw list edits.
- The renderer computes layout and cursor offsets using `RenderParagraph` and a custom `TextScaler` — tests and widgets that measure text should reuse `MathTextStyle` helpers.
- `MathExpressionSerializer` normalizes unicode operators to ASCII for the solver; be careful when introducing new Unicode symbols.
- `MathSolverNew` expects plain-text solver format (strings from the serializer). It also supports multi-line systems (separated by `\n`) and `=`-based equations. If adding new node types, ensure the serializer maps them into solver-friendly syntax.

5. Important files to inspect when changing behavior
- UI / app lifecycle: [lib/main.dart](../lib/main.dart)
- Editor core & node types: [lib/renderer.dart](../lib/renderer.dart)
- Serialization & persistence format: [lib/math_expression_serializer.dart](../lib/math_expression_serializer.dart)
- Solver/evaluator: [lib/math_engine.dart](../lib/math_engine.dart)
- Persistence helpers: [lib/cell_persistence_service.dart](../lib/cell_persistence_service.dart)
- Keypad and input handling: [lib/keypad.dart](../lib/keypad.dart)
- Walkthrough/UX hints: [lib/walkthrough](../lib/walkthrough)

6. Tests and examples
- Unit tests live in `test/` (e.g., `math_engine_test.dart`, `math_expression_serializer_test.dart`) — use them as examples for expected input/output for serialization and solver.

7. If you need to change evaluation or persistence
- Update `MathExpressionSerializer` first (serialization contract). Then adapt `MathSolverNew` to accept the new textual forms. Update JSON schema (serializeToJson/_nodeToJson) to preserve backwards compatibility if possible.

If anything above is unclear or you want a different focus (CI, adding new node types, or improving precision handling), tell me which area to expand.  
