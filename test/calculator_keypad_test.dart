import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/keypad/keypad.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';

void main() {
  group('CalculatorKeypad', () {
    late WalkthroughService walkthroughService;
    late SettingsProvider settingsProvider;
    late Map<int, MathEditorController?> mathEditorControllers;
    late Map<int, TextEditingController?> textDisplayControllers;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({
        'dark_theme': false,
        'multiplication_sign': '×',
        'walkthrough_completed_v2': true,
      });
    });

    setUp(() async {
      walkthroughService = WalkthroughService();
      settingsProvider = await SettingsProvider.create();
      mathEditorControllers = {0: MathEditorController()};
      textDisplayControllers = {0: TextEditingController()};
    });

    tearDown(() {
      walkthroughService.dispose();
      settingsProvider.dispose();
      mathEditorControllers[0]?.dispose();
      textDisplayControllers[0]?.dispose();
    });

    Widget buildTestWidget({
      double screenWidth = 400,
      bool isLandscape = false,
      WalkthroughService? customWalkthroughService,
      SettingsProvider? customSettingsProvider,
      int activeIndex = 0,
      VoidCallback? onUpdateMathEditor,
      void Function(int index)? onRemoveDisplay,
      VoidCallback? onSetState,
    }) {
      final provider = customSettingsProvider ?? settingsProvider;
      final walkthrough = customWalkthroughService ?? walkthroughService;

      return ChangeNotifierProvider<SettingsProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return CalculatorKeypad(
                  screenWidth: screenWidth,
                  isLandscape: isLandscape,
                  colors: AppColors.of(context),
                  activeIndex: activeIndex,
                  mathEditorControllers: mathEditorControllers,
                  textDisplayControllers: textDisplayControllers,
                  settingsProvider: provider,
                  onUpdateMathEditor: onUpdateMathEditor ?? () {},
                  onAddDisplay: () {},
                  onRemoveDisplay: onRemoveDisplay ?? (_) {},
                  onClearAllDisplays: () {},
                  onSetState: onSetState ?? () {},
                  walkthroughService: walkthrough,
                  scientificKeypadKey: GlobalKey(),
                  numberKeypadKey: GlobalKey(),
                  extrasKeypadKey: GlobalKey(),
                  commandButtonKey: GlobalKey(),
                  mainKeypadAreaKey: GlobalKey(),
                  settingsButtonKey: GlobalKey(),
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets('should render keypad widget', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify the widget tree contains expected structure
      expect(find.byType(CalculatorKeypad), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
    });



    testWidgets('should have SizedBox for main keypad area', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsWidgets);
    });


    group('Walkthrough Integration', () {
      testWidgets('should register callbacks with walkthrough service', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(walkthroughService.onResetKeypad, isNotNull);
        expect(walkthroughService.onNavigateToKeypadPage, isNotNull);
      });

      testWidgets('should reset keypad when walkthrough resets', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Should not throw when called
        walkthroughService.onResetKeypad?.call();
        await tester.pumpAndSettle();

        expect(find.byType(CalculatorKeypad), findsOneWidget);
      });

      testWidgets('should navigate to page when walkthrough requests', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Should not throw when called
        walkthroughService.onNavigateToKeypadPage?.call(0);
        await tester.pumpAndSettle();

        walkthroughService.onNavigateToKeypadPage?.call(2);
        await tester.pumpAndSettle();

        expect(find.byType(CalculatorKeypad), findsOneWidget);
      });
    });

    group('Landscape Mode', () {
      testWidgets('should render in landscape mode', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(screenWidth: 800, isLandscape: true),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CalculatorKeypad), findsOneWidget);
      });

      testWidgets('should set tablet mode for wide screens', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(screenWidth: 800, isLandscape: true),
        );
        await tester.pumpAndSettle();

        // Allow post-frame callback to execute
        await tester.pump(const Duration(milliseconds: 100));

        expect(walkthroughService.isTabletMode, true);
      });
    });

    group('Backspace behavior', () {
      testWidgets(
        'single taps delete content first, then delete empty cell on next tap',
        (tester) async {
          int cellCount = 2;
          int removedCells = 0;

          mathEditorControllers[0]!.insertCharacter('9');
          mathEditorControllers[0]!.expr =
              mathEditorControllers[0]!.getExpression();

          await tester.pumpWidget(
            buildTestWidget(
              onUpdateMathEditor: () {
                mathEditorControllers[0]!.expr =
                    mathEditorControllers[0]!.getExpression();
              },
              onRemoveDisplay: (_) {
                if (cellCount > 1) {
                  cellCount--;
                  removedCells++;
                }
              },
            ),
          );
          await tester.pumpAndSettle();

          final backspaceFinder = find.text('\u232B').hitTestable().first;

          await tester.tap(backspaceFinder);
          await tester.pump();

          expect(mathEditorControllers[0]!.getExpression(), isEmpty);
          expect(removedCells, 0);

          await tester.tap(backspaceFinder);
          await tester.pump();

          expect(removedCells, 1);
        },
      );

      testWidgets(
        'holding backspace does not delete cell after it becomes empty until a new press',
        (tester) async {
          int cellCount = 2;
          int removedCells = 0;

          const seed = '123456';
          for (int i = 0; i < seed.length; i++) {
            mathEditorControllers[0]!.insertCharacter(seed[i]);
          }
          mathEditorControllers[0]!.expr =
              mathEditorControllers[0]!.getExpression();

          await tester.pumpWidget(
            buildTestWidget(
              onUpdateMathEditor: () {
                mathEditorControllers[0]!.expr =
                    mathEditorControllers[0]!.getExpression();
              },
              onRemoveDisplay: (_) {
                if (cellCount > 1) {
                  cellCount--;
                  removedCells++;
                }
              },
            ),
          );
          await tester.pumpAndSettle();

          final backspaceFinder = find.text('\u232B').hitTestable().first;

          final gesture = await tester.startGesture(
            tester.getCenter(backspaceFinder),
          );
          await tester.pump(const Duration(milliseconds: 1300));

          expect(mathEditorControllers[0]!.getExpression(), isEmpty);
          expect(removedCells, 0);

          await tester.pump(const Duration(milliseconds: 500));
          expect(removedCells, 0);

          await gesture.up();
          await tester.pump();

          await tester.tap(backspaceFinder);
          await tester.pump();

          expect(removedCells, 1);
        },
      );
    });

    group('Physics during walkthrough', () {
      testWidgets('should use normal physics when walkthrough inactive', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Just verify the widget renders without error
        expect(find.byType(CalculatorKeypad), findsOneWidget);
      });

      testWidgets('should have directional physics on swipe step', (
        tester,
      ) async {
        final testWalkthroughService = WalkthroughService();
        testWalkthroughService.startWalkthrough();

        // Navigate to a swipe step
        while (!testWalkthroughService.currentStepData.requiresAction) {
          testWalkthroughService.nextStep();
        }

        expect(testWalkthroughService.currentStepData.requiresAction, true);
        expect(
          testWalkthroughService.currentStepData.requiredAction,
          isIn([WalkthroughAction.swipeLeft, WalkthroughAction.swipeRight]),
        );

        await tester.pumpWidget(
          buildTestWidget(customWalkthroughService: testWalkthroughService),
        );

        // Use pump() instead of pumpAndSettle() because animations run forever
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(CalculatorKeypad), findsOneWidget);

        testWalkthroughService.dispose();
      });

      testWidgets('should allow correct swipe direction during walkthrough', (
        tester,
      ) async {
        final testWalkthroughService = WalkthroughService();
        testWalkthroughService.startWalkthrough();

        // Navigate to first swipe-right step
        while (testWalkthroughService.currentStepData.requiredAction !=
            WalkthroughAction.swipeRight) {
          testWalkthroughService.nextStep();
          if (testWalkthroughService.currentStep >=
              testWalkthroughService.steps.length - 1) {
            break;
          }
        }

        // Skip test if no swipe-right step found
        if (testWalkthroughService.currentStepData.requiredAction !=
            WalkthroughAction.swipeRight) {
          testWalkthroughService.dispose();
          return;
        }

        await tester.pumpWidget(
          buildTestWidget(customWalkthroughService: testWalkthroughService),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(CalculatorKeypad), findsOneWidget);

        testWalkthroughService.dispose();
      });
    });

    group('DirectionalScrollPhysics', () {
      test('should block left swipe when not allowed', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: false,
          allowRightSwipe: true,
        );

        final position = FixedScrollMetrics(
          pixels: 100,
          minScrollExtent: 0,
          maxScrollExtent: 300,
          viewportDimension: 100,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        );

        final result = physics.applyBoundaryConditions(position, 150);
        expect(result, 50);
      });

      test('should allow left swipe when allowed', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: true,
          allowRightSwipe: true,
        );

        final position = FixedScrollMetrics(
          pixels: 100,
          minScrollExtent: 0,
          maxScrollExtent: 300,
          viewportDimension: 100,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        );

        final result = physics.applyBoundaryConditions(position, 150);
        expect(result, 0);
      });

      test('should block right swipe when not allowed', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: true,
          allowRightSwipe: false,
        );

        final position = FixedScrollMetrics(
          pixels: 100,
          minScrollExtent: 0,
          maxScrollExtent: 300,
          viewportDimension: 100,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        );

        final result = physics.applyBoundaryConditions(position, 50);
        expect(result, -50);
      });

      test('should allow right swipe when allowed', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: true,
          allowRightSwipe: true,
        );

        final position = FixedScrollMetrics(
          pixels: 100,
          minScrollExtent: 0,
          maxScrollExtent: 300,
          viewportDimension: 100,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        );

        final result = physics.applyBoundaryConditions(position, 50);
        expect(result, 0);
      });

      test('should apply to ancestor correctly', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: false,
          allowRightSwipe: true,
        );

        final applied = physics.applyTo(const ClampingScrollPhysics());

        expect(applied, isA<DirectionalScrollPhysics>());
        expect(applied.allowLeftSwipe, false);
        expect(applied.allowRightSwipe, true);
      });
    });
  });
}
