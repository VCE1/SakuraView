import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shimmer/shimmer.dart';

/// Custom per-site cookies & User-Agent registry updated by [SiteConfigProvider].
class SiteImageHeaderRegistry {
  static final Map<String, Map<String, String>> _siteOverrides = {};

  static void setSiteAuthHeaders({
    required String domainKeyword,
    String? cookies,
    String? userAgent,
  }) {
    final map = <String, String>{};
    if (cookies != null && cookies.trim().isNotEmpty) {
      map['Cookie'] = cookies.trim();
    }
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      map['User-Agent'] = userAgent.trim();
    }
    if (map.isEmpty) {
      _siteOverrides.remove(domainKeyword);
    } else {
      _siteOverrides[domainKeyword] = map;
    }
  }

  static Map<String, String> getOverridesForUrl(String url) {
    final lower = url.toLowerCase();
    for (final entry in _siteOverrides.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return const {};
  }
}

/// Site-aware headers helper inspired by pixes's CachedImageProvider.
Map<String, String> resolveSiteImageHeaders(String url) {
  final lower = url.toLowerCase();
  final base = <String, String>{
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };
  if (lower.contains('zerochan.net')) {
    base['Referer'] = 'https://www.zerochan.net/';
    base['User-Agent'] = 'SakuraView - vce1';
  } else if (lower.contains('donmai.us')) {
    base['Referer'] = 'https://danbooru.donmai.us/';
    base['User-Agent'] = 'vce1.sakuraview/1.2 (vce1)';
  } else if (lower.contains('yande.re')) {
    base['Referer'] = 'https://yande.re/';
    base['User-Agent'] = 'vce1.sakuraview/1.2 (vce1)';
  } else {
    base['User-Agent'] = 'vce1.sakuraview/1.2 (vce1)';
  }

  final overrides = SiteImageHeaderRegistry.getOverridesForUrl(url);
  if (overrides.isNotEmpty) {
    base.addAll(overrides);
  }
  return base;
}

/// Returns a [CachedNetworkImageProvider] pre-configured with site-specific headers.
ImageProvider createSiteImageProvider(
  String url, {
  Map<String, String>? extraHeaders,
}) {
  final baseHeaders = resolveSiteImageHeaders(url);
  final headers = extraHeaders == null || extraHeaders.isEmpty
      ? baseHeaders
      : <String, String>{...baseHeaders, ...extraHeaders};
  return CachedNetworkImageProvider(url, headers: headers);
}

