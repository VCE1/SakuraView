import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生 Android 通知栏下载进度与完成提醒封装。
class DownloadNotificationService {
  DownloadNotificationService._();

  static const MethodChannel _channel =
      MethodChannel('com.sakuraview.dev/download_notifications');

  static bool _permissionRequested = false;

  @visibleForTesting
  static bool? debugOverrideIsSupported;

  static bool get _isSupported =>
      debugOverrideIsSupported ?? (!kIsWeb && Platform.isAndroid);

  static Future<void> ensurePermissionOnce() async {
    if (!_isSupported || _permissionRequested) return;
    _permissionRequested = true;
    try {
      await _channel.invokeMethod<bool>('ensurePermission');
    } catch (_) {}
  }

  static Future<void> updateProgress({
    required String title,
    required String body,
    required int progress,
    int max = 100,
    bool indeterminate = false,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('updateProgress', {
        'title': title,
        'body': body,
        'progress': progress,
        'max': max,
        'indeterminate': indeterminate,
      });
    } catch (_) {}
  }

  static Future<void> showComplete({
    required String title,
    required String body,
    bool isError = false,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('showComplete', {
        'title': title,
        'body': body,
        'isError': isError,
      });
    } catch (_) {}
  }

  static Future<void> cancelProgress() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('cancelProgress');
    } catch (_) {}
  }
}
