import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/android_page.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/quick_search_drawer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_drawer_swipe_region.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';
import 'package:vce1_sakuraview/widgets/drawer_widget.dart';

const List<int> _kTinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class _FakeDownloadNotifier extends BaseDownloadNotifier {
  final List<DownloadedItem> _items;
  final List<AppDownloadTask> _tasks;

  _FakeDownloadNotifier({
    List<DownloadedItem>? items,
    List<AppDownloadTask>? tasks,
  })  : _items = items ?? const [],
        _tasks = tasks ?? const [];

  @override
  bool get isLoadingGallery => false;

  @override
  List<DownloadedItem> get downloadedItems => _items;

  @override
  List<AppDownloadTask> get downloadingTasks => _tasks;

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

class _OfflineSourceAdapter extends ImageSourceAdapter {
  _OfflineSourceAdapter(SourceDescriptor descriptor)
      : super(descriptor: descriptor);

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) =>
      PostHiveModel.fromApiMap(json);

  @override
  Future<PostHiveModel?> getPostDetail(String id) async => null;

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async =>
      List<PostHiveModel>.generate(6, (idx) {
        final id = (query.page - 1) * 6 + idx + 1;
        return PostHiveModel()
          ..id = id
          ..siteName = descriptor.id
          ..tags = 'sakura_hair'
          ..previewUrl = ''
          ..sampleUrl = ''
          ..fileUrl = ''
          ..width = 800
          ..height = 1000
          ..previewWidth = 300
          ..previewHeight = 375
          ..rating = 'safe'
          ..fileExt = 'png';
      });
}

class _OfflineSiteConfigProvider extends SiteConfigProvider {
  late final _OfflineSourceAdapter _adapter =
      _OfflineSourceAdapter(currentSource);

  @override
  ImageSourceAdapter get apiClient => _adapter;

  @override
  ImageSourceAdapter adapterFor(String sourceId) => _adapter;
}

