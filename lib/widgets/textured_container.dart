// lib/widgets/textured_container.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import '../utils/texture_generator.dart';
import '../utils/app_colors.dart';
import '../settings/settings_provider.dart';

class TexturedContainer extends StatefulWidget {
  final Color baseColor;
  final Widget child;
  final BoxDecoration? decoration;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const TexturedContainer({
    super.key,
    required this.baseColor,
    required this.child,
    this.decoration,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  State<TexturedContainer> createState() => _TexturedContainerState();
}

class _TexturedContainerState extends State<TexturedContainer>
    with SingleTickerProviderStateMixin {
  ui.Image? _textureImage;
  bool _isLoading = false;
  String _loadedCacheKey = '';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _hasAnimatedIn = false;

  TextureType? _lastTextureType;
  int? _lastColorValue;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAndLoadTexture();
  }

  @override
  void didUpdateWidget(TexturedContainer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.baseColor.toARGB32() != widget.baseColor.toARGB32()) {
      _resetAndReload();
    }
  }

  void _resetAndReload() {
    _textureImage = null;
    _hasAnimatedIn = false;
    _fadeController.value = 0.0;
    _loadedCacheKey = '';
    _checkAndLoadTexture();
  }

  void _checkAndLoadTexture() {
    if (!mounted) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final currentColorValue = widget.baseColor.toARGB32();

    final settingsChanged = _lastTextureType != settings.textureType ||
        _lastColorValue != currentColorValue;

    if (settingsChanged) {
      _lastTextureType = settings.textureType;
      _lastColorValue = currentColorValue;

      _textureImage = null;
      _hasAnimatedIn = false;
      _fadeController.value = 0.0;
      _loadedCacheKey = '';
      _isLoading = false;
    }

    _primeTextureFromCache();
    _loadTexture();
  }

  String _getCacheKey(Color color, TextureType type) {
    final colors = AppColors.of(context, listen: false);
    return '${color.toARGB32()}_${type.name}_${colors.textureIntensity}_${colors.textureScale}';
  }

  void _primeTextureFromCache() {
    if (!mounted) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final textureType = settings.textureType;
    final colors = AppColors.of(context, listen: false);

    if (textureType == TextureType.none) {
      _textureImage = null;
      return;
    }

    final cached = TextureGenerator.peekCachedTexture(
      widget.baseColor,
      type: textureType,
      intensity: colors.textureIntensity,
      scale: colors.textureScale,
    );

    if (cached == null) return;

    final cacheKey = _getCacheKey(widget.baseColor, textureType);

    _textureImage = cached;
    _loadedCacheKey = cacheKey;

    if (!_hasAnimatedIn) {
      _fadeController.value = 1.0;
      _hasAnimatedIn = true;
    }
  }

  Future<void> _loadTexture() async {
    if (!mounted) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final textureType = settings.textureType;

    if (textureType == TextureType.none) {
      if (_textureImage != null && mounted) {
        setState(() {
          _textureImage = null;
        });
      }
      return;
    }

    final colorToLoad = widget.baseColor;
    final cacheKey = _getCacheKey(colorToLoad, textureType);

    if (_textureImage != null && _loadedCacheKey == cacheKey) {
      return;
    }

    if (_isLoading && _loadedCacheKey == cacheKey) {
      return;
    }

    _isLoading = true;
    _loadedCacheKey = cacheKey;

    try {
      final colors = AppColors.of(context, listen: false);

      final image = await TextureGenerator.getTexture(
        colorToLoad,
        TextureGenerator.textureSize,
        type: textureType,
        intensity: colors.textureIntensity,
        scale: colors.textureScale,
        softness: colors.textureSoftness,
      );

      if (!mounted) {
        _isLoading = false;
        return;
      }

      final currentCacheKey = _getCacheKey(
        widget.baseColor,
        settings.textureType,
      );

      if (image != null && cacheKey == currentCacheKey) {
        setState(() {
          _textureImage = image;
          _isLoading = false;
        });

        if (!_hasAnimatedIn && mounted) {
          _fadeController.forward();
          _hasAnimatedIn = true;
        }
      } else {
        _isLoading = false;
        if (cacheKey != currentCacheKey && mounted) {
          _loadTexture();
        }
      }
    } catch (e) {
      assert(() {
        debugPrint('Error generating texture: $e');
        return true;
      }());
      if (mounted) {
        _isLoading = false;
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _textureImage = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final textureType = settings.textureType;

    final currentColorValue = widget.baseColor.toARGB32();
    final needsReload = _lastTextureType != textureType ||
        _lastColorValue != currentColorValue;

    if (needsReload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkAndLoadTexture();
        }
      });
    }

    BoxDecoration baseDecoration = widget.decoration ?? const BoxDecoration();

    // No texture - simple container
    if (textureType == TextureType.none) {
      return Container(
        width: widget.width,
        height: widget.height,
        padding: widget.padding,
        margin: widget.margin,
        decoration: baseDecoration.copyWith(color: widget.baseColor),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        final showBaseColor = _textureImage == null || _fadeAnimation.value < 1.0;

        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: baseDecoration.copyWith(
            color: showBaseColor ? widget.baseColor : Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: baseDecoration.borderRadius?.resolve(TextDirection.ltr) 
                ?? BorderRadius.zero,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // Tiled texture layer
                if (_textureImage != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: _fadeAnimation.value,
                      child: RawImage(
                        image: _textureImage,
                        fit: BoxFit.none, // Don't scale, just tile
                        repeat: ImageRepeat.repeat, // Tile the texture!
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                // Content with padding
                Padding(
                  padding: widget.padding ?? EdgeInsets.zero,
                  child: widget.child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}