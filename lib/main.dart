import 'dart:io';
import 'package:logging/logging.dart';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

import 'package:vce1_sakuraview/services/proxy_config.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/android_download_notifier.dart';
import 'package:vce1_sakuraview/providers/windows_download_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/pages/android_page.dart';
import 'package:vce1_sakuraview/pages/windows_page.dart';
import 'package:vce1_sakuraview/widgets/common/download_images_display_widget.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

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

  if (Platform.isWindows) {
    doWhenWindowReady(() {
      const initialSize = Size(1240, 820);
      appWindow.minSize = const Size(760, 540);
      appWindow.size = initialSize;
      appWindow.alignment = Alignment.center;
      appWindow.title = 'SakuraView';
      appWindow.show();
    });
  }

  await ProxyConfig.initGlobalHttpOverrides();
  ProxyConfig.testConnection().then((ok) {
    debugPrint('[MAIN] Startup proxy test: ${ok ? "PASS" : "FAIL"}');
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const int _activeCacheBytes = 90 << 20; // 90 MiB
  static const int _backgroundCacheBytes = 24 << 20; // 24 MiB

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 250;
    cache.maximumSizeBytes = _activeCacheBytes;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cache = PaintingBinding.instance.imageCache;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // 切到后台时主动释放非活跃解码位图并收紧图片缓存上限，降低 Android LMK 杀后台概率
      cache.clearLiveImages();
      cache.maximumSizeBytes = _backgroundCacheBytes;
    } else if (state == AppLifecycleState.resumed) {
      cache.maximumSizeBytes = _activeCacheBytes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
            title: 'SakuraView',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.theme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: Platform.isWindows
                ? const WindowImageGridPage()
                : const AndroidImageGridPage(),
            onGenerateRoute: (settings) {
              if (settings.name == '/downloads') {
                return SakuraPageRoute(
                  settings: settings,
                  builder: (_) => const DownloadedImagesDisplay(),
                );
              }
              return null;
            },
          );
        },
      ),
    );
  }
}
