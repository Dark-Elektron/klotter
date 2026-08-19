enum TooltipPosition { above, below, center }

enum WalkthroughAction { swipeLeft, swipeRight, tap }

class WalkthroughStep {
  final String id;
  final String title;
  final String description;
  final TooltipPosition position;
  final bool requiresAction;
  final WalkthroughAction? requiredAction;
  final bool mobileOnly;
  final bool tabletOnly;

  const WalkthroughStep({
    required this.id,
    required this.title,
    required this.description,
    required this.position,
    this.requiresAction = false,
    this.requiredAction,
    this.mobileOnly = false,
    this.tabletOnly = false,
  });
}

const List<WalkthroughStep> walkthroughSteps = [
  // ============ COMMON STEPS (BOTH MOBILE & TABLET) ============
  WalkthroughStep(
    id: 'expression_area',
    title: 'Expression Display',
    description:
        'Your mathematical expressions appear here with proper formatting - fractions, roots, exponents and more!',
    position: TooltipPosition.below,
  ),
  WalkthroughStep(
    id: 'plot_area',
    title: 'Live Graph',
    description:
        'Any expression using x, y or z is graphed here as you type. Drag to pan, pinch to zoom, and switch between 2D and 3D on the right. Long-press the plot to read a point off it.',
    position: TooltipPosition.below,
  ),
  WalkthroughStep(
    id: 'plot_pages',
    title: 'Your Plots',
    description:
        'Each plot has its own page. Swipe this strip to move between them, or past the last one to start a new plot.',
    position: TooltipPosition.above,
  ),
  WalkthroughStep(
    id: 'command_button',
    title: 'Command Button',
    description:
        'Tap ⌘ to add another line to this plot. Every line is drawn as its own curve in its own colour, so you can compare several at once.',
    position: TooltipPosition.above,
  ),

  // ============ MOBILE ONLY STEPS ============
  WalkthroughStep(
    id: 'number_keypad',
    title: 'Number Pad',
    description:
        'Digits and operators stay here permanently — swiping the rows above never takes them away.',
    position: TooltipPosition.above,
    mobileOnly: true,
  ),
  WalkthroughStep(
    id: 'scientific_keypad',
    title: 'Scientific Functions',
    description:
        'Trigonometry, logarithms, roots and exponents, alongside the variables and unit vectors you build expressions from. Long-press a variable to work in polar or spherical coordinates instead — the plot converts for you.',
    position: TooltipPosition.above,
    mobileOnly: true,
  ),
  WalkthroughStep(
    id: 'swipe_left_extras',
    title: 'More Functions',
    description: 'Swipe the top rows LEFT for additional functions.',
    position: TooltipPosition.above,
    requiresAction: true,
    requiredAction: WalkthroughAction.swipeLeft,
    mobileOnly: true,
  ),
  WalkthroughStep(
    id: 'extras_keypad',
    title: 'Extra Functions',
    description:
        'Permutations, combinations, factorial, undo/redo, export and settings are here. ⇪ saves the plot you are looking at as an image or PDF.',
    position: TooltipPosition.above,
    mobileOnly: true,
  ),
  // NEW: Settings button step for mobile
  WalkthroughStep(
    id: 'settings_button',
    title: 'Settings',
    description:
        'Tap the gear icon \u2630 anytime to access settings. You can always restart this tutorial from there!',
    position: TooltipPosition.above,
    mobileOnly: true,
  ),
  WalkthroughStep(
    id: 'swipe_right_back',
    title: 'Navigate Back',
    description: 'Swipe the top rows RIGHT to return to the scientific keys.',
    position: TooltipPosition.above,
    requiresAction: true,
    requiredAction: WalkthroughAction.swipeRight,
    mobileOnly: true,
  ),

  // ============ TABLET ONLY STEPS ============
  // A tablet has no swipe between keypads — every block is on screen at
  // once — so the tour points at each block in turn rather than asking for
  // a gesture that does nothing here. The phone steps above still teach the
  // swipes, and they are mobileOnly, so no tour shows both.
  WalkthroughStep(
    id: 'tablet_keypads_visible',
    title: 'Every Key at Once',
    description:
        'Your screen is wide enough for the whole keypad, so there is nothing to swipe between. Here is what each block holds.',
    position: TooltipPosition.above,
    tabletOnly: true,
  ),
  WalkthroughStep(
    id: 'tablet_number_block',
    title: 'Number Block',
    description:
        'The digits, the basic operators, and the command key that evaluates what you have typed.',
    position: TooltipPosition.above,
    tabletOnly: true,
  ),
  WalkthroughStep(
    id: 'tablet_scientific_block',
    title: 'Scientific Block',
    description:
        'Trigonometry, logarithms, powers and roots. Long-press a key to reach its second function.',
    position: TooltipPosition.above,
    tabletOnly: true,
  ),
  WalkthroughStep(
    id: 'tablet_extras_block',
    title: 'Extras Block',
    description:
        'Permutations and combinations, integrals and sums, undo/redo, and ⇪ to save the current plot as an image or PDF.',
    position: TooltipPosition.above,
    tabletOnly: true,
  ),
  WalkthroughStep(
    id: 'tablet_settings_button',
    title: 'Settings',
    description:
        'Tap the gear icon \u2630 anytime to access settings. You can always restart this tutorial from there!',
    position: TooltipPosition.above,
    tabletOnly: true,
  ),

  // ============ COMMON FINAL STEP ============
  WalkthroughStep(
    id: 'complete',
    title: 'You\'re All Set!',
    description:
        'That is the tour. Type an expression using x, y or z and watch it plot as you go.',
    position: TooltipPosition.center,
  ),
];
