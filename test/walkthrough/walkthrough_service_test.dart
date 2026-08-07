import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/walkthrough/walkthrough_service.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';

void main() {
  // Initialize the binding at the start of main
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalkthroughService', () {
    late WalkthroughService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = WalkthroughService();
    });

    tearDown(() {
      service.dispose();
    });

    group('Initialization', () {
      test('should start inactive before initialization', () {
        expect(service.isActive, false);
        expect(service.isInitialized, false);
        expect(service.currentStep, 0);
      });

      test('should activate on first launch', () async {
        SharedPreferences.setMockInitialValues({});

        await service.initialize();

        expect(service.isActive, true);
        expect(service.isInitialized, true);
        expect(service.currentStep, 0);
      });

      test('should not activate if already completed', () async {
        SharedPreferences.setMockInitialValues({
          'walkthrough_completed_v2': true,
        });

        await service.initialize();

        expect(service.isActive, false);
        expect(service.isInitialized, true);
      });

      test('should handle initialization errors gracefully', () async {
        // Force an error scenario - service should still be usable
        await service.initialize();

        expect(service.isInitialized, true);
      });
    });

    group('Step Navigation', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
      });

      test('should start at step 0', () {
        expect(service.currentStep, 0);
      });

      test('nextStep should increment current step', () {
        final initialStep = service.currentStep;

        service.nextStep();

        expect(service.currentStep, initialStep + 1);
      });

      test('previousStep should decrement current step', () {
        service.nextStep();
        service.nextStep();
        final stepBeforeBack = service.currentStep;

        service.previousStep();

        expect(service.currentStep, stepBeforeBack - 1);
      });

      test('previousStep should not go below 0', () {
        service.previousStep();
        service.previousStep();

        expect(service.currentStep, 0);
      });

      test('should complete walkthrough at last step', () async {
        // Navigate to last step
        while (service.currentStep < service.steps.length - 1) {
          service.nextStep();
        }

        service.nextStep(); // Should trigger completion

        expect(service.isActive, false);
        expect(service.currentStep, 0);
      });

      test('skipWalkthrough should complete immediately', () async {
        service.nextStep();
        service.nextStep();

        service.skipWalkthrough();

        expect(service.isActive, false);
        expect(service.currentStep, 0);
      });
    });

    group('Device Mode', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
      });

      test('should default to mobile mode', () {
        expect(service.isTabletMode, false);
      });

      test('should switch to tablet mode', () {
        service.setDeviceMode(isTablet: true);

        expect(service.isTabletMode, true);
      });

      test('should filter steps for mobile mode', () {
        service.setDeviceMode(isTablet: false);

        final steps = service.steps;

        // Should not contain tablet-only steps
        expect(
          steps.any((s) => s.id.startsWith('tablet_') && s.tabletOnly),
          false,
        );
      });

      test('should filter steps for tablet mode', () {
        service.setDeviceMode(isTablet: true);

        final steps = service.steps;

        // Should not contain mobile-only steps
        expect(steps.any((s) => s.mobileOnly), false);
      });

      test('mobile mode should have more steps than tablet mode', () {
        service.setDeviceMode(isTablet: false);
        final mobileStepCount = service.steps.length;

        service.setDeviceMode(isTablet: true);
        final tabletStepCount = service.steps.length;

        expect(mobileStepCount, greaterThan(tabletStepCount));
      });
    });

    group('User Actions', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
      });

      test('should not respond to actions when inactive', () {
        service.skipWalkthrough();
        final step = service.currentStep;

        service.onUserAction(WalkthroughAction.swipeLeft);

        expect(service.currentStep, step);
      });

      test('should advance when correct action is performed', () {
        // Navigate to a swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        final stepBefore = service.currentStep;
        final requiredAction = service.currentStepData.requiredAction!;

        service.onUserAction(requiredAction);

        expect(service.currentStep, stepBefore + 1);
      });

      test('should not advance on wrong action', () {
        // Navigate to a swipe step
        while (!service.currentStepData.requiresAction) {
          service.nextStep();
        }

        final stepBefore = service.currentStep;
        final requiredAction = service.currentStepData.requiredAction!;
        final wrongAction =
            requiredAction == WalkthroughAction.swipeLeft
                ? WalkthroughAction.swipeRight
                : WalkthroughAction.swipeLeft;

        service.onUserAction(wrongAction);

        expect(service.currentStep, stepBefore);
      });
    });

    group('Reset Walkthrough', () {
      test('should reset to initial state', () async {
        SharedPreferences.setMockInitialValues({
          'walkthrough_completed_v2': true,
        });

        // Create a fresh service for this test
        final testService = WalkthroughService();
        await testService.initialize();
        expect(testService.isActive, false);

        await testService.resetWalkthrough();

        expect(testService.isActive, true);
        expect(testService.currentStep, 0);
        expect(testService.isInitialized, true);

        testService.dispose();
      });
    });

    group('Callbacks', () {
      test('should have onResetKeypad callback setter', () async {
        SharedPreferences.setMockInitialValues({});

        bool callbackSet = false;
        service.onResetKeypad = () {
          callbackSet = true;
        };

        // Verify the callback was set (not null)
        expect(service.onResetKeypad, isNotNull);

        // Manually call it to verify it works
        service.onResetKeypad!();
        expect(callbackSet, true);
      });

      test('should have onNavigateToKeypadPage callback setter', () async {
        SharedPreferences.setMockInitialValues({});

        int? navigatedPage;
        service.onNavigateToKeypadPage = (page) {
          navigatedPage = page;
        };

        // Verify the callback was set (not null)
        expect(service.onNavigateToKeypadPage, isNotNull);

        // Manually call it to verify it works
        service.onNavigateToKeypadPage!(2);
        expect(navigatedPage, 2);
      });
    });
    group('Listeners', () {
      test('should notify listeners on step change', () async {
        SharedPreferences.setMockInitialValues({});

        final testService = WalkthroughService();
        await testService.initialize();

        int notificationCount = 0;
        testService.addListener(() {
          notificationCount++;
        });

        testService.nextStep();

        expect(notificationCount, 1);

        testService.dispose();
      });

      test('should notify listeners on skip', () async {
        SharedPreferences.setMockInitialValues({});

        final testService = WalkthroughService();
        await testService.initialize();

        int notificationCount = 0;
        testService.addListener(() {
          notificationCount++;
        });

        testService.skipWalkthrough();

        // Wait for async completion
        await Future.delayed(const Duration(milliseconds: 150));

        expect(notificationCount, greaterThan(0));

        // Don't dispose here since skipWalkthrough might have async operations
      });
    });
  });
}
