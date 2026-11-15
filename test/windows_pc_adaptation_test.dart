import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/pages/windows_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/favorite_display_widget.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';

class _TestDownloadNotifier extends BaseDownloadNotifier {
  @override
  bool get isLoadingGallery => false;

  @override
  List<DownloadedItem> get downloadedItems => const [];

  @override
  List<AppDownloadTask> get downloadingTasks => const [];

  @override
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData) async =>
      EnqueueResult.success;

  @override
  Future<void> deleteDownloadedItem(DownloadedItem item) async {}

  @override
  Future<void> scanForDownloadedImages() async {}

  @override
  void setupPhotoManagerListener() {}

  @override
  Future<void> pauseDownload(AppDownloadTask task) async {}

  @override
  Future<void> resumeDownload(AppDownloadTask task) async {}

  @override
  Future<void> cancelDownload(AppDownloadTask task) async {}

  @override
  Future<void> retryDownload(AppDownloadTask task) async {}

  @override
  Future<void> removeTask(AppDownloadTask task) async {}

  @override
  Future<void> pauseAllDownloads() async {}

  @override
  Future<void> cancelAllDownloads() async {}

  @override
  Future<void> refreshTasks() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrapProviders(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => RecentTagsNotifier()),
        ChangeNotifierProvider<BaseDownloadNotifier>(
          create: (_) => _TestDownloadNotifier(),
        ),
      ],
      child: MaterialApp(
        routes: {
          '/downloads': (_) => const Scaffold(body: Text('DownloadsRoute')),
        },
        home: child,
      ),
    );
  }

  group('Windows & PC adaptation tests', () {
    test('app_icon.ico exists and has valid multi-resolution ICO header', () {
      final file = File('windows/runner/resources/app_icon.ico');
      expect(file.existsSync(), isTrue);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(10000));
      // ICO header: reserved=0x0000, type=0x0001, count >= 5
      expect(bytes.sublist(0, 4), equals([0x00, 0x00, 0x01, 0x00]));
      final count = bytes[4] | (bytes[5] << 8);
      expect(count, greaterThanOrEqualTo(5));
    });

    testWidgets(
      'WindowImageGridPage adapts NavigationRail on wide screens, hides it on narrow screens, and handles desktop shortcuts',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(wrapProviders(const WindowImageGridPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byTooltip('刷新 (F5)'), findsOneWidget);
        expect(find.byTooltip('快速搜索预设'), findsOneWidget);

        // Switch to Favorites tab via NavigationRail
        await tester.tap(find.text('收藏'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(FavoriteDisplayWidget), findsOneWidget);
        expect(find.text('本地 (0)'), findsOneWidget);

        // Ctrl+F jumps to Search view
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(SearchPage), findsOneWidget);

        // Shrink width below breakpoint -> NavigationRail hides
        tester.view.physicalSize = const Size(780, 700);
        await tester.pumpWidget(wrapProviders(const WindowImageGridPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(NavigationRail), findsNothing);
      },
    );

    testWidgets('SakuraPostCard exposes click cursor and handles mouse hover', (
      tester,
    ) async {
      final post = <String, dynamic>{
        'id': 42,
        'site': 'yandere',
        'preview_url': '',
        'width': 800,
        'height': 1000,
        'rating': 's',
      };
      await tester.pumpWidget(
        wrapProviders(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: SakuraPostCard(
                  item: post,
                  cacheWidth: 300,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final mouseRegion = tester.widget<MouseRegion>(
        find
            .descendant(
              of: find.byType(SakuraPostCard),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(mouseRegion.cursor, SystemMouseCursors.click);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SakuraPostCard)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'SakuraPhotoGalleryViewer handles desktop zoom & HD keys while leaving Space unconsumed',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('sakuraview_win_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final img = File('${tempDir.path}/1.png');
        img.writeAsBytesSync(const <int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82,
        ]);

        final post = <String, dynamic>{
          'id': 7001,
          'site': 'yandere',
          'site_id': 'yandere',
          'file_ext': 'png',
          'is_local_file': true,
          'local_file_path': img.path,
          'file_url': img.path,
          'sample_url': img.path,
          'preview_url': img.path,
        };

        await tester.pumpWidget(
          wrapProviders(
            SakuraPhotoGalleryViewer(
              posts: [post],
              initialIndex: 0,
              isLocal: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(PhotoViewGallery), findsOneWidget);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.equal), isTrue);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.minus), isTrue);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit0), isTrue);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyH), isTrue);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse);
      },
    );
  });
}
