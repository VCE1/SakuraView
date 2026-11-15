import 'package:vce1_sakuraview/providers/pooled_download_notifier.dart';

/// Windows 平台下载管理器：复用跨平台高速并发连接池下载引擎。
class WindowsDownloadNotifier extends PooledDownloadNotifier {
  WindowsDownloadNotifier()
      : super(
          loggerName: 'WindowsDownloadNotifier',
          enableNotifications: false,
        );
}
