import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:shimmer/shimmer.dart';

/// Site-aware headers helper inspired by pixes's CachedImageProvider.
Map<String, String> resolveSiteImageHeaders(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('zerochan.net')) {
    return const {
      'Referer': 'https://www.zerochan.net/',
      'User-Agent': 'SakuraView - vce1',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }
  if (lower.contains('donmai.us')) {
    return const {
      'Referer': 'https://danbooru.donmai.us/',
      'User-Agent': 'vce1.sakuraview/1.1 (vce1)',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }
  if (lower.contains('yande.re')) {
    return const {
      'Referer': 'https://yande.re/',
      'User-Agent': 'vce1.sakuraview/1.1 (vce1)',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }
  return const {
    'User-Agent': 'vce1.sakuraview/1.1 (vce1)',
  };
}

/// Convenience provider that attaches site-specific headers.
ImageProvider createSiteImageProvider(String url, {int? maxWidth, int? maxHeight}) {
  return CachedNetworkImageProvider(
    url,
    headers: resolveSiteImageHeaders(url),
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}

/// Image widget modeled on pixes's `AnimatedImage`:
/// - Uses `ScrollAwareImageProvider` so fast scrolling defers decoding.
/// - Tracks byte-level `ImageChunkEvent` progress.
/// - Automatically retries transient network failures and evicts broken cache entries.
/// - Smoothly transitions from shimmer/progress to decoded `RawImage` via `AnimatedSwitcher`.
class SakuraAnimatedImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final bool showProgressRing;
  final int? cacheWidth;
  final int? cacheHeight;
  final BorderRadius? borderRadius;

  const SakuraAnimatedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = false,
    this.showProgressRing = false,
    this.cacheWidth,
    this.cacheHeight,
    this.borderRadius,
  });

  @override
  State<SakuraAnimatedImage> createState() => _SakuraAnimatedImageState();
}

