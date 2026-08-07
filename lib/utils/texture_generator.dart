// lib/utils/texture_generator.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

enum TextureType {
  smoothNoise,
  paperFiber,
  none,
}

class TextureGenerator {
  static const int textureWidth = 256;
  static const int textureHeight = 256;
  static const Size textureSize = Size(256, 256);

  static final Map<String, ui.Image?> _cache = {};
  static final Map<String, Completer<ui.Image?>> _pendingRequests = {};

  static String _getCacheKey(
    Color color,
    TextureType type, {
    double intensity = 0.15,
    double scale = 1.65,
  }) {
    return '${color.toARGB32()}_${type.name}_${intensity}_$scale';
  }

  static ui.Image? peekCachedTexture(
    Color baseColor, {
    TextureType type = TextureType.smoothNoise,
    double intensity = 0.15,
    double scale = 1.65,
  }) {
    return _cache[_getCacheKey(
      baseColor,
      type,
      intensity: intensity,
      scale: scale,
    )];
  }

  static Future<ui.Image?> getTexture(
    Color baseColor,
    Size size, {
    TextureType type = TextureType.smoothNoise,
    double intensity = 0.25,
    double scale = 1.65,
    double softness = 1.0,
  }) async {
    if (type == TextureType.none) {
      return null;
    }

    final cacheKey = _getCacheKey(
      baseColor,
      type,
      intensity: intensity,
      scale: scale,
    );

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    if (_pendingRequests.containsKey(cacheKey)) {
      return _pendingRequests[cacheKey]!.future;
    }

    final completer = Completer<ui.Image?>();
    _pendingRequests[cacheKey] = completer;

    try {
      ui.Image? image;

      switch (type) {
        case TextureType.smoothNoise:
          image = await _generateSeamlessSmoothNoiseTexture(
            baseColor,
            intensity: intensity,
            scale: scale,
          );
          break;
        case TextureType.paperFiber:
          image = await _generateSeamlessPaperTexture(
            baseColor,
            grainIntensity: intensity,
          );
          break;
        case TextureType.none:
          image = null;
          break;
      }

      _cache[cacheKey] = image;
      completer.complete(image);
    } catch (e) {
      debugPrint('Error generating texture: $e');
      completer.complete(null);
    } finally {
      _pendingRequests.remove(cacheKey);
    }

    return completer.future;
  }

  static void clearCache() {
    final imagesToDispose = _cache.values.whereType<ui.Image>().toList();
    _cache.clear();
    _pendingRequests.clear();

    for (final image in imagesToDispose) {
      image.dispose();
    }
  }

  // ============================================
  // SEAMLESS SMOOTH NOISE (Toroidal Sampling)
  // ============================================

  static Future<ui.Image?> _generateSeamlessSmoothNoiseTexture(
    Color baseColor, {
    required double intensity,
    required double scale,
  }) async {
    const width = textureWidth;
    const height = textureHeight;

    final baseR = (baseColor.r * 255.0).round() & 0xff;
    final baseG = (baseColor.g * 255.0).round() & 0xff;
    final baseB = (baseColor.b * 255.0).round() & 0xff;

    final pixels = await Isolate.run(() {
      return _generateSeamlessNoisePixels(
        Color.fromARGB(255, baseR, baseG, baseB),
        width,
        height,
        intensity: intensity,
        scale: scale,
      );
    });

    return _createImageFromPixels(pixels, width, height);
  }

