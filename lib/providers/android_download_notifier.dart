import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:vce1_sakuraview/providers/pooled_download_notifier.dart';

/// Android 平台下载管理器：基于高速并发 HTTP 连接池引擎，并触发媒体库扫描与通知栏进度。
class AndroidDownloadNotifier extends PooledDownloadNotifier {
  final Logger _logger = Logger('AndroidDownloadNotifier');

  static const MethodChannel _mediaScanChannel =
      MethodChannel('com.sakuraview.dev/media_scan');

  AndroidDownloadNotifier()
      : super(
          loggerName: 'AndroidDownloadNotifier',
          enableNotifications: true,
        );

  @override
  Future<void> onFileSaved(String fullPath) async {
    try {
      await _mediaScanChannel
          .invokeMethod('scanFile', {'path': fullPath})
          .timeout(const Duration(seconds: 4));
    } on PlatformException catch (e) {
      _logger.fine('Media scan skipped or failed: ${e.message}');
    } catch (_) {}
  }
}
