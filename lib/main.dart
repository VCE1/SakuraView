import 'dart:io';
import 'dart:isolate';
import 'package:logging/logging.dart';

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'dart:ui' as ui;

import 'package:vce1_sakuraview/services/proxy_config.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/android_download_notifier.dart';
import 'package:vce1_sakuraview/providers/windows_download_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/pages/android_page.dart';
import 'package:vce1_sakuraview/pages/windows_page.dart';
import 'package:vce1_sakuraview/widgets/common/download_images_display_widget.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = ui.IsolateNameServer.lookupPortByName('downloader_send_port');
  if (send != null) {
    send.send([id, status, progress]);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(PostHiveModelAdapter());
  await Hive.openBox<PostHiveModel>('downloaded_posts');

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) {
    debugPrint('[${r.level.name}] ${r.loggerName}: ${r.message}');
    if (r.error != null) {
      debugPrint('  => ${r.error}');
    }
  });

  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await FlutterDownloader.initialize(debug: true);
      FlutterDownloader.registerCallback(downloadCallback);
      AndroidDownloadNotifier.markDownloaderInitialized();
    } catch (e) {
      debugPrint('Failed to initialize FlutterDownloader: $e');
    }
  }

  if (Platform.isWindows) {
    doWhenWindowReady(() {
      const initialSize = Size(960, 640);
      appWindow.minSize = const Size(700, 500);
      appWindow.size = initialSize;
      appWindow.alignment = Alignment.center;
      appWindow.show();
    });
  }

  await ProxyConfig.initGlobalHttpOverrides();
  ProxyConfig.testConnection().then((ok) {
    debugPrint('[MAIN] Startup proxy test: ${ok ? "PASS" : "FAIL"}');
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
        ChangeNotifierProvider<BaseDownloadNotifier>(
          create: (_) {
            if (Platform.isAndroid || Platform.isIOS) {
              return AndroidDownloadNotifier();
            } else if (Platform.isWindows) {
              return WindowsDownloadNotifier();
            }
            throw UnsupportedError('Unsupported platform for downloads');
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => RecentTagsNotifier()..load()),
      ],
      child: Consumer2<SiteConfigProvider, ThemeProvider>(
        builder: (context, siteConfig, themeProvider, child) {
          return MaterialApp(
            title: 'vce1.sakuraview',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.theme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: Platform.isWindows
                ? const WindowImageGridPage()
                : const AndroidImageGridPage(),
            routes: {
              '/downloads': (_) => const DownloadedImagesDisplay(),
            },
          );
        },
      ),
    );
  }
}
