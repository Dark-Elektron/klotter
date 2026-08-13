import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

void main() {
  runApp(const TextureExperimentApp());
}

class TextureExperimentApp extends StatelessWidget {
  const TextureExperimentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Texture Experiment',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const TexturePlayground(),
    );
  }
}

class TexturePlayground extends StatefulWidget {
  const TexturePlayground({super.key});

  @override
  State<TexturePlayground> createState() => _TexturePlaygroundState();
}

class _TexturePlaygroundState extends State<TexturePlayground> {
  Color _baseColor = Colors.blueGrey;
  double _intensity = 0.15;
  double _scale = 1.0;
  double _softness = 0.6;
  int _seed = 42;

  ui.Image? _noiseImage;
  bool _isGenerating = false;

  // Container background colors from AppColors themes
  final List<_ThemeColor> _presetColors = [
    _ThemeColor('Classic', Colors.blueGrey),
    _ThemeColor('Dark', const Color.fromARGB(255, 57, 57, 57)),
    _ThemeColor('Pink', const Color(0xFF3D3134)),
    _ThemeColor('Soft Pink', const Color(0xFFE29B9B)),
    _ThemeColor('Sunset Ember', const Color(0xFF3D2B2B)),
    _ThemeColor('Desert Sand', const Color(0xFFC18A63)),
    _ThemeColor('Digital Amber', const Color(0xFF1A120B)),
    _ThemeColor('Rose Chic', const Color(0xFF3D3D3D)),
    _ThemeColor('Honey Mustard', const Color(0xFFFFCF36)),
  ];

  @override
  void dispose() {
    _noiseImage?.dispose();
    super.dispose();
  }

  void _generateNoise(Size size) {
    if (_isGenerating) return;
    _isGenerating = true;

    // Generate at lower res for softness
    final scale = 0.3 + (_softness * 0.2);
    final width = (size.width * scale).toInt().clamp(50, 800);
    final height = (size.height * scale).toInt().clamp(50, 800);

    final pixels = _generateNoisePixels(width, height);

    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
      image,
    ) {
      if (mounted) {
        setState(() {
          _noiseImage?.dispose();
          _noiseImage = image;
          _isGenerating = false;
        });
      }
    });
  }

  Uint8List _generateNoisePixels(int width, int height) {
    final pixels = Uint8List(width * height * 4);
    final random = math.Random(_seed);

    // Pre-generate a grid of random values
    const gridSize = 32;
    final grid = List.generate(gridSize * gridSize, (_) => random.nextDouble());

    double getValue(int gx, int gy) {
      return grid[(gy % gridSize) * gridSize + (gx % gridSize)];
    }

    // Smooth noise function
    double smoothNoise(double x, double y) {
      final scaleX = x * _scale * 0.02;
      final scaleY = y * _scale * 0.02;

      final x0 = scaleX.floor();
      final y0 = scaleY.floor();
      final x1 = x0 + 1;
      final y1 = y0 + 1;

      final sx = scaleX - x0;
      final sy = scaleY - y0;

      // Smoothstep interpolation
      final tx = sx * sx * (3 - 2 * sx);
      final ty = sy * sy * (3 - 2 * sy);

      final n00 = getValue(x0, y0);
      final n10 = getValue(x1, y0);
      final n01 = getValue(x0, y1);
      final n11 = getValue(x1, y1);

      final nx0 = n00 + tx * (n10 - n00);
      final nx1 = n01 + tx * (n11 - n01);

      return nx0 + ty * (nx1 - nx0);
    }

    // Layered noise (FBM)
    double layeredNoise(double x, double y) {
      double value = 0;
      double amp = 1;
      double freq = 1;
      double maxAmp = 0;

      for (int i = 0; i < 5; i++) {
        value += smoothNoise(x * freq, y * freq) * amp;
        maxAmp += amp;
        amp *= 0.5;
        freq *= 2;
      }

      return value / maxAmp;
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Get noise value (0-1)
        final noise = layeredNoise(x.toDouble(), y.toDouble());

        // Convert to grayscale variation (-1 to 1 range, centered at 0)
        final variation = (noise - 0.5) * 2 * _intensity;

        // Apply to base color
        final r = ((_baseColor.red * (1 + variation))).round().clamp(0, 255);
        final g = ((_baseColor.green * (1 + variation))).round().clamp(0, 255);
        final b = ((_baseColor.blue * (1 + variation))).round().clamp(0, 255);

        final idx = (y * width + x) * 4;
        pixels[idx] = r;
        pixels[idx + 1] = g;
        pixels[idx + 2] = b;
        pixels[idx + 3] = 255;
      }
    }

    return pixels;
  }

  void _regenerate() {
    _noiseImage?.dispose();
    _noiseImage = null;
    setState(() {});
  }

  void _randomizeSeed() {
    _seed = math.Random().nextInt(10000);
    _regenerate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Texture preview
            Expanded(
              flex: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  if (_noiseImage == null && !_isGenerating && size.width > 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _generateNoise(size);
                    });
                  }

                  return Container(
                    color: _baseColor,
                    child:
                        _noiseImage != null
                            ? RawImage(
                              image: _noiseImage,
                              fit: BoxFit.cover,
                              width: size.width,
                              height: size.height,
                              filterQuality: FilterQuality.medium,
                            )
                            : const Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),

            // Controls
            Expanded(
              flex: 2,
              child: Container(
                color: const Color(0xFF1A1A1A),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Theme Colors (Container Backgrounds)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            _presetColors.map((themeColor) {
                              final isSelected =
                                  _baseColor.value == themeColor.color.value;
                              return Tooltip(
                                message: themeColor.name,
                                child: GestureDetector(
                                  onTap: () {
                                    _baseColor = themeColor.color;
                                    _regenerate();
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: themeColor.color,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color:
                                            isSelected
                                                ? Colors.white
                                                : Colors.grey,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // Show current theme name
                      Text(
                        'Current: ${_presetColors.firstWhere((t) => t.color.value == _baseColor.value, orElse: () => _ThemeColor('Custom', _baseColor)).name}',
                        style: const TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 16),
                      _buildSlider('Intensity', _intensity, 0.05, 0.4, (v) {
                        _intensity = v;
                        _regenerate();
                      }),
                      _buildSlider('Scale', _scale, 0.2, 3.0, (v) {
                        _scale = v;
                        _regenerate();
                      }),
                      _buildSlider('Softness', _softness, 0.0, 1.0, (v) {
                        _softness = v;
                        _regenerate();
                      }),

                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _randomizeSeed,
                        icon: const Icon(Icons.refresh),
                        label: Text('Randomize (Seed: $_seed)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(value.toStringAsFixed(2))),
      ],
    );
  }
}

class _ThemeColor {
  final String name;
  final Color color;

  const _ThemeColor(this.name, this.color);
}
