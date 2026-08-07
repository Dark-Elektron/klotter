import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/walkthrough/walkthrough_steps.dart';

void main() {
  group('WalkthroughSteps', () {
    test('walkthroughSteps should not be empty', () {
      expect(walkthroughSteps, isNotEmpty);
    });

    test('all steps should have required fields', () {
      for (final step in walkthroughSteps) {
        expect(step.id, isNotEmpty, reason: 'Step should have an id');
        expect(
          step.title,
          isNotEmpty,
          reason: 'Step ${step.id} should have a title',
        );
        expect(
          step.description,
          isNotEmpty,
          reason: 'Step ${step.id} should have a description',
        );
      }
    });

    test('steps requiring action should have requiredAction', () {
      for (final step in walkthroughSteps) {
        if (step.requiresAction) {
          expect(
            step.requiredAction,
            isNotNull,
            reason: 'Step ${step.id} requires action but has no requiredAction',
          );
        }
      }
    });

    test('step ids should be unique', () {
      final ids = walkthroughSteps.map((s) => s.id).toList();
      final uniqueIds = ids.toSet();

      expect(ids.length, uniqueIds.length, reason: 'Step ids should be unique');
    });

    test('should have common steps (not mobile or tablet only)', () {
      final commonSteps = walkthroughSteps.where(
        (s) => !s.mobileOnly && !s.tabletOnly,
      );

      expect(commonSteps, isNotEmpty);
    });

    test('should have mobile-only steps', () {
      final mobileSteps = walkthroughSteps.where((s) => s.mobileOnly);

      expect(mobileSteps, isNotEmpty);
    });

    test('should have tablet-only steps', () {
      final tabletSteps = walkthroughSteps.where((s) => s.tabletOnly);

      expect(tabletSteps, isNotEmpty);
    });

    test('no step should be both mobile and tablet only', () {
      for (final step in walkthroughSteps) {
        expect(
          step.mobileOnly && step.tabletOnly,
          false,
          reason: 'Step ${step.id} cannot be both mobile and tablet only',
        );
      }
    });

    test('should start with expression_area step', () {
      expect(walkthroughSteps.first.id, 'expression_area');
    });

    test('should end with complete step', () {
      expect(walkthroughSteps.last.id, 'complete');
    });

    test('complete step should not require action', () {
      final completeStep = walkthroughSteps.last;

      expect(completeStep.requiresAction, false);
    });

    test('swipe steps should have correct actions', () {
      final swipeRightSteps = walkthroughSteps.where(
        (s) => s.id.contains('swipe_right'),
      );
      final swipeLeftSteps = walkthroughSteps.where(
        (s) => s.id.contains('swipe_left'),
      );

      for (final step in swipeRightSteps) {
        if (step.requiresAction) {
          expect(
            step.requiredAction,
            WalkthroughAction.swipeRight,
            reason: 'Step ${step.id} should require swipeRight',
          );
        }
      }

      for (final step in swipeLeftSteps) {
        if (step.requiresAction) {
          expect(
            step.requiredAction,
            WalkthroughAction.swipeLeft,
            reason: 'Step ${step.id} should require swipeLeft',
          );
        }
      }
    });

    group('Mobile steps flow', () {
      late List<WalkthroughStep> mobileSteps;

      setUp(() {
        mobileSteps = walkthroughSteps.where((s) => !s.tabletOnly).toList();
      });

      test('should have settings_button step', () {
        expect(mobileSteps.any((s) => s.id == 'settings_button'), true);
      });

      test('settings_button should come before swipe_right_back', () {
        final settingsIndex = mobileSteps.indexWhere(
          (s) => s.id == 'settings_button',
        );
        final swipeBackIndex = mobileSteps.indexWhere(
          (s) => s.id == 'swipe_right_back',
        );

        if (settingsIndex != -1 && swipeBackIndex != -1) {
          expect(settingsIndex, lessThan(swipeBackIndex));
        }
      });
    });

    group('Tablet steps flow', () {
      late List<WalkthroughStep> tabletSteps;

      setUp(() {
        tabletSteps = walkthroughSteps.where((s) => !s.mobileOnly).toList();
      });

      test('should have tablet_settings_button step', () {
        expect(tabletSteps.any((s) => s.id == 'tablet_settings_button'), true);
      });

      test('tablet flow has no more swipe steps than mobile', () {
      // The permanent number pad removed two mobile swipes, so the two flows
      // now carry the same number.
      final mobileSwipes = walkthroughSteps
          .where((s) => !s.tabletOnly && s.requiresAction)
          .length;
      final tabletSwipes = walkthroughSteps
          .where((s) => !s.mobileOnly && s.requiresAction)
          .length;
      expect(tabletSwipes, lessThanOrEqualTo(mobileSwipes));
    });
    });
  });

  group('WalkthroughStep', () {
    test('should create step with required fields', () {
      const step = WalkthroughStep(
        id: 'test_step',
        title: 'Test Title',
        description: 'Test Description',
        position: TooltipPosition.below,
      );

      expect(step.id, 'test_step');
      expect(step.title, 'Test Title');
      expect(step.description, 'Test Description');
      expect(step.position, TooltipPosition.below);
      expect(step.requiresAction, false);
      expect(step.requiredAction, null);
      expect(step.mobileOnly, false);
      expect(step.tabletOnly, false);
    });

    test('should create step with action required', () {
      const step = WalkthroughStep(
        id: 'action_step',
        title: 'Action Step',
        description: 'Requires action',
        position: TooltipPosition.above,
        requiresAction: true,
        requiredAction: WalkthroughAction.swipeLeft,
      );

      expect(step.requiresAction, true);
      expect(step.requiredAction, WalkthroughAction.swipeLeft);
    });

    test('should create mobile-only step', () {
      const step = WalkthroughStep(
        id: 'mobile_step',
        title: 'Mobile Step',
        description: 'Mobile only',
        position: TooltipPosition.above,
        mobileOnly: true,
      );

      expect(step.mobileOnly, true);
      expect(step.tabletOnly, false);
    });

    test('should create tablet-only step', () {
      const step = WalkthroughStep(
        id: 'tablet_step',
        title: 'Tablet Step',
        description: 'Tablet only',
        position: TooltipPosition.above,
        tabletOnly: true,
      );

      expect(step.mobileOnly, false);
      expect(step.tabletOnly, true);
    });
  });

  group('TooltipPosition', () {
    test('should have all expected values', () {
      expect(TooltipPosition.values, contains(TooltipPosition.above));
      expect(TooltipPosition.values, contains(TooltipPosition.below));
      expect(TooltipPosition.values, contains(TooltipPosition.center));
    });
  });

  group('WalkthroughAction', () {
    test('should have all expected values', () {
      expect(WalkthroughAction.values, contains(WalkthroughAction.swipeLeft));
      expect(WalkthroughAction.values, contains(WalkthroughAction.swipeRight));
      expect(WalkthroughAction.values, contains(WalkthroughAction.tap));
    });
  });
}
