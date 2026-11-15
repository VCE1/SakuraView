import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';

/// 按图源域名隔离维护的 Cookie、User-Agent 与 Referer 注册表。
class SiteImageHeaderRegistry {
  static final Map<String, Map<String, String>> _siteOverrides = {};

  static void setSiteAuthHeaders({
    required String domainKeyword,
    String? cookies,
    String? userAgent,
    String? referer,
  }) {
    final key = domainKeyword.trim().toLowerCase();
    if (key.isEmpty) return;
    final map = <String, String>{};
    if (cookies != null && cookies.trim().isNotEmpty) {
      map['Cookie'] = cookies.trim();
    }
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      map['User-Agent'] = userAgent.trim();
    }
    if (referer != null && referer.trim().isNotEmpty) {
      map['Referer'] = referer.trim();
    }
    if (map.isEmpty) {
      _siteOverrides.remove(key);
    } else {
      _siteOverrides[key] = map;
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

/// 根据图片 URL 与所属图源 ID 生成适配的请求头（解决防盗链、Cookie 与 UA 问题）。
Map<String, String> resolveSiteImageHeaders(String url, {String? siteId}) {
  final lower = url.toLowerCase();
  final cleanSite = (siteId ?? '').trim().toLowerCase();
  final base = <String, String>{
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'User-Agent': 'vce1.sakuraview/1.2 (vce1)',
  };

  if (lower.contains('zerochan.net') || cleanSite == 'zerochan') {
    base['Referer'] = 'https://www.zerochan.net/';
    base['User-Agent'] = 'SakuraView - vce1';
  } else if (lower.contains('donmai.us') || cleanSite == 'danbooru') {
    base['Referer'] = 'https://danbooru.donmai.us/';
  } else if (lower.contains('yande.re') || cleanSite == 'yandere') {
    base['Referer'] = 'https://yande.re/';
  } else if (lower.contains('konachan') || cleanSite == 'konachan') {
    base['Referer'] = 'https://konachan.com/';
  } else if (lower.contains('gelbooru.com') || cleanSite == 'gelbooru') {
    base['Referer'] = 'https://gelbooru.com/';
  } else if (lower.contains('rule34.xxx') || cleanSite == 'rule34') {
    base['Referer'] = 'https://rule34.xxx/';
  } else if (lower.contains('sakugabooru.com') || cleanSite == 'sakugabooru') {
    base['Referer'] = 'https://www.sakugabooru.com/';
  } else if (lower.contains('e-shuushuu.net') || cleanSite == 'eshuushuu') {
    base['Referer'] = 'https://e-shuushuu.net/';
  }

  final overrides = SiteImageHeaderRegistry.getOverridesForUrl(url);
  if (overrides.isNotEmpty) {
    base.addAll(overrides);
  }
  return base;
}

/// Returns a [CachedNetworkImageProvider] (or [FileImage] for local paths)
/// pre-configured with site-specific headers.
ImageProvider createSiteImageProvider(
  String url, {
  Map<String, String>? extraHeaders,
  String? siteId,
}) {
  final trimmed = url.trim();
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return FileImage(File(trimmed));
  }
  final baseHeaders = resolveSiteImageHeaders(trimmed, siteId: siteId);
  final headers = extraHeaders == null || extraHeaders.isEmpty
      ? baseHeaders
      : <String, String>{...baseHeaders, ...extraHeaders};
  return CachedNetworkImageProvider(trimmed, headers: headers);
}

/// An animated image widget modeled after `pixes`'s `AnimatedImage`
/// (`lib/components/animated_image.dart`), safely handling lifecycle across
/// orientation / layout changes without prematurely disposing cached `ui.Image`s.
class SakuraAnimatedImage extends StatefulWidget {
  final String imageUrl;
  final String? siteId;
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
  final bool enableRetryTap;

  const SakuraAnimatedImage({
    super.key,
    required this.imageUrl,
    this.siteId,
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
    this.enableRetryTap = true,
  });

