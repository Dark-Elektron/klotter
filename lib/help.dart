import 'package:flutter/material.dart';
import 'utils/app_colors.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.displayBackground,
      appBar: AppBar(
        title: Text(
          'Help & Instructions',
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.displayBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        children: [
          // Logo Section
          Center(
            child: Image.asset(
              'assets/icons/app_icon.png',
              height: 80,
              errorBuilder:
                  (context, error, stackTrace) =>
                      Icon(Icons.calculate, size: 80, color: colors.accent),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Welcome to Klotter',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A scientific calculator that graphs what you type.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: colors.textSecondary),
          ),
          Divider(height: 40, color: colors.divider),

          _buildHelpStep(
            context,
            icon: Icons.iso,
            title: 'Structural Math',
            description:
                'Insert fractions with "/" and exponents with "x\u207F". Tap any part of the expression to move your cursor.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.restore,
            title: 'Undo & Redo',
            description:
                'Easily fix mistakes using the history buttons: Tap ⎌ to Undo your last change, or ⎏ to Redo an action you moved back from.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.show_chart,
            title: 'Live Plotting',
            description:
                'Every cell graphs as you type. Use x for a curve, or x and y together for a 3D surface. Constants draw as a horizontal line, and unit vectors (x̂, ŷ, ẑ) make a vector field.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.touch_app,
            title: 'Read A Point',
            description:
                'Long-press a plot to put a marker on it. In 2D it reports every curve at that x, solving equations like x²+y²=1 for their y values; in 3D it marks the point on the surface you touched and gives its x, y and z. Tap to clear it.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.threed_rotation,
            title: '2D And 3D',
            description:
                'Switch dimension with the buttons on the right of the plot. Drag to rotate a 3D view, flick to leave it spinning, and tap to stop. Pinch to zoom — in 2D, pinching up and down scales y, sideways scales x.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.keyboard_command_key,
            title: 'Multiple Curves',
            description:
                'Press ⌘ to add another expression to the same plot; each line is drawn as its own curve in its own colour. Swipe the strip above the keypad to move between plots, or to start a new one.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.ios_share,
            title: 'Export A Plot',
            description:
                'Press ⇪ on the extras keypad to save the plot you are looking at as a PNG, JPEG or PDF, then share it wherever you like.',
            colors: colors,
          ),
          _buildHelpStep(
            context,
            icon: Icons.settings,
            title: 'Customization',
            description:
                'Tap the gear icon to adjust decimal precision, themes, and haptic feedback.',
            colors: colors,
          ),

          const SizedBox(height: 32),

          Text(
            'Documentation & Feedback',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'For technical details and updates, visit our GitHub page:',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          SelectableText(
            'https://github.com/Dark-Elektron/klotter',
            style: TextStyle(color: colors.accent, fontStyle: FontStyle.italic),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHelpStep(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required AppColors colors,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: colors.accent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
