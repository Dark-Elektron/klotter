import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'walkthrough_steps.dart';

class WalkthroughService extends ChangeNotifier {
  static const String _completedKey = 'walkthrough_completed_v2';

  bool _isActive = false;
  int _currentStep = 0;
  bool _isInitialized = false;
  bool _isTabletMode = false;

  VoidCallback? onResetKeypad;
  void Function(int page)? onNavigateToKeypadPage;  // NEW

  bool get isActive => _isActive;
  int get currentStep => _currentStep;
  bool get isInitialized => _isInitialized;
  bool get isTabletMode => _isTabletMode;

  // Expected keypad page when ENTERING each swipe step (for mobile, pagesPerView=1)
  // This is the page the user should be on BEFORE performing the swipe
  // Phone pages are scientific (0) and extras (1). The number pad sits below
  // them permanently and is not part of the PageView.
  static const Map<String, int> _mobileSwipeStepPages = {
    'swipe_left_extras': 0, // On scientific (0), swipe left to extras (1)
    'swipe_right_back': 1, // On extras (1), swipe right to scientific (0)
  };

  // Expected keypad page when ENTERING each swipe step (for tablet, pagesPerView=2)
  static const Map<String, int> _tabletSwipeStepPages = {
    'tablet_swipe_left_extras': 0, // On page 0, will swipe to page 1
    'tablet_swipe_right_back': 1,  // On page 1, will swipe to page 0
  };

  List<WalkthroughStep> get steps {
    return walkthroughSteps.where((step) {
      if (_isTabletMode) {
        return !step.mobileOnly;
      } else {
        return !step.tabletOnly;
      }
    }).toList();
  }

  void setDeviceMode({required bool isTablet}) {
    if (_isTabletMode != isTablet) {
      _isTabletMode = isTablet;
      // debugPrint('Walkthrough device mode changed: isTablet=$isTablet');

      if (_isActive) {
        if (_currentStep >= steps.length) {
          _currentStep = steps.length - 1;
        }
        notifyListeners();
      }
    }
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_completedKey);

      // debugPrint(
      //     'Walkthrough initialize - completed: $completed, isTablet: $_isTabletMode, steps: ${steps.length}');

      if (completed == null || completed == false) {
        _isActive = true;
        _currentStep = 0;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          onResetKeypad?.call();
        });

        // debugPrint('Walkthrough will be shown');
      } else {
        _isActive = false;
        // debugPrint('Walkthrough already completed');
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      // debugPrint('Walkthrough initialization error: $e');
      _isActive = true;
      _currentStep = 0;
      _isInitialized = true;
      notifyListeners();
    }
  }

  void startWalkthrough() {
    _isActive = true;
    _currentStep = 0;
    _isInitialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      onResetKeypad?.call();
    });

    notifyListeners();
    // debugPrint(
    //     'Walkthrough started manually (tablet: $_isTabletMode, steps: ${steps.length})');
  }

  void nextStep() {
    if (_currentStep < steps.length - 1) {
      _currentStep++;
      // debugPrint(
      //     'Walkthrough step: $_currentStep/${steps.length} - ${steps[_currentStep].id}');
      notifyListeners();
    } else {
      completeWalkthrough();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      final step = currentStepData;

      // If going back to a swipe step, navigate keypad to expected position
      if (step.requiresAction &&
          (step.requiredAction == WalkthroughAction.swipeLeft ||
              step.requiredAction == WalkthroughAction.swipeRight)) {
        
        final expectedPage = _isTabletMode
            ? _tabletSwipeStepPages[step.id]
            : _mobileSwipeStepPages[step.id];

        if (expectedPage != null && onNavigateToKeypadPage != null) {
          // debugPrint('Navigating keypad to page $expectedPage for step ${step.id}');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onNavigateToKeypadPage!(expectedPage);
          });
        }
      }

      // debugPrint(
      //     'Walkthrough step: $_currentStep/${steps.length} - ${step.id}');
      notifyListeners();
    }
  }

  void skipWalkthrough() {
    // debugPrint('Walkthrough skipped');
    completeWalkthrough();
  }

  Future<void> completeWalkthrough() async {
    _isActive = false;
    _currentStep = 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_completedKey, true);
      // debugPrint('Walkthrough completed and saved');
    } catch (e) {
      debugPrint('Error saving walkthrough completion: $e');
    }

    notifyListeners();
  }

  Future<void> resetWalkthrough() async {
    // debugPrint('Resetting walkthrough...');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_completedKey, false);
    } catch (e) {
      debugPrint('Error resetting walkthrough: $e');
    }

    _currentStep = 0;
    _isActive = true;
    _isInitialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      onResetKeypad?.call();
    });

    notifyListeners();
    // debugPrint(
    //     'Walkthrough reset complete (tablet: $_isTabletMode, steps: ${steps.length})');
  }

  Future<void> forceClear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_completedKey);
      // debugPrint('Walkthrough data force cleared');
    } catch (e) {
      debugPrint('Error clearing walkthrough: $e');
    }
  }

  WalkthroughStep get currentStepData {
    // `steps` length depends on device mode, which can change (e.g. rotation)
    // before `_currentStep` is re-clamped. Clamp defensively so switching to a
    // shorter step list never throws a RangeError.
    final list = steps;
    final index = _currentStep.clamp(0, list.length - 1);
    return list[index];
  }

  void onUserAction(WalkthroughAction action) {
    if (!_isActive) return;

    final step = currentStepData;
    // debugPrint(
    //     'Walkthrough: User action=$action, Step=${step.id}, Requires=${step.requiredAction}');

    if (step.requiresAction && step.requiredAction == action) {
      // debugPrint('Walkthrough: Action matched! Moving to next step.');
      nextStep();
    }
  }
}