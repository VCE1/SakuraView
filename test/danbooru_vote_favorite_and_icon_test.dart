import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/exceptions/api_exception.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';

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

  group('SourceCapabilities & DanbooruSourceAdapter voting/favorites', () {
    test('BuiltInSources declares supportsVoting true for danbooru and false for yandere', () {
      final danbooru =
          BuiltInSources.catalog.firstWhere((s) => s.id == 'danbooru');
      final yandere =
          BuiltInSources.catalog.firstWhere((s) => s.id == 'yandere');

      expect(danbooru.capabilities.supportsVoting, isTrue);
      expect(danbooru.capabilities.supportsCloudFavorites, isTrue);
      expect(yandere.capabilities.supportsVoting, isFalse);

      final roundTripped = SourceCapabilities.fromJson(
        danbooru.capabilities.toJson(),
      );
      expect(roundTripped.supportsVoting, isTrue);
      expect(roundTripped.supportsCloudFavorites, isTrue);
    });

    test('parsePostVotePayload handles Map, List, deleted, and invalid inputs', () {
      expect(DanbooruSourceAdapter.parsePostVotePayload({'score': 1}), 1);
      expect(DanbooruSourceAdapter.parsePostVotePayload({'score': -1}), -1);
      expect(
        DanbooruSourceAdapter.parsePostVotePayload({
          'score': 1,
          'is_deleted': true,
        }),
        0,
      );
      expect(
        DanbooruSourceAdapter.parsePostVotePayload([
          {'score': 1, 'is_deleted': true},
          {'score': -1, 'is_deleted': false},
        ]),
        -1,
      );
      expect(
        DanbooruSourceAdapter.parsePostVotePayload([
          {'score': 1, 'is_deleted': true},
        ]),
        0,
      );
      expect(DanbooruSourceAdapter.parsePostVotePayload(const []), 0);
      expect(DanbooruSourceAdapter.parsePostVotePayload(null), 0);
      expect(DanbooruSourceAdapter.parsePostVotePayload({}), 0);
    });

    test('DanbooruSourceAdapter requires write credentials when unauthenticated', () async {
      final danbooruDesc =
          BuiltInSources.catalog.firstWhere((s) => s.id == 'danbooru');
      final unauthAdapter = DanbooruSourceAdapter(descriptor: danbooruDesc);

      expect(unauthAdapter.hasWriteCredentials, isFalse);
      expect(await unauthAdapter.fetchPostVoteState('12345'), isNull);
      await expectLater(
        unauthAdapter.votePost('12345', 1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      await expectLater(
        unauthAdapter.unvotePost('12345'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      await expectLater(
        unauthAdapter.addCloudFavorite('12345'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      await expectLater(
        unauthAdapter.removeCloudFavorite('12345'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('DanbooruSourceAdapter votePost, unvotePost, and cloud favorites hit Danbooru endpoints', () async {
      final prevHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevHttpOverrides);

      int currentPostScore = 10;
      int currentUserVote = 0;
      final recordedRequests = <String>[];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        final path = req.uri.path;
        recordedRequests.add('${req.method} $path');
        await utf8.decoder.bind(req).join();

        if (req.method == 'GET' && path == '/profile.json') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 999, 'name': 'tester'}));
        } else if (req.method == 'GET' && path == '/post_votes.json') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                currentUserVote == 0
                    ? <dynamic>[]
                    : [
                        {'post_id': 12345, 'score': currentUserVote},
                      ],
              ),
            );
        } else if (req.method == 'GET' && path == '/posts/12345.json') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'id': 12345, 'score': currentPostScore}));
        } else if (req.method == 'POST' && path == '/posts/12345/votes.json') {
          final rawScore =
              int.tryParse(req.uri.queryParameters['score'] ?? '') ?? 1;
          currentPostScore += rawScore - currentUserVote;
          currentUserVote = rawScore;
          req.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'post_id': 12345, 'score': currentUserVote}));
        } else if (req.method == 'DELETE' && path == '/posts/12345/votes.json') {
          currentPostScore -= currentUserVote;
          currentUserVote = 0;
          req.response.statusCode = HttpStatus.noContent;
        } else if (req.method == 'POST' && path == '/favorites.json') {
          req.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'post_id': 12345}));
        } else if (req.method == 'DELETE' && path == '/favorites/12345.json') {
          req.response.statusCode = HttpStatus.noContent;
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });

      final localDescriptor = SourceDescriptor(
        id: 'danbooru',
        name: 'Danbooru Test',
        engine: SourceEngineType.danbooru,
        baseUrl: 'http://127.0.0.1:${server.port}',
        authType: SourceAuthType.userApiKey,
        capabilities: const SourceCapabilities(
          supportsCloudFavorites: true,
          supportsVoting: true,
        ),
      );
      final adapter = DanbooruSourceAdapter(
        descriptor: localDescriptor,
        credentials: const SourceAccountCredentials(
          username: 'tester',
          apiKey: 'secret_key',
        ),
      );

      expect(adapter.hasWriteCredentials, isTrue);

      final voteUp = await adapter.votePost('12345', 1);
      expect(voteUp, isNotNull);
      expect(voteUp!.userVote, 1);
      expect(voteUp.postScore, 11);

      final fetched = await adapter.fetchPostVoteState('12345');
      expect(fetched?.userVote, 1);

      final unvoted = await adapter.unvotePost('12345');
      expect(unvoted, isNotNull);
      expect(unvoted!.userVote, 0);
      expect(unvoted.postScore, 10);

      expect(await adapter.addCloudFavorite('12345'), isTrue);
      expect(await adapter.removeCloudFavorite('12345'), isTrue);

      expect(recordedRequests, contains('POST /posts/12345/votes.json'));
      expect(recordedRequests, contains('DELETE /posts/12345/votes.json'));
      expect(recordedRequests, contains('POST /favorites.json'));
      expect(recordedRequests, contains('DELETE /favorites/12345.json'));
    });
  });

  group('FavoritesNotifier cloud sync & SakuraLogoIcon/PostDetailPage UI', () {
    test('toggleFavoriteWithCloudSync updates local favorites and syncs Danbooru cloud', () async {
      final prevHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevHttpOverrides);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final remoteFavs = <String>{};
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        if (req.method == 'POST' && req.uri.path == '/favorites.json') {
          remoteFavs.add(req.uri.queryParameters['post_id'] ?? '555');
          req.response
            ..statusCode = HttpStatus.created
            ..write('{}');
        } else if (req.method == 'DELETE' &&
            req.uri.path == '/favorites/555.json') {
          remoteFavs.remove('555');
          req.response.statusCode = HttpStatus.noContent;
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });

      final adapter = DanbooruSourceAdapter(
        descriptor: SourceDescriptor(
          id: 'danbooru',
          name: 'Danbooru',
          engine: SourceEngineType.danbooru,
          baseUrl: 'http://127.0.0.1:${server.port}',
          capabilities: const SourceCapabilities(supportsCloudFavorites: true),
        ),
        credentials: const SourceAccountCredentials(
          username: 'tester',
          apiKey: 'secret_key',
        ),
      );

      final notifier = FavoritesNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final post = <String, dynamic>{
        'id': 555,
        'site': 'danbooru',
        'site_id': 'danbooru',
        'preview_url': 'https://example.com/555.jpg',
        'file_url': 'https://example.com/555.jpg',
      };

      final addResult = await notifier.toggleFavoriteWithCloudSync(
        post,
        siteName: 'danbooru',
        adapter: adapter,
      );
      expect(addResult.isFavorite, isTrue);
      expect(addResult.cloudSynced, isTrue);
      expect(notifier.isFavorite('555'), isTrue);
      expect(remoteFavs, contains('555'));

      final removeResult = await notifier.toggleFavoriteWithCloudSync(
        post,
        siteName: 'danbooru',
        adapter: adapter,
      );
      expect(removeResult.isFavorite, isFalse);
      expect(removeResult.cloudSynced, isTrue);
      expect(notifier.isFavorite('555'), isFalse);
      expect(remoteFavs, isEmpty);
    });

    testWidgets(
        'AboutPage uses Material icon without SakuraLogoIcon and PostDetailPage shows Danbooru vote strip only for Danbooru',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutPage(),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.collections_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);

      final siteProvider = SiteConfigProvider();
      final favNotifier = FavoritesNotifier();

      // Danbooru post renders vote controls & score
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SiteConfigProvider>.value(value: siteProvider),
            ChangeNotifierProvider<FavoritesNotifier>.value(value: favNotifier),
            ChangeNotifierProvider<BaseDownloadNotifier>(
              create: (_) => _TestDownloadNotifier(),
            ),
          ],
          child: const MaterialApp(
            home: PostDetailPage(
              key: ValueKey('post_danbooru'),
              siteName: 'danbooru',
              postData: {
                'id': 12345,
                'site': 'danbooru',
                'site_id': 'danbooru',
                'score': 42,
                'fav_count': 7,
                'tags': 'sakura_hair',
                'general_tags': ['sakura_hair'],
                'rating': 'g',
                'width': 800,
                'height': 600,
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('点赞 +1'), findsOneWidget);
      expect(find.text('点踩 -1'), findsOneWidget);
      expect(find.text('42'), findsWidgets);

      // Yandere post does NOT render Danbooru vote controls
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SiteConfigProvider>.value(value: siteProvider),
            ChangeNotifierProvider<FavoritesNotifier>.value(value: favNotifier),
            ChangeNotifierProvider<BaseDownloadNotifier>(
              create: (_) => _TestDownloadNotifier(),
            ),
          ],
          child: const MaterialApp(
            home: PostDetailPage(
              key: ValueKey('post_yandere'),
              siteName: 'yandere',
              postData: {
                'id': 888,
                'site': 'yandere',
                'site_id': 'yandere',
                'score': 9,
                'tags': 'sakura_hair',
                'general_tags': ['sakura_hair'],
                'rating': 's',
                'width': 800,
                'height': 600,
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('点赞 +1'), findsNothing);
      expect(find.text('点踩 -1'), findsNothing);
    });
  });
}