  static Uint8List _generateSeamlessNoisePixels(
    Color baseColor,
    int width,
    int height, {
    required double intensity,
    required double scale,
  }) {
    final pixels = Uint8List(width * height * 4);
    final random = math.Random(42);

    // Permutation table for noise (must be at least 512 for proper wrapping)
    final perm = List<int>.generate(256, (i) => i)..shuffle(random);
    final p = [...perm, ...perm]; // Double for overflow handling

    // Gradient vectors
    final gradients = [
      [1.0, 1.0], [1.0, -1.0], [-1.0, 1.0], [-1.0, -1.0],
      [1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0],
    ];

    double fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

    double lerp(double a, double b, double t) => a + t * (b - a);

    double grad(int hash, double x, double y) {
      final g = gradients[hash & 7];
      return g[0] * x + g[1] * y;
    }

    // Perlin noise that tiles at period boundaries
    double tiledPerlin(double x, double y, int periodX, int periodY) {
      // Integer coordinates (wrapped)
      final xi = x.floor() % periodX;
      final yi = y.floor() % periodY;
      final xi1 = (xi + 1) % periodX;
      final yi1 = (yi + 1) % periodY;

      // Fractional coordinates
      final xf = x - x.floor();
      final yf = y - y.floor();

      // Fade curves
      final u = fade(xf);
      final v = fade(yf);

      // Hash coordinates (using permutation table)
      final aa = p[p[xi] + yi];
      final ab = p[p[xi] + yi1];
      final ba = p[p[xi1] + yi];
      final bb = p[p[xi1] + yi1];

      // Gradient dot products
      final g00 = grad(aa, xf, yf);
      final g10 = grad(ba, xf - 1, yf);
      final g01 = grad(ab, xf, yf - 1);
      final g11 = grad(bb, xf - 1, yf - 1);

      // Bilinear interpolation
      final x1 = lerp(g00, g10, u);
      final x2 = lerp(g01, g11, u);

      return lerp(x1, x2, v);
    }

    // Layered noise with seamless tiling
    double seamlessLayeredNoise(double normX, double normY, double baseScale) {
      double value = 0;
      double amplitude = 1;
      double maxAmplitude = 0;

      // Each octave must tile at texture boundaries
      // Period doubles each octave to maintain seamless tiling
      int period = (4 * baseScale).round().clamp(2, 64);

      for (int octave = 0; octave < 4; octave++) {
        final freq = period.toDouble();
        final x = normX * freq;
        final y = normY * freq;

        value += tiledPerlin(x, y, period, period) * amplitude;
        maxAmplitude += amplitude;

        amplitude *= 0.5;
        period *= 2; // Double period for next octave
      }

      return (value / maxAmplitude + 1) * 0.5; // Normalize to 0-1
    }

    final baseR = (baseColor.r * 255.0).round() & 0xff;
    final baseG = (baseColor.g * 255.0).round() & 0xff;
    final baseB = (baseColor.b * 255.0).round() & 0xff;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final normX = x / width;
        final normY = y / height;

        final noise = seamlessLayeredNoise(normX, normY, scale);
        final variation = (noise - 0.5) * 2 * intensity;

        final r = ((baseR * (1 + variation))).round().clamp(0, 255);
        final g = ((baseG * (1 + variation))).round().clamp(0, 255);
        final b = ((baseB * (1 + variation))).round().clamp(0, 255);

        final idx = (y * width + x) * 4;
        pixels[idx] = r;
        pixels[idx + 1] = g;
        pixels[idx + 2] = b;
        pixels[idx + 3] = 255;
      }
    }

    return pixels;
  }

  // ============================================
  // SEAMLESS PAPER GRAIN TEXTURE
  // ============================================

  static Future<ui.Image?> _generateSeamlessPaperTexture(
    Color baseColor, {
    required double grainIntensity,
  }) async {
    const width = textureWidth;
    const height = textureHeight;

    final baseR = (baseColor.r * 255.0).round() & 0xff;
    final baseG = (baseColor.g * 255.0).round() & 0xff;
    final baseB = (baseColor.b * 255.0).round() & 0xff;

    final pixels = await Isolate.run(() {
      return _generateSeamlessPaperPixels(
        Color.fromARGB(255, baseR, baseG, baseB),
        width,
        height,
        grainIntensity: grainIntensity,
      );
    });

    return _createImageFromPixels(pixels, width, height);
  }

  static Uint8List _generateSeamlessPaperPixels(
    Color baseColor,
    int width,
    int height, {
    required double grainIntensity,
  }) {
    final pixels = Uint8List(width * height * 4);
    final random = math.Random(42);

    final baseR = (baseColor.r * 255.0).round() & 0xff;
    final baseG = (baseColor.g * 255.0).round() & 0xff;
    final baseB = (baseColor.b * 255.0).round() & 0xff;

    // Fill with base color
    for (int i = 0; i < width * height; i++) {
      final idx = i * 4;
      pixels[idx] = baseR;
      pixels[idx + 1] = baseG;
      pixels[idx + 2] = baseB;
      pixels[idx + 3] = 255;
    }

    // Add grain
    final grainCount = (width * height * 0.5).toInt();

    for (int i = 0; i < grainCount; i++) {
      final x = random.nextInt(width);
      final y = random.nextInt(height);

      final isLight = random.nextBool();
      final grainOpacity = random.nextDouble() * grainIntensity;

      final idx = (y * width + x) * 4;

      final currentR = pixels[idx];
      final currentG = pixels[idx + 1];
      final currentB = pixels[idx + 2];

      final grainColor = isLight ? 255 : 0;

      pixels[idx] = _blend(currentR, grainColor, grainOpacity);
      pixels[idx + 1] = _blend(currentG, grainColor, grainOpacity);
      pixels[idx + 2] = _blend(currentB, grainColor, grainOpacity);
    }

    return pixels;
  }

  static int _blend(int base, int overlay, double opacity) {
    return (base + (overlay - base) * opacity).round().clamp(0, 255);
  }

  // ============================================
  // UTILITIES
  // ============================================

  static Future<ui.Image> _createImageFromPixels(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );

    return completer.future;
  }
}