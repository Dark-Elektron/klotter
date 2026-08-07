import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';
import 'package:klotter/walkthrough/walkthrough_overlay.dart';

void main() {
  group('WalkthroughOverlay', () {
    late WalkthroughService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = WalkthroughService();
    });

    tearDown(() {
      service.dispose();
    });

    Widget buildTestWidget({
      Map<String, GlobalKey>? targetKeys,
      Widget? child,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: WalkthroughOverlay(
            walkthroughService: service,
            targetKeys: targetKeys ?? {},
            child: child ?? const Center(child: Text('Test Child')),
          ),
        ),
      );
    }

    testWidgets('should render child widget', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Text('Child Content')),
      );

      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('should not show overlay when inactive', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('should show overlay when active', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('should show step title and description', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final step = service.currentStepData;
      expect(find.text(step.title), findsOneWidget);
      expect(find.text(step.description), findsOneWidget);
    });

    testWidgets('should show progress indicator', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('1/${service.steps.length}'), findsOneWidget);
    });

    testWidgets('should show Next button on non-action steps', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('should advance step when Next is tapped', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final initialStep = service.currentStep;

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(service.currentStep, initialStep + 1);
    });

    testWidgets('should show Back button after first step', (tester) async {
      await service.initialize();
      service.nextStep();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('should not show Back button on first step', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsNothing);
    });

    testWidgets('should go back when Back is tapped', (tester) async {
      await service.initialize();
      service.nextStep();
      service.nextStep();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final stepBeforeBack = service.currentStep;

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(service.currentStep, stepBeforeBack - 1);
    });

    testWidgets('should skip walkthrough when Skip is tapped', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(service.isActive, false);
    });

    testWidgets('should show Get Started on last step', (tester) async {
      await service.initialize();

      // Navigate to last step
      while (service.currentStep < service.steps.length - 1) {
        service.nextStep();
      }

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Get Started!'), findsOneWidget);
    });

    testWidgets('should show hint about settings', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Settings'), findsWidgets);
    });

    testWidgets('should update progress when step changes', (tester) async {
      await service.initialize();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('1/${service.steps.length}'), findsOneWidget);

      service.nextStep();
      await tester.pumpAndSettle();

      expect(find.text('2/${service.steps.length}'), findsOneWidget);
    });

    group('Swipe Steps', () {
      testWidgets('should show swipe instruction on swipe steps', (
        tester,
      ) async {
        await service.initialize();

        // Navigate to first swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        await tester.pumpWidget(buildTestWidget());
        // Use pump() instead of pumpAndSettle() - animation runs forever
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final action = service.currentStepData.requiredAction;
        if (action == WalkthroughAction.swipeLeft) {
          expect(find.text('Swipe LEFT'), findsOneWidget);
        } else if (action == WalkthroughAction.swipeRight) {
          expect(find.text('Swipe RIGHT'), findsOneWidget);
        }
      });

      testWidgets('should not show Next button on swipe steps', (tester) async {
        await service.initialize();

        // Navigate to first swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        await tester.pumpWidget(buildTestWidget());
        // Use pump() instead of pumpAndSettle() - animation runs forever
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Next'), findsNothing);
      });

      testWidgets('should show Back button on swipe steps', (tester) async {
        await service.initialize();

        // Navigate to first swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        await tester.pumpWidget(buildTestWidget());
        // Use pump() instead of pumpAndSettle() - animation runs forever
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Back button should be present
        expect(find.text('Back'), findsOneWidget);
      });

      testWidgets('should go back from swipe step when Back is tapped', (
        tester,
      ) async {
        await service.initialize();

        // Navigate to first swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        final stepBeforeBack = service.currentStep;

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(service.currentStep, stepBeforeBack - 1);
      });

      testWidgets('should skip from swipe step', (tester) async {
        await service.initialize();

        // Navigate to first swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Skip'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(service.isActive, false);
      });
    });

    group('Target Highlighting', () {
      testWidgets('should highlight target when key is provided', (
        tester,
      ) async {
        final targetKey = GlobalKey();

        await service.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WalkthroughOverlay(
                walkthroughService: service,
                targetKeys: {'expression_area': targetKey},
                child: Container(
                  key: targetKey,
                  width: 100,
                  height: 50,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Overlay should be rendered
        expect(find.text('Skip'), findsOneWidget);
      });
    });

    group('Device Mode', () {
      testWidgets('should filter steps for mobile mode', (tester) async {
        service.setDeviceMode(isTablet: false);
        await service.initialize();

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(service.isTabletMode, false);
        expect(find.text('1/${service.steps.length}'), findsOneWidget);
      });

      testWidgets('should filter steps for tablet mode', (tester) async {
        service.setDeviceMode(isTablet: true);
        await service.initialize();

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(service.isTabletMode, true);
        expect(find.text('1/${service.steps.length}'), findsOneWidget);
      });

      testWidgets('tablet mode should have fewer steps', (tester) async {
        service.setDeviceMode(isTablet: false);
        await service.initialize();
        final mobileSteps = service.steps.length;

        // Create new service for tablet
        final tabletService = WalkthroughService();
        tabletService.setDeviceMode(isTablet: true);
        await tabletService.initialize();
        final tabletSteps = tabletService.steps.length;

        expect(tabletSteps, lessThan(mobileSteps));

        tabletService.dispose();
      });
    });

    group('Walkthrough Completion', () {
      testWidgets('should complete when Get Started is tapped', (tester) async {
        await service.initialize();

        // Navigate to last step
        while (service.currentStep < service.steps.length - 1) {
          service.nextStep();
        }

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Get Started!'));
        await tester.pumpAndSettle();

        expect(service.isActive, false);
      });

      testWidgets('should hide overlay after completion', (tester) async {
        await service.initialize();
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Skip'), findsOneWidget);

        service.skipWalkthrough();
        await tester.pumpAndSettle();

        expect(find.text('Skip'), findsNothing);
      });
    });
  });
}