/// An animated image widget modeled after `pixes`'s `AnimatedImage`
/// (`lib/components/animated_image.dart`), safely handling lifecycle across
/// orientation / layout changes without prematurely disposing cached `ui.Image`s.
class SakuraAnimatedImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final Map<String, String>? headers;
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
    this.headers,
    this.gaplessPlayback = true,
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
  bool _invertColors = false;
  int? _frameNumber;
  bool _wasSynchronouslyLoaded = false;
  late DisposableBuildContext<State<SakuraAnimatedImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;
  int _retryCount = 0;
  Timer? _retryTimer;

  ImageProvider get _effectiveProvider {
    final base = createSiteImageProvider(
      widget.imageUrl,
      extraHeaders: widget.headers,
    );
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
    _scrollAwareContext =
        DisposableBuildContext<State<SakuraAnimatedImage>>(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _stopListeningToStream();
    _completerHandle?.dispose();
    _scrollAwareContext.dispose();
    // Do NOT call _imageInfo?.dispose() here because CachedNetworkImageProvider's
    // MultiImageStreamCompleter shares the same ImageInfo instance across
    // ImageCache and active listeners without cloning. Disposing it during
    // orientation-change grid rebuilds would corrupt active ui.Image handles.
    _imageInfo = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateInvertColors();
    if (widget.imageUrl.isNotEmpty) {
      _resolveImage(fromDependenciesChange: true);
      if (TickerMode.valuesOf(context).enabled) {
        _listenToStream();
      } else {
        _stopListeningToStream(keepStreamAlive: true);
      }
    }
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
        _imageInfo = null;
        _lastException = ArgumentError('Empty URL');
      }
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    if (mounted) {
      setState(_updateInvertColors);
    }
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

  void _resolveImage({bool fromDependenciesChange = false}) {
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
    _updateSourceStream(newStream, fromDependenciesChange: fromDependenciesChange);
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
    if (!mounted) return;
    if (synchronousCall) {
      _imageInfo = imageInfo;
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      _wasSynchronouslyLoaded = true;
      return;
    }
    setState(() {
      _imageInfo = imageInfo;
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
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

  void _updateSourceStream(
    ImageStream newStream, {
    bool fromDependenciesChange = false,
  }) {
    if (_imageStream?.key == newStream.key) {
      return;
    }

    if (_isListeningToStream) {
      _imageStream?.removeListener(_getListener());
    }

    if (!widget.gaplessPlayback) {
      _imageInfo = null;
    }

    _loadingProgress = null;
    _frameNumber = null;
    _wasSynchronouslyLoaded = false;

    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }

    if (!fromDependenciesChange && mounted) {
      setState(() {});
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
    if (!_isListeningToStream) {
      return;
    }
    if (keepStreamAlive &&
        _completerHandle == null &&
        _imageStream?.completer != null) {
      _completerHandle = _imageStream!.completer!.keepAlive();
    }
    _imageStream?.removeListener(_getListener());
    _isListeningToStream = false;
  }

  void _manualRetry() {
    if (widget.imageUrl.isEmpty) return;
    setState(() {
      _retryCount = 0;
      _lastException = null;
      _loadingProgress = null;
    });
    PaintingBinding.instance.imageCache.evict(_effectiveProvider);
    _stopListeningToStream();
    _imageStreamListener = null;
    _imageStream = null;
    _resolveImage();
    _listenToStream();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (widget.imageUrl.isEmpty || _lastException != null) {
      content = _buildErrorWidget(context);
    } else if (_imageInfo != null) {
      Widget raw = RawImage(
        image: _imageInfo?.image,
        debugImageLabel: _imageInfo?.debugLabel,
        width: widget.width,
        height: widget.height,
        scale: _imageInfo?.scale ?? 1.0,
        fit: widget.fit,
        alignment: widget.alignment,
        invertColors: _invertColors,
        filterQuality: widget.filterQuality,
      );
      if (!_wasSynchronouslyLoaded) {
        raw = TweenAnimationBuilder<double>(
          key: ValueKey<String>(widget.imageUrl),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (ctx, opacity, child) => Opacity(
            opacity: opacity,
            child: child,
          ),
          child: raw,
        );
      }
      content = raw;
    } else {
      content = _buildLoadingWidget(context);
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: content,
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final baseColor = isDark
        ? cs.surfaceContainerHighest.withAlpha(110)
        : cs.surfaceContainerHighest.withAlpha(160);
    final highlightColor = isDark
        ? cs.surfaceContainerHighest.withAlpha(190)
        : Colors.white.withAlpha(220);

    double? progress;
    if (_loadingProgress != null &&
        _loadingProgress!.expectedTotalBytes != null &&
        _loadingProgress!.expectedTotalBytes! > 0) {
      progress = _loadingProgress!.cumulativeBytesLoaded /
          _loadingProgress!.expectedTotalBytes!;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          period: const Duration(milliseconds: 1300),
          child: const ColoredBox(color: Colors.white),
        ),
        if (widget.showProgressRing || (progress != null && progress > 0.05))
          Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.2,
                color: cs.primary.withAlpha(200),
                backgroundColor: cs.primary.withAlpha(40),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withAlpha(90),
      child: InkWell(
        onTap: _manualRetry,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: cs.onSurfaceVariant.withAlpha(140),
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                '点按重试',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant.withAlpha(140),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