Widget _wrapProviders(
  Widget child, {
  BaseDownloadNotifier? downloadNotifier,
  SiteConfigProvider? siteProvider,
}) {
  return MultiProvider(
    key: ValueKey<Object?>(downloadNotifier),
    providers: [
      ChangeNotifierProvider<SiteConfigProvider>.value(
        value: siteProvider ?? _OfflineSiteConfigProvider(),
      ),
      ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
      if (downloadNotifier != null)
        ChangeNotifierProvider<BaseDownloadNotifier>.value(
          value: downloadNotifier,
        )
      else
        ChangeNotifierProvider<BaseDownloadNotifier>(
          create: (_) => _FakeDownloadNotifier(),
        ),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => RecentTagsNotifier()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'view_original_by_default': false,
    });
  });

  group('Launcher Icon & In-App Cleanliness', () {
    test('Android & iOS/iPadOS AppIcon PNGs exist cleanly and asset removed from pubspec', () {
      const pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      expect(File('assets/icons/sakura_icon.png').existsSync(), isTrue);
      expect(File('lib/widgets/common/sakura_logo_icon.dart').existsSync(), isFalse);

      final pubspecText = File('pubspec.yaml').readAsStringSync();
      expect(pubspecText.contains('sakura_icon.png'), isFalse);

      for (final density in const ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final f = File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
        expect(f.existsSync(), isTrue, reason: 'Missing $density ic_launcher.png');
        final bytes = f.readAsBytesSync();
        expect(bytes.length, greaterThan(100));
        expect(bytes.take(8).toList(), equals(pngMagic));
      }

      const appIconDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final contentsJson =
          jsonDecode(File('$appIconDir/Contents.json').readAsStringSync())
              as Map<String, dynamic>;
      final images = (contentsJson['images'] as List).cast<Map<String, dynamic>>();
      final filenames = images
          .map((e) => e['filename']?.toString())
          .whereType<String>()
          .toSet();
      expect(filenames.length, greaterThanOrEqualTo(15));
      for (final name in filenames) {
        final f = File('$appIconDir/$name');
        expect(f.existsSync(), isTrue, reason: 'Missing iOS AppIcon $name');
        final bytes = f.readAsBytesSync();
        expect(bytes.length, greaterThan(100));
        expect(bytes.take(8).toList(), equals(pngMagic));
      }
    });

    testWidgets('AboutPage and AppDrawer render without SakuraLogoIcon / Image', (tester) async {
      await tester.pumpWidget(_wrapProviders(const AboutPage()));
      await tester.pump();
      expect(find.byIcon(Icons.collections_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(
        _wrapProviders(
          Scaffold(
            body: AppDrawer(
              isSafeMode: false,
              onSafeModeChanged: (_) {},
              onHomeTapped: () {},
              onFavoritesTapped: () {},
              onDownloadsTapped: () {},
              onSearchTapped: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.collections_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('Download Original Quality Tracking & HD Auto-Check', () {
    test('DownloadMetadataHelper & PostHiveModel persist original vs sample download quality', () async {
      final rawPost = <String, dynamic>{
        'id': 7788,
        'site': 'yandere',
        'site_id': 'yandere',
        'file_url': 'https://example.com/images/7788/original.png',
        'sample_url': 'https://example.com/sample/7788/sample.jpg',
        'preview_url': 'https://example.com/preview/7788.jpg',
        'file_ext': 'png',
        'file_size': 4500000,
        'tags': 'sakura_hair',
      };

      final originalTarget = DownloadMetadataHelper.resolveDownloadTarget(
        rawPost,
        DownloadQuality.original,
      );
      expect(originalTarget.url, equals(rawPost['file_url']));
      expect(originalTarget.fileExt, equals('png'));
      expect(originalTarget.postData['downloaded_quality'], equals('original'));
      expect(originalTarget.postData['is_downloaded_original'], isTrue);

      final sampleTarget = DownloadMetadataHelper.resolveDownloadTarget(
        rawPost,
        DownloadQuality.sample,
      );
      expect(sampleTarget.url, equals(rawPost['sample_url']));
      expect(sampleTarget.fileExt, equals('jpg'));
      expect(sampleTarget.postData['downloaded_quality'], equals('sample'));
      expect(sampleTarget.postData['is_downloaded_original'], isFalse);

      // Legacy downloaded item heuristic fallback (no explicit downloadedQuality saved yet)
      expect(
        DownloadMetadataHelper.evaluateDownloadedOriginal(
          downloadedQuality: null,
          filePath: '/downloads/7788.png',
          actualFileSize: 4400000,
          apiFileSize: 4500000,
          fileUrl: rawPost['file_url'] as String,
          sampleUrl: rawPost['sample_url'] as String,
        ),
        isTrue,
      );
      expect(
        DownloadMetadataHelper.evaluateDownloadedOriginal(
          downloadedQuality: null,
          filePath: '/downloads/7788.jpg',
          actualFileSize: 320000,
          apiFileSize: 4500000,
          fileUrl: rawPost['file_url'] as String,
          sampleUrl: rawPost['sample_url'] as String,
        ),
        isFalse,
      );

      // Hive binary persistence round-trip
      final hiveDir = Directory.systemTemp.createTempSync('sakura_hive_hd_test_');
      addTearDown(() async {
        await Hive.close();
        if (hiveDir.existsSync()) {
          hiveDir.deleteSync(recursive: true);
        }
      });
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(PostHiveModelAdapter());
      }

      var box = await Hive.openBox<PostHiveModel>('hd_quality_test_box');
      final origModel = PostHiveModel.fromApiMap(originalTarget.postData);
      final sampleModel = PostHiveModel.fromApiMap(sampleTarget.postData);
      await box.put('orig', origModel);
      await box.put('sample', sampleModel);
      await box.close();

      box = await Hive.openBox<PostHiveModel>('hd_quality_test_box');
      final reloadedOrig = box.get('orig')!;
      final reloadedSample = box.get('sample')!;
      expect(reloadedOrig.downloadedQuality, equals('original'));
      expect(reloadedOrig.toApiMap()['downloaded_quality'], equals('original'));
      expect(reloadedOrig.toApiMap()['is_downloaded_original'], isTrue);
      expect(reloadedSample.downloadedQuality, equals('sample'));
      expect(reloadedSample.toApiMap()['downloaded_quality'], equals('sample'));
      expect(reloadedSample.toApiMap()['is_downloaded_original'], isFalse);
    });

    testWidgets('SakuraPhotoGalleryViewer auto-checks HD for downloaded originals (local & online) and leaves sample unchecked', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sakura_viewer_hd_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final origFile = File('${tempDir.path}/5001.png')..writeAsBytesSync(_kTinyPng);
      final sampleFile = File('${tempDir.path}/5002.png')..writeAsBytesSync(_kTinyPng);

      // 1. Local downloaded original -> frame 1 immediately shows checked HD
      await tester.pumpWidget(
        _wrapProviders(
          SakuraPhotoGalleryViewer(
            key: const ValueKey('local_orig'),
            isLocal: true,
            initialIndex: 0,
            posts: [
              <String, dynamic>{
                'id': 5001,
                'site': 'yandere',
                'site_id': 'yandere',
                'width': 1200,
                'height': 1600,
                'file_ext': 'png',
                'is_local_file': true,
                'local_file_path': origFile.path,
                'downloaded_quality': 'original',
                'is_downloaded_original': true,
                'file_url': origFile.path,
                'sample_url': origFile.path,
                'preview_url': origFile.path,
              },
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('已勾选原图 (HD)'), findsOneWidget);
      expect(find.byIcon(Icons.hd_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // 2. Local downloaded sample -> HD remains unchecked
      await tester.pumpWidget(
        _wrapProviders(
          SakuraPhotoGalleryViewer(
            key: const ValueKey('local_sample'),
            isLocal: true,
            initialIndex: 0,
            posts: [
              <String, dynamic>{
                'id': 5002,
                'site': 'yandere',
                'site_id': 'yandere',
                'width': 1200,
                'height': 1600,
                'file_ext': 'png',
                'is_local_file': true,
                'local_file_path': sampleFile.path,
                'downloaded_quality': 'sample',
                'is_downloaded_original': false,
                'file_url': 'https://example.com/5002_original.png',
                'sample_url': sampleFile.path,
                'preview_url': sampleFile.path,
              },
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('已勾选原图 (HD)'), findsNothing);
      expect(find.byTooltip('加载高清原图'), findsOneWidget);
      expect(find.byIcon(Icons.hd_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      // 3. Online post matching a locally downloaded original -> auto-checks HD automatically
      final matchedNotifier = _FakeDownloadNotifier(
        items: [
          DownloadedItem(
            id: '5001',
            filePath: origFile.path,
            filename: '5001.png',
            creationDate: DateTime(2026, 5, 1),
            siteName: 'yandere',
            downloadedQuality: 'original',
          ),
        ],
      );
      await tester.pumpWidget(
        _wrapProviders(
          SakuraPhotoGalleryViewer(
            key: const ValueKey('online_with_local_orig'),
            isLocal: false,
            initialIndex: 0,
            posts: const [
              <String, dynamic>{
                'id': 5001,
                'site': 'yandere',
                'site_id': 'yandere',
                'width': 1200,
                'height': 1600,
                'file_ext': 'png',
                'file_url': 'https://example.com/5001_original.png',
                'sample_url': 'https://example.com/5001_sample.jpg',
                'preview_url': 'https://example.com/5001_preview.jpg',
              },
            ],
          ),
          downloadNotifier: matchedNotifier,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byTooltip('已勾选原图 (HD)'), findsOneWidget);
      expect(find.byIcon(Icons.hd_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('Left-Side & Right-Side Swipe Gestures', () {
    testWidgets('SakuraDrawerSwipeDetector handles left/right zones and start bounds accurately', (tester) async {
      int leftCount = 0;
      int rightCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SakuraDrawerSwipeDetector(
                minLeftStartWidth: 20,
                maxLeftStartWidth: 100,
                onSwipeRightFromLeft: () => leftCount++,
                onSwipeLeftFromRight: () => rightCount++,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      // Inside left allowed range [20..100] -> triggers onSwipeRightFromLeft
      await tester.flingFrom(const Offset(50, 300), const Offset(120, 0), 800);
      await tester.pump();
      expect(leftCount, 1);

      // Too far right (x=150 > maxLeftStartWidth 100) -> ignored for left callback
      await tester.flingFrom(const Offset(150, 300), const Offset(120, 0), 800);
      await tester.pump();
      expect(leftCount, 1);

      // Too close to edge (x=10 < minLeftStartWidth 20) -> ignored
      await tester.flingFrom(const Offset(10, 300), const Offset(120, 0), 800);
      await tester.pump();
      expect(leftCount, 1);

      // Right half swipe left -> triggers onSwipeLeftFromRight
      await tester.flingFrom(const Offset(340, 300), const Offset(-120, 0), 800);
      await tester.pump();
      expect(rightCount, 1);
    });

    testWidgets('AndroidImageGridPage supports left-side swipe to open AppDrawer across Home, Search, and Favorites', (tester) async {
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_wrapProviders(const AndroidImageGridPage()));
      await tester.pumpAndSettle();

      // Home tab: swipe left-to-right on left half opens AppDrawer
      await tester.flingFrom(const Offset(60, 420), const Offset(180, 0), 900);
      await tester.pumpAndSettle();
      expect(find.byType(AppDrawer), findsOneWidget);

      // Switch to Search tab via AppDrawer
      await tester.tap(find.text('搜索').last);
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.byType(AppDrawer), findsNothing);

      // Search tab: swipe left-to-right opens AppDrawer again
      await tester.flingFrom(const Offset(70, 420), const Offset(180, 0), 900);
      await tester.pumpAndSettle();
      expect(find.byType(AppDrawer), findsOneWidget);

      // Switch to Favorites tab via AppDrawer
      await tester.tap(find.text('收藏').last);
      await tester.pumpAndSettle();
      expect(find.text('我的收藏'), findsOneWidget);

      // Favorites tab: swipe left-to-right opens AppDrawer
      await tester.flingFrom(const Offset(70, 420), const Offset(180, 0), 900);
      await tester.pumpAndSettle();
      expect(find.byType(AppDrawer), findsOneWidget);

      // Close AppDrawer and verify right-half swipe-left opens QuickSearchDrawer
      Navigator.of(tester.element(find.byType(AppDrawer))).pop();
      await tester.pumpAndSettle();
      await tester.flingFrom(const Offset(350, 420), const Offset(-180, 0), 900);
      await tester.pumpAndSettle();
      expect(find.byType(QuickSearchDrawer), findsOneWidget);
    });

    testWidgets('SakuraPageRoute supports left-side swipe-back by default and disables cleanly when enableSwipeBack is false', (tester) async {
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).push(
                      SakuraPageRoute(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Swipeable Child')),
                        ),
                      ),
                    ),
                    child: const Text('Push Swipeable'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).push(
                      SakuraPageRoute(
                        enableSwipeBack: false,
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Locked Viewer')),
                        ),
                      ),
                    ),
                    child: const Text('Push Viewer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swipeable route pops cleanly via left-side swipe
      await tester.tap(find.text('Push Swipeable'));
      await tester.pumpAndSettle();
      expect(find.text('Swipeable Child'), findsOneWidget);
      await tester.flingFrom(const Offset(44, 400), const Offset(160, 0), 900);
      await tester.pumpAndSettle();
      expect(find.text('Swipeable Child'), findsNothing);
      expect(find.text('Push Swipeable'), findsOneWidget);

      // Locked viewer route ignores left-side swipe so PageView gestures stay intact
      await tester.tap(find.text('Push Viewer'));
      await tester.pumpAndSettle();
      expect(find.text('Locked Viewer'), findsOneWidget);
      await tester.flingFrom(const Offset(44, 400), const Offset(160, 0), 900);
      await tester.pumpAndSettle();
      expect(find.text('Locked Viewer'), findsOneWidget);
    });
  });

  group('PostDetailPage Tight Preview Framing & Quiet Notifications', () {
    testWidgets('Portrait PostDetailPage uses 8dp side margins without outer gray letterbox frame and suppresses favorite snackbar', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tempDir = Directory.systemTemp.createTempSync('sakura_detail_ui_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final sampleFile = File('${tempDir.path}/3030.png')..writeAsBytesSync(_kTinyPng);

      await tester.pumpWidget(
        _wrapProviders(
          PostDetailPage(
            siteName: 'yandere',
            postData: {
              'id': 3030,
              'site': 'yandere',
              'site_id': 'yandere',
              'width': 800,
              'height': 800,
              'file_ext': 'png',
              'rating': 's',
              'tags': 'sakura_hair',
              'general_tags': const ['sakura_hair'],
              'is_local_file': true,
              'local_file_path': sampleFile.path,
              'file_url': sampleFile.path,
              'sample_url': sampleFile.path,
              'preview_url': sampleFile.path,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Portrait scroll container uses 8dp horizontal margins
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollView.padding, equals(const EdgeInsets.fromLTRB(8, 6, 8, 28)));

      // Preview ClipRRect matches square 1:1 image proportion without full-width horizontal stretch bars
      final heroClip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(heroClip.borderRadius, equals(BorderRadius.circular(12)));
      final heroRect = tester.getRect(find.byType(ClipRRect).first);
      expect((heroRect.width - heroRect.height).abs(), lessThan(2.0));
      expect(heroRect.left, closeTo(8.0, 2.0));

      // Tapping favorite does NOT spawn any intrusive SnackBar
      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