  @override
  State<SakuraAnimatedImage> createState() => _SakuraAnimatedImageState();
}

class _SakuraAnimatedImageState extends State<SakuraAnimatedImage>
    with WidgetsBindingObserver {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  bool _isListeningToStream = false;
  bool _invertColors = false;
  int? _frameNumber;
  late DisposableBuildContext<State<SakuraAnimatedImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;
  int _retryCount = 0;
  Timer? _retryTimer;

  ImageProvider get _effectiveProvider {
    final base = createSiteImageProvider(
      widget.imageUrl,
      extraHeaders: widget.headers,
      siteId: widget.siteId,
    );
    final isGif =
        widget.imageUrl.toLowerCase().split('?').first.endsWith('.gif');
    final isAnimated = SourceUrlResolver.isAnimatedMedia(url: widget.imageUrl);
    if (isGif || (isAnimated && widget.fit == BoxFit.contain)) {
      return base;
    }
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
    if (widget.imageUrl.isNotEmpty &&
        !SourceUrlResolver.isVideoMedia(url: widget.imageUrl)) {
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
        widget.siteId != oldWidget.siteId ||
        widget.cacheWidth != oldWidget.cacheWidth ||
        widget.cacheHeight != oldWidget.cacheHeight) {
      _retryCount = 0;
      _retryTimer?.cancel();
      if (widget.imageUrl.isNotEmpty &&
          !SourceUrlResolver.isVideoMedia(url: widget.imageUrl)) {
        _resolveImage();
      } else {
        _stopListeningToStream();
        _imageInfo = null;
        _lastException = widget.imageUrl.isEmpty ? ArgumentError('Empty URL') : null;
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
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      return;
    }
    setState(() {
      _imageInfo = imageInfo;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
    });
  }

  void _handleImageChunk(ImageChunkEvent event) {
    if (!mounted) return;
    setState(() {
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

    _frameNumber = null;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool hasBoundedBox =
            constraints.hasBoundedWidth && constraints.hasBoundedHeight;
        final double? resolvedWidth =
            widget.width ?? (hasBoundedBox ? double.infinity : null);
        final double? resolvedHeight =
            widget.height ?? (hasBoundedBox ? double.infinity : null);

        Widget content;
        if (SourceUrlResolver.isVideoMedia(url: widget.imageUrl)) {
          content = KeyedSubtree(
            key: const ValueKey<String>('video_media'),
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_outline_rounded,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        } else if (widget.imageUrl.isEmpty || _lastException != null) {
          content = KeyedSubtree(
            key: const ValueKey<String>('error'),
            child: _buildErrorWidget(context),
          );
        } else if (_imageInfo != null) {
          Widget img = RawImage(
            image: _imageInfo?.image,
            debugImageLabel: _imageInfo?.debugLabel,
            width: resolvedWidth,
            height: resolvedHeight,
            scale: _imageInfo?.scale ?? 1.0,
            fit: widget.fit,
            alignment: widget.alignment,
            invertColors: _invertColors,
            filterQuality: widget.filterQuality,
          );
          if (hasBoundedBox && widget.fit == BoxFit.cover) {
            img = SizedBox.expand(child: img);
          }
          content = KeyedSubtree(
            key: ValueKey<String>('image_${widget.imageUrl}'),
            child: img,
          );
        } else {
          Widget placeholder = _buildLoadingWidget(context);
          if (hasBoundedBox) {
            placeholder = SizedBox.expand(child: placeholder);
          }
          content = KeyedSubtree(
            key: const ValueKey<String>('placeholder'),
            child: placeholder,
          );
        }

        Widget switcher = AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: (hasBoundedBox || widget.width != null && widget.height != null)
                  ? StackFit.expand
                  : StackFit.loose,
              alignment: Alignment.center,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: content,
        );

        if (widget.borderRadius != null) {
          switcher = ClipRRect(
            borderRadius: widget.borderRadius!,
            clipBehavior: Clip.antiAlias,
            child: switcher,
          );
        }

        return SizedBox(
          width: resolvedWidth,
          height: resolvedHeight,
          child: switcher,
        );
      },
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.40),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = Center(
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
            widget.enableRetryTap ? '点按重试' : '点击查看详情',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant.withAlpha(140),
            ),
          ),
        ],
      ),
    );
    if (!widget.enableRetryTap) {
      return ColoredBox(
        color: cs.surfaceContainerHighest.withAlpha(90),
        child: body,
      );
    }
    return Material(
      color: cs.surfaceContainerHighest.withAlpha(90),
      child: InkWell(
        onTap: _manualRetry,
        child: body,
      ),
    );
  }
}
