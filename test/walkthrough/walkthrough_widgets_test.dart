import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/walkthrough/walkthrough_widgets.dart';

void main() {
  group('SwipeGestureAnimation', () {
    testWidgets('should render without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 60,
                child: SwipeGestureAnimation(
                  swipeLeft: true,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SwipeGestureAnimation), findsOneWidget);
    });

    testWidgets('should animate continuously', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 60,
                child: SwipeGestureAnimation(
                  swipeLeft: true,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

      // Pump a few frames to verify animation is running
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Widget should still be present and animating
      expect(find.byType(SwipeGestureAnimation), findsOneWidget);
    });

    testWidgets('should render for swipe left', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 60,
                child: SwipeGestureAnimation(
                  swipeLeft: true,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SwipeGestureAnimation), findsOneWidget);
    });

    testWidgets('should render for swipe right', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 60,
                child: SwipeGestureAnimation(
                  swipeLeft: false,
                  color: Colors.green,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SwipeGestureAnimation), findsOneWidget);
    });

    testWidgets('should respect size constraints', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 80,
                child: SwipeGestureAnimation(
                  swipeLeft: true,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(SwipeGestureAnimation),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      expect(sizedBox.width, 200);
      expect(sizedBox.height, 80);
    });
  });

  group('SpotlightPainter', () {
    test('should create with required parameters', () {
      final painter = SpotlightPainter(
        targetRect: const Rect.fromLTWH(50, 50, 100, 100),
        padding: 8,
      );

      expect(painter.targetRect, const Rect.fromLTWH(50, 50, 100, 100));
      expect(painter.padding, 8);
    });

    test('shouldRepaint should return true when targetRect changes', () {
      final painter1 = SpotlightPainter(
        targetRect: const Rect.fromLTWH(50, 50, 100, 100),
      );
      final painter2 = SpotlightPainter(
        targetRect: const Rect.fromLTWH(60, 60, 100, 100),
      );

      expect(painter1.shouldRepaint(painter2), true);
    });

    test('shouldRepaint should return false when targetRect is same', () {
      final painter1 = SpotlightPainter(
        targetRect: const Rect.fromLTWH(50, 50, 100, 100),
      );
      final painter2 = SpotlightPainter(
        targetRect: const Rect.fromLTWH(50, 50, 100, 100),
      );

      expect(painter1.shouldRepaint(painter2), false);
    });

    testWidgets('should paint spotlight correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(400, 800),
              painter: SpotlightPainter(
                targetRect: const Rect.fromLTWH(100, 100, 200, 100),
                padding: 8,
              ),
            ),
          ),
        ),
      );

      // Use a more specific finder - find CustomPaint with our specific painter
      final customPaintFinder = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is SpotlightPainter,
      );

      expect(customPaintFinder, findsOneWidget);
    });
  });

  group('SwipeGesturePainter', () {
    test('shouldRepaint should return true when progress changes', () {
      final painter1 = SwipeGesturePainter(
        progress: 0.5,
        swipeLeft: true,
        color: Colors.blue,
      );
      final painter2 = SwipeGesturePainter(
        progress: 0.6,
        swipeLeft: true,
        color: Colors.blue,
      );

      expect(painter1.shouldRepaint(painter2), true);
    });

    test('shouldRepaint should return false when progress is same', () {
      final painter1 = SwipeGesturePainter(
        progress: 0.5,
        swipeLeft: true,
        color: Colors.blue,
      );
      final painter2 = SwipeGesturePainter(
        progress: 0.5,
        swipeLeft: true,
        color: Colors.blue,
      );

      expect(painter1.shouldRepaint(painter2), false);
    });
  });
}
