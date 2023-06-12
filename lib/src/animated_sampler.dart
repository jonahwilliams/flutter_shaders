// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A callback for the [AnimatedSamplerBuilder] widget.
typedef AnimatedSamplerBuilder = void Function(
  ui.Image image,
  Size size,
  ui.Canvas canvas,
);

/// A widget that allows access to a snapshot of the child widgets for painting
/// with a sampler applied to a [FragmentProgram].
///
/// When [enabled] is true, the child widgets will be painted into a texture
/// exposed as a [ui.Image]. This can then be passed to a [FragmentShader]
/// instance via [FragmentShader.setSampler].
///
/// If [enabled] is false, then the child widgets are painted as normal.
///
/// Caveats:
///   * Platform views cannot be captured in a texture. If any are present they
///     will be excluded from the texture. Texture-based platform views are OK.
///
/// Example:
///
/// Providing an image to a fragment shader using
/// [FragmentShader.setImageSampler].
///
/// ```dart
/// Widget build(BuildContext context) {
///   return AnimatedSampler(
///     (ui.Image image, Size size, Canvas canvas) {
///       shader
///         ..setFloat(0, size.width)
///         ..setFloat(1, size.height)
///         ..setImageSampler(0, image);
///       canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
///     },
///     child: widget.child,
///   );
/// }
/// ```
///
/// See also:
///   * [SnapshotWidget], which provides a similar API for the purpose of
///      caching during expensive animations.
class AnimatedSampler extends StatelessWidget {
  /// Create a new [AnimatedSampler].
  const AnimatedSampler(
    this.builder, {
    required this.child,
    super.key,
    this.enabled = true,
  });

  /// A callback used by this widget to provide the children captured in
  /// a texture.
  final AnimatedSamplerBuilder builder;

  /// Whether the children should be captured in a texture or displayed as
  /// normal.
  final bool enabled;

  /// The child widget.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _ShaderSamplerBuilder(
      builder,
      enabled: enabled,
      child: child,
    );
  }
}

class _ShaderSamplerBuilder extends SingleChildRenderObjectWidget {
  const _ShaderSamplerBuilder(
    this.builder, {
    super.child,
    required this.enabled,
  });

  final AnimatedSamplerBuilder builder;
  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderShaderSamplerBuilderWidget(
      devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      builder: builder,
      enabled: enabled,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderShaderSamplerBuilderWidget)
      ..devicePixelRatio = MediaQuery.of(context).devicePixelRatio
      ..builder = builder
      ..enabled = enabled;
  }
}

// A render object that conditionally converts its child into a [ui.Image]
// and then paints it in place of the child.
class _RenderShaderSamplerBuilderWidget extends RenderProxyBox {
  // Create a new [_RenderSnapshotWidget].
  _RenderShaderSamplerBuilderWidget({
    required double devicePixelRatio,
    required AnimatedSamplerBuilder builder,
    required bool enabled,
  })  : _devicePixelRatio = devicePixelRatio,
        _builder = builder,
        _enabled = enabled;

  @override
  OffsetLayer updateCompositedLayer(
      {required covariant _ShaderSamplerBuilderLayer? oldLayer}) {
    final _ShaderSamplerBuilderLayer layer =
        oldLayer ?? _ShaderSamplerBuilderLayer(builder);
    layer
      ..callback = builder
      ..size = size
      ..devicePixelRatio = devicePixelRatio;
    return layer;
  }

  /// The device pixel ratio used to create the child image.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsCompositedLayerUpdate();
  }

  /// The painter used to paint the child snapshot or child widgets.
  AnimatedSamplerBuilder get builder => _builder;
  AnimatedSamplerBuilder _builder;
  set builder(AnimatedSamplerBuilder value) {
    if (value == builder) {
      return;
    }
    _builder = value;
    markNeedsCompositedLayerUpdate();
  }

  bool get enabled => _enabled;
  bool _enabled;
  set enabled(bool value) {
    if (value == enabled) {
      return;
    }
    _enabled = value;
    markNeedsPaint();
    markNeedsCompositingBitsUpdate();
  }

  @override
  bool get isRepaintBoundary => alwaysNeedsCompositing;

  @override
  bool get alwaysNeedsCompositing => enabled;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      return;
    }
    assert(!_enabled || offset == Offset.zero);
    return super.paint(context, offset);
  }
}

/// A [Layer] that uses an [AnimatedSamplerBuilder] to create a [ui.Picture]
/// every time it is added to a scene.
class _ShaderSamplerBuilderLayer extends OffsetLayer {
  _ShaderSamplerBuilderLayer(this._callback);

  ui.Picture? _lastPicture;

  Size get size => _size;
  Size _size = Size.zero;
  set size(Size value) {
    if (value == size) {
      return;
    }
    _size = value;
    markNeedsAddToScene();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio = 1.0;
  set devicePixelRatio(double value) {
    if (value == devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  AnimatedSamplerBuilder get callback => _callback;
  AnimatedSamplerBuilder _callback;
  set callback(AnimatedSamplerBuilder value) {
    if (value == callback) {
      return;
    }
    _callback = value;
    markNeedsAddToScene();
  }

  ui.Image _buildChildScene(Rect bounds, double pixelRatio) {
    final ui.SceneBuilder builder = ui.SceneBuilder();
    final Matrix4 transform =
        Matrix4.diagonal3Values(pixelRatio, pixelRatio, 1);
    builder.pushTransform(transform.storage);
    addChildrenToScene(builder);
    builder.pop();
    return builder.build().toImageSync(
          (pixelRatio * bounds.width).ceil(),
          (pixelRatio * bounds.height).ceil(),
        );
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    _lastPicture?.dispose();

    if (size.isEmpty) return;
    final ui.Image image = _buildChildScene(
      offset & size,
      devicePixelRatio,
    );
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    try {
      callback(image, size, canvas);
    } finally {
      image.dispose();
    }
    final ui.Picture picture = pictureRecorder.endRecording();
    _lastPicture = picture;
    builder.addPicture(offset, picture);
  }

  @override
  void dispose() {
    _lastPicture?.dispose();
    super.dispose();
  }
}