class _SakuraAnimatedImageState extends State<SakuraAnimatedImage>
    with WidgetsBindingObserver {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _loadingProgress;
  bool _isListeningToStream = false;
  late bool _invertColors;
  int? _frameNumber;
  bool _wasSynchronouslyLoaded = false;
  late DisposableBuildContext<State<SakuraAnimatedImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;
  int _retryCount = 0;
  Timer? _retryTimer;

  ImageProvider get _effectiveProvider {
    final base = createSiteImageProvider(widget.imageUrl);
    return ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      widget.cacheHeight,
      base,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollAwareContext = DisposableBuildContext<State<SakuraAnimatedImage>>(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _stopListeningToStream();
    _completerHandle?.dispose();
    _scrollAwareContext.dispose();
    _replaceImage(info: null);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    _updateInvertColors();
    if (widget.imageUrl.isNotEmpty) {
      _resolveImage();
      if (TickerMode.valuesOf(context).enabled) {
        _listenToStream();
      } else {
        _stopListeningToStream(keepStreamAlive: true);
      }
    }
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(SakuraAnimatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl ||
        widget.cacheWidth != oldWidget.cacheWidth ||
        widget.cacheHeight != oldWidget.cacheHeight) {
      _retryCount = 0;
      _retryTimer?.cancel();
      if (widget.imageUrl.isNotEmpty) {
        _resolveImage();
      } else {
        _stopListeningToStream();
        setState(() {
          _replaceImage(info: null);
          _lastException = ArgumentError('Empty URL');
        });
      }
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    setState(_updateInvertColors);
  }

  @override
  void reassemble() {
    if (widget.imageUrl.isNotEmpty) {
      _resolveImage();
    }
    super.reassemble();
  }

  void _updateInvertColors() {
    _invertColors = MediaQuery.maybeInvertColorsOf(context) ??
        SemanticsBinding.instance.accessibilityFeatures.invertColors;
  }

  void _resolveImage() {
    final ScrollAwareImageProvider provider = ScrollAwareImageProvider<Object>(
      context: _scrollAwareContext,
      imageProvider: _effectiveProvider,
    );
    final ImageStream newStream = provider.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    _updateSourceStream(newStream);
  }

  ImageStreamListener? _imageStreamListener;

  ImageStreamListener _getListener({bool recreateListener = false}) {
    if (_imageStreamListener == null || recreateListener) {
      _lastException = null;
      _imageStreamListener = ImageStreamListener(
        _handleImageFrame,
        onChunk: _handleImageChunk,
        onError: _handleError,
      );
    }
    return _imageStreamListener!;
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    if (!mounted) {
      imageInfo.dispose();
      return;
    }
    setState(() {
      _replaceImage(info: imageInfo.clone());
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      _wasSynchronouslyLoaded = _wasSynchronouslyLoaded || synchronousCall;
    });
  }

  void _handleImageChunk(ImageChunkEvent event) {
    if (!mounted) return;
    setState(() {
      _loadingProgress = event;
      _lastException = null;
    });
  }

  void _handleError(Object error, StackTrace? stackTrace) {
    scheduleMicrotask(() {
      PaintingBinding.instance.imageCache.evict(_effectiveProvider);
    });
    if (!mounted) return;
    if (_retryCount < 2) {
      _retryCount++;
      final delaySeconds = _retryCount * 2;
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: delaySeconds), () {
        if (!mounted) return;
        _imageStreamListener = null;
        _resolveImage();
        _listenToStream();
      });
      return;
    }
    setState(() {
      _lastException = error;
    });
  }

  void _replaceImage({required ImageInfo? info}) {
    final ImageInfo? oldImageInfo = _imageInfo;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      oldImageInfo?.dispose();
    });
    _imageInfo = info;
  }

  void _updateSourceStream(ImageStream newStream) {
    if (_imageStream?.key == newStream.key) {
      return;
    }
    if (_isListeningToStream) {
      _imageStream?.removeListener(_getListener());
    }
    if (!widget.gaplessPlayback) {
      setState(() {
        _replaceImage(info: null);
      });
    }
    setState(() {
      _loadingProgress = null;
      _frameNumber = null;
      _wasSynchronouslyLoaded = false;
    });
    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }
  }

  void _listenToStream() {
    if (_isListeningToStream || _imageStream == null) {
      return;
    }
    _imageStream!.addListener(_getListener());
    _completerHandle?.dispose();
    _completerHandle = null;
    _isListeningToStream = true;
  }

  void _stopListeningToStream({bool keepStreamAlive = false}) {
    if (!_isListeningToStream || _imageStream == null) {
      return;
    }
    if (keepStreamAlive &&
        _completerHandle == null &&
        _imageStream?.completer != null) {
      _completerHandle = _imageStream!.completer!.keepAlive();
    }
    _imageStream!.removeListener(_getListener());
    _isListeningToStream = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget result;

    if (_imageInfo != null) {
      result = RawImage(
        key: ValueKey<String>('img_${widget.imageUrl}'),
        image: _imageInfo?.image,
        width: widget.width,
        height: widget.height,
        debugImageLabel: _imageInfo?.debugLabel,
        scale: _imageInfo?.scale ?? 1.0,
        alignment: widget.alignment,
        invertColors: _invertColors,
        filterQuality: widget.filterQuality,
        fit: widget.fit,
      );
    } else if (_lastException != null || widget.imageUrl.isEmpty) {
      result = Container(
        key: const ValueKey<String>('error'),
        width: widget.width,
        height: widget.height,
        color: isDark
            ? cs.surfaceContainerHighest.withAlpha(110)
            : cs.surfaceContainerHighest,
        child: Center(
          child: IconButton(
            tooltip: 'Tap to retry',
            icon: Icon(
              Icons.refresh_rounded,
              color: cs.onSurfaceVariant.withAlpha(160),
              size: 26,
            ),
            onPressed: () {
              setState(() {
                _retryCount = 0;
                _lastException = null;
              });
              _imageStreamListener = null;
              _resolveImage();
              _listenToStream();
            },
          ),
        ),
      );
    } else {
      double? progressValue;
      if (_loadingProgress != null &&
          _loadingProgress!.expectedTotalBytes != null &&
          _loadingProgress!.expectedTotalBytes! > 0) {
        progressValue = (_loadingProgress!.cumulativeBytesLoaded /
                _loadingProgress!.expectedTotalBytes!)
            .clamp(0.0, 1.0);
      }

      result = Stack(
        key: const ValueKey<String>('loading'),
        fit: StackFit.expand,
        children: [
          Shimmer.fromColors(
            baseColor: isDark
                ? const Color(0xFF232538)
                : Colors.grey.shade200,
            highlightColor: isDark
                ? const Color(0xFF2F324B)
                : Colors.grey.shade100,
            period: const Duration(milliseconds: 1100),
            child: Container(
              width: widget.width,
              height: widget.height,
              color: isDark ? const Color(0xFF232538) : Colors.white,
            ),
          ),
          if (widget.showProgressRing || progressValue != null)
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: progressValue,
                  strokeWidth: 2.2,
                  color: cs.primary.withAlpha(200),
                ),
              ),
            ),
        ],
      );
    }

    Widget animated = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: result,
    );

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: animated,
      );
    }
    return animated;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(DiagnosticsProperty<ImageStream>('stream', _imageStream));
    description.add(DiagnosticsProperty<ImageInfo>('pixels', _imageInfo));
    description.add(DiagnosticsProperty<ImageChunkEvent>(
        'loadingProgress', _loadingProgress));
  }
}
