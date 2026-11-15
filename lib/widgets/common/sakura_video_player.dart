import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';

/// 应用内嵌入式视频播放器（支持 MP4 / WebM / MKV 等格式，兼容站点防盗链 Header 与本地离线文件）。
class SakuraVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? posterUrl;
  final String? siteId;
  final bool autoPlay;
  final bool looping;
  final bool compact;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onTapBackground;

  /// 测试钩子：允许在桌面单元测试环境下绕过平台限制直接验证控制器交互。
  @visibleForTesting
  static bool? debugOverridePlatformSupported;

  const SakuraVideoPlayer({
    super.key,
    required this.videoUrl,
    this.posterUrl,
    this.siteId,
    this.autoPlay = true,
    this.looping = true,
    this.compact = false,
    this.onEnterFullscreen,
    this.onTapBackground,
  });

  @override
  State<SakuraVideoPlayer> createState() => _SakuraVideoPlayerState();
}

class _SakuraVideoPlayerState extends State<SakuraVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _muted = false;
  bool _showControls = true;
  String? _errorText;
  Timer? _hideControlsTimer;

  bool get _isLocalSource {
    final clean = widget.videoUrl.trim();
    return clean.isNotEmpty &&
        !clean.startsWith('http://') &&
        !clean.startsWith('https://');
  }

  bool get _isPlatformSupported {
    final override = SakuraVideoPlayer.debugOverridePlatformSupported;
    if (override != null) return override;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(SakuraVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.siteId != widget.siteId) {
      _disposeController();
      _initController();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      ctrl.removeListener(_onVideoTick);
      ctrl.dispose();
    }
  }

  void _onVideoTick() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _initController() async {
    final source = widget.videoUrl.trim();
    if (source.isEmpty) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorText = '缺少有效视频地址';
        });
      }
      return;
    }

    if (!_isPlatformSupported) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorText = '当前平台暂未启用内嵌视频解码，请点击外部播放';
        });
      }
      return;
    }

    setState(() {
      _initializing = true;
      _errorText = null;
      _showControls = true;
    });

    try {
      final VideoPlayerController ctrl;
      if (_isLocalSource) {
        ctrl = VideoPlayerController.file(File(source));
      } else {
        final headers = resolveSiteImageHeaders(source, siteId: widget.siteId);
        ctrl = VideoPlayerController.networkUrl(
          Uri.parse(source),
          httpHeaders: headers,
        );
      }

      _controller = ctrl;
      ctrl.addListener(_onVideoTick);
      await ctrl.setLooping(widget.looping);
      await ctrl.initialize();
      await ctrl.setVolume(_muted ? 0.0 : 1.0);
      if (widget.autoPlay) {
        await ctrl.play();
        _scheduleControlsHide();
      }
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorText = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorText = '视频加载失败：${e.toString().split('\n').first}';
        });
      }
    }
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isPlaying) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleControlsHide();
    } else {
      _hideControlsTimer?.cancel();
    }
    widget.onTapBackground?.call();
  }

  Future<void> _togglePlayPause() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
      _hideControlsTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    } else {
      await ctrl.play();
      if (mounted) setState(() => _showControls = true);
      _scheduleControlsHide();
    }
  }

  Future<void> _toggleMute() async {
    final ctrl = _controller;
    _muted = !_muted;
    if (ctrl != null && ctrl.value.isInitialized) {
      await ctrl.setVolume(_muted ? 0.0 : 1.0);
    }
    if (mounted) setState(() {});
    _scheduleControlsHide();
  }

  Future<void> _openExternal() async {
    final raw = widget.videoUrl.trim();
    if (raw.isEmpty) return;
    final uri = _isLocalSource ? Uri.file(raw) : Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法调起外部播放器')),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 359999);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildPosterBackdrop() {
    final poster = widget.posterUrl?.trim() ?? '';
    if (poster.isEmpty) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.movie_outlined, color: Colors.white38, size: 48),
        ),
      );
    }
    return SakuraAnimatedImage(
      imageUrl: poster,
      siteId: widget.siteId,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = _controller;
    final value = ctrl?.value;
    final isReady = ctrl != null && value != null && value.isInitialized;
    final hasError = _errorText != null || (value?.hasError ?? false);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isReady)
              Center(
                child: AspectRatio(
                  aspectRatio:
                      value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                  child: VideoPlayer(ctrl),
                ),
              )
            else
              Center(child: _buildPosterBackdrop()),

            if (_initializing || (isReady && value.isBuffering))
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            if (hasError && !_initializing)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_disabled_rounded,
                        color: Colors.white70,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorText ??
                            value?.errorDescription ??
                            '视频播放失败',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              _disposeController();
                              _initController();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('重试'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _openExternal,
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                            ),
                            label: const Text('外部播放'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            if (isReady && _showControls)
              Positioned.fill(
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                      fixedSize: Size.square(widget.compact ? 48 : 58),
                    ),
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: widget.compact ? 28 : 34,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                ),
              ),

            if (isReady && _showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.78),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoProgressIndicator(
                        ctrl,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        colors: VideoProgressColors(
                          playedColor: cs.primary,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: _togglePlayPause,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: _muted ? '取消静音' : '静音',
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: _toggleMute,
                          ),
                          if (widget.onEnterFullscreen != null)
                            IconButton(
                              tooltip: '全屏播放',
                              icon: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: widget.onEnterFullscreen,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
