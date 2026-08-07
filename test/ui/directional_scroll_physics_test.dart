import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/keypad/keypad.dart';

void main() {
  group('DirectionalScrollPhysics', () {
    test('should allow both directions by default', () {
      const physics = DirectionalScrollPhysics();

      expect(physics.allowLeftSwipe, true);
      expect(physics.allowRightSwipe, true);
    });

    test('should apply to ancestor correctly', () {
      const physics = DirectionalScrollPhysics(
        allowLeftSwipe: true,
        allowRightSwipe: false,
      );

      final applied = physics.applyTo(const BouncingScrollPhysics());

      expect(applied.allowLeftSwipe, true);
      expect(applied.allowRightSwipe, false);
      expect(applied.parent, isA<BouncingScrollPhysics>());
    });

    group('applyBoundaryConditions', () {
      test('should allow left swipe when allowLeftSwipe is true', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: true,
          allowRightSwipe: true,
        );

        // Simulating scrolling left (value > pixels)
        final position = FixedScrollMetrics(
          pixels: 100,
          minScrollExtent: 0,
          maxScrollExtent: 300,
          viewportDimension: 100,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 1.0,
        );

        // When value > position.pixels, it's a left swipe
        final result = physics.applyBoundaryConditions(position, 150);

        // Should return 0 or delegate to parent (allowing the scroll)
        expect(result, 0);
      });

      test('should block left swipe when allowLeftSwipe is false', () {
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

        // When value > position.pixels, it's a left swipe
        final result = physics.applyBoundaryConditions(position, 150);

        // Should return the difference (blocking the scroll)
        expect(result, 50);
      });

      test('should allow right swipe when allowRightSwipe is true', () {
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

        // When value < position.pixels, it's a right swipe
        final result = physics.applyBoundaryConditions(position, 50);

        expect(result, 0);
      });

      test('should block right swipe when allowRightSwipe is false', () {
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

        // When value < position.pixels, it's a right swipe
        final result = physics.applyBoundaryConditions(position, 50);

        // Should return the difference (blocking the scroll)
        expect(result, -50);
      });

      test('should block both directions when both are false', () {
        const physics = DirectionalScrollPhysics(
          allowLeftSwipe: false,
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

        final leftResult = physics.applyBoundaryConditions(position, 150);
        final rightResult = physics.applyBoundaryConditions(position, 50);

        expect(leftResult, 50);
        expect(rightResult, -50);
      });
    });
  });
}
