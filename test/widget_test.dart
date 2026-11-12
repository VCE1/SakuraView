import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/api/danbooru_api_client.dart';
import 'package:vce1_sakuraview/api/yandere_api_client.dart';
import 'package:vce1_sakuraview/api/zerochan_api_client.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/services/proxy_config.dart';
import 'package:vce1_sakuraview/utils/proxy_settings_page.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Google-Compliant Proxy System Tests', () {
    test('Default mode is ProxyMode.system (accepts Wi-Fi / OS proxy)', () async {
      final mode = await ProxyConfig.getProxyMode();
      expect(mode, ProxyMode.system);
      expect(await ProxyConfig.isProxyEnabled(), isTrue);
    });

    test('ProxyMode.system routes via mounted Wi-Fi / system proxy and honors bypass list', () {
      const wifiProxy = SystemProxyInfo(
        host: '192.168.6.233',
        port: 7890,
        nonProxyHosts: ['*.local', '192.168.6.*', 'internal.corp'],
        source: 'Android Wi-Fi / System Proxy',
      );

      final extDirective = ProxyConfig.resolveProxyDirectiveForUri(
        Uri.parse('https://yande.re/post.json'),
        mode: ProxyMode.system,
        manualAddress: '127.0.0.1:7890',
        systemProxy: wifiProxy,
      );
      expect(extDirective, 'PROXY 192.168.6.233:7890; DIRECT');

      // Loopback and nonProxyHosts must bypass proxy (DIRECT)
      for (final bypassUrl in [
        'http://localhost:8080/api',
        'http://127.0.0.1:3000/test',
        'http://[::1]:8080/test',
        'http://nas.local/files',
        'http://192.168.6.100/admin',
      ]) {
        final dir = ProxyConfig.resolveProxyDirectiveForUri(
          Uri.parse(bypassUrl),
          mode: ProxyMode.system,
          manualAddress: '127.0.0.1:7890',
          systemProxy: wifiProxy,
        );
        expect(dir, 'DIRECT', reason: 'Expected $bypassUrl to bypass proxy');
      }
    });

    test('ProxyMode.manual validates, normalizes, and routes via manual proxy', () async {
      expect(ProxyConfig.normalizeProxyAddress(' http://192.168.6.233：7890/ '), '192.168.6.233:7890');
      expect(ProxyConfig.isValidProxyAddress('192.168.6.233:7890'), isTrue);
      expect(ProxyConfig.isValidProxyAddress('invalid_address'), isFalse);
      expect(ProxyConfig.isValidProxyAddress('127.0.0.1:99999'), isFalse);

      await ProxyConfig.saveProxyAddress('http://10.0.2.2：7890');
      await ProxyConfig.saveProxyMode(ProxyMode.manual);

      expect(await ProxyConfig.getProxyMode(), ProxyMode.manual);
      expect(await ProxyConfig.getProxyAddress(), '10.0.2.2:7890');

      final directive = ProxyConfig.resolveProxyDirectiveForUri(
        Uri.parse('https://danbooru.donmai.us/posts.json'),
        mode: ProxyMode.manual,
        manualAddress: '10.0.2.2:7890',
      );
      expect(directive, 'PROXY 10.0.2.2:7890; DIRECT');
    });

    test('ProxyMode.none forces DIRECT connection', () async {
      await ProxyConfig.saveProxyMode(ProxyMode.none);
      expect(await ProxyConfig.isProxyEnabled(), isFalse);

      final zerochanDirect = ProxyConfig.resolveProxyDirectiveForUri(
        Uri.parse('https://www.zerochan.net/?json'),
        mode: ProxyMode.none,
        manualAddress: '192.168.6.233:7890',
        systemProxy: const SystemProxyInfo(host: '192.168.6.233', port: 7890),
      );
      expect(zerochanDirect, 'DIRECT');
    });

    test('Danbooru v2 JSON and Zerochan malformed JSON wrapper parse accurately', () {
      final danbooruClient = DanbooruApiClient();
      final danbooruV2 = <String, dynamic>{
        'id': 12527336,
        'created_at': '2026-11-12T01:53:04.077-05:00',
        'uploader_id': 1314269,
        'score': 42,
        'source': 'https://www.bilibili.com/opus/1269705586735316997',
        'rating': 'g',
        'image_width': 2480,
        'image_height': 3820,
        'tag_string': 'absurdres highres youguo_naberu',
        'tag_string_artist': 'youguo_naberu',
        'file_ext': 'jpg',
        'file_size': 1321127,
        'has_children': false,
        'file_url': 'https://cdn.donmai.us/original/b5/5f/b55fae4c2a8f3ca9501867dbeb2f3784.jpg',
        'large_file_url': 'https://cdn.donmai.us/sample/b5/5f/sample-b55fae4c2a8f3ca9501867dbeb2f3784.jpg',
        'preview_file_url': 'https://cdn.donmai.us/180x180/b5/5f/b55fae4c2a8f3ca9501867dbeb2f3784.jpg',
      };
      final dp = danbooruClient.parsePost(danbooruV2);
      expect(dp.id, 12527336);
      expect(dp.author, 'youguo_naberu');
      expect(dp.fileUrl, contains('cdn.donmai.us/original'));
      expect(dp.sampleUrl, contains('cdn.donmai.us/sample'));
      expect(dp.previewUrl, contains('cdn.donmai.us/180x180'));
      expect(dp.createdAt, isNotNull);
      expect(dp.createdAt, greaterThan(1700000000));

      const rawZerochanBody = '''
{
{
    "items": [
        {
            "id": "4735953",
            "width": "914",
            "height": "1400",
            "md5": "ae8e6f0d5efdacb06e6490855f1ff9ad",
            "thumbnail": "https://s3.zerochan.net/240/03/19/4735953.avif",
            "source": "https://www.pixiv.net/en/artworks/151952711",
            "tag": "Benio (Dontsugel)",
            "tags": [
                "Female",
                "Genshin Impact",
                "Solo"
            ]
        }
    ]
}<p id="browse-filters">HTML trailing noise</p>}''';

      final extracted = ZerochanApiClient.extractZerochanJson(rawZerochanBody);
      expect(extracted, isNotNull);
      final items = extracted!['items'] as List<dynamic>;
      expect(items.length, 1);

      final zcClient = ZerochanApiClient();
      final zp = zcClient.parsePost(items.first as Map<String, dynamic>);
      expect(zp.id, 4735953);
      expect(zp.previewUrl, 'https://s3.zerochan.net/240/03/19/4735953.jpg');
      expect(zp.sampleUrl, 'https://s1.zerochan.net/600/03/19/4735953.jpg');
      expect(zp.tags, 'Female Genshin_Impact Solo');
    });

    test('Global SakuraHttpOverrides installs cleanly', () async {
      await ProxyConfig.initGlobalHttpOverrides();
      expect(HttpOverrides.current, isA<SakuraHttpOverrides>());
    });
  });

  group('Minimum Software Benchmark Suite', () {
    test('Benchmark 1: Proxy PAC directive resolution throughput (10,000 ops)', () {
      const wifiProxy = SystemProxyInfo(
        host: '192.168.6.233',
        port: 7890,
        nonProxyHosts: ['localhost', '127.0.0.1', '::1', '192.168.6.*', '*.local'],
      );
      final targetUri = Uri.parse('https://yande.re/post.json?limit=40&page=1');

      final sw = Stopwatch()..start();
      const iterations = 10000;
      for (int i = 0; i < iterations; i++) {
        ProxyConfig.resolveProxyDirectiveForUri(
          targetUri,
          mode: ProxyMode.system,
          manualAddress: '192.168.6.233:7890',
          systemProxy: wifiProxy,
        );
      }
      sw.stop();

      final totalMs = sw.elapsedMilliseconds;
      final usPerOp = (sw.elapsedMicroseconds / iterations).toStringAsFixed(2);
      debugPrint('[BENCHMARK] Proxy resolution: $iterations ops in ${totalMs}ms ($usPerOp us/op)');
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('Benchmark 2: Multi-site Post JSON parsing & Hive model conversion (3,000 ops)', () {
      final yandereClient = YandereApiClient();
      final danbooruClient = DanbooruApiClient();
      final zerochanClient = ZerochanApiClient();

      final yandereJson = <String, dynamic>{
        'id': 100001,
        'tags': 'sakura_blossom landscape sky_clouds',
        'author': 'vce1',
        'creator_id': 42,
        'source': 'https://www.pixiv.net/artworks/12345',
        'file_size': 2097152,
        'created_at': 1710000000,
        'rating': 's',
        'score': 128,
        'width': 1920,
        'height': 1080,
        'preview_url': 'https://yande.re/data/preview/100001.jpg',
        'sample_url': 'https://yande.re/data/sample/100001.jpg',
        'file_url': 'https://yande.re/data/image/100001.png',
        'file_ext': 'png',
        'has_children': false,
      };

      final danbooruJson = <String, dynamic>{
        'id': 200002,
        'tag_string': '1girl solo cherry_blossoms',
        'uploader': {'name': 'danbooru_user'},
        'uploader_id': 99,
        'source': 'https://twitter.com/example/status/1',
        'created_at': 1710000000,
        'rating': 'g',
        'score': {'up': 64, 'down': -2, 'total': 62},
        'image_width': 2400,
        'image_height': 1600,
        'file': {'size': 3145728, 'url': 'https://cdn.donmai.us/original/200002.jpg', 'ext': 'jpg'},
        'preview': {'url': 'https://cdn.donmai.us/preview/200002.jpg'},
        'large_file': {'url': 'https://cdn.donmai.us/sample/200002.jpg'},
        'has_children': true,
      };

      final zerochanJson = <String, dynamic>{
        'id': 300003,
        'tags': 'Anime, Sakura',
        'uploader': 'zero_user',
        'content': 'Safe',
        'score': 45,
        'width': 1600,
        'height': 1200,
        'thumb': 'https://s3.zerochan.net/300003.240.jpg',
        'full': 'https://static.zerochan.net/300003.full.jpg',
      };

      final sw = Stopwatch()..start();
      const batches = 1000;
      for (int i = 0; i < batches; i++) {
        final p1 = yandereClient.parsePost(yandereJson);
        final p2 = danbooruClient.parsePost(danbooruJson);
        final p3 = zerochanClient.parsePost(zerochanJson);

        final map1 = p1.toApiMap();
        PostHiveModel.fromApiMap(map1);
        expect(p2.score, 64);
        expect(p3.id, 300003);
      }
      sw.stop();

      final totalOps = batches * 3;
      final usPerOp = (sw.elapsedMicroseconds / totalOps).toStringAsFixed(2);
      debugPrint('[BENCHMARK] Multi-site model parse+roundtrip: $totalOps ops in ${sw.elapsedMilliseconds}ms ($usPerOp us/op)');
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    testWidgets('Benchmark 3: ProxySettingsPage UI render & mode switching', (WidgetTester tester) async {
      final sw = Stopwatch()..start();
      await tester.pumpWidget(
        const MaterialApp(
          home: ProxySettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      sw.stop();

      debugPrint('[BENCHMARK] ProxySettingsPage initial render & settle: ${sw.elapsedMilliseconds}ms');

      expect(find.text('跟随系统代理 (System Proxy)'), findsOneWidget);
      expect(find.text('自定义代理 (Custom HTTP Proxy)'), findsOneWidget);
      expect(find.text('直连模式 (Direct Connection)'), findsOneWidget);

      // Switch to Manual Proxy mode and verify input field appears
      await tester.tap(find.text('自定义代理 (Custom HTTP Proxy)'));
      await tester.pumpAndSettle();
      expect(find.text('自定义 HTTP 代理服务器'), findsOneWidget);
      expect(find.text('127.0.0.1:7890'), findsWidgets);

      // Switch to Direct Connection mode
      await tester.tap(find.text('直连模式 (Direct Connection)'));
      await tester.pumpAndSettle();
      expect(find.text('自定义 HTTP 代理服务器'), findsNothing);
    });

    test('Benchmark 4: ViewerFormatUtils & Metadata parsing throughput (10,000 ops)', () {
      final sw = Stopwatch()..start();
      for (int i = 1; i <= 10000; i++) {
        final fs = ViewerFormatUtils.fileSize(i * 1024 * 512);
        final res = ViewerFormatUtils.resolution(1920 + i, 1080 + i);
        final (rating, _) = ViewerFormatUtils.parseRating(i % 3 == 0 ? 's' : (i % 3 == 1 ? 'q' : 'e'));
        assert(fs.isNotEmpty);
        assert(res.isNotEmpty);
        assert(rating.isNotEmpty);
      }
      sw.stop();
      debugPrint('[BENCHMARK] Viewer metadata parse: 10000 ops in ${sw.elapsedMilliseconds}ms (${(sw.elapsedMicroseconds / 10000).toStringAsFixed(2)} us/op)');
      expect(ViewerFormatUtils.fileSize(10485760), '10.0 MB');
      expect(ViewerFormatUtils.resolution(3840, 2160), '3840 × 2160');
      final (labelSafe, _) = ViewerFormatUtils.parseRating('safe');
      expect(labelSafe, 'Safe 全年龄');
    });
  });
}
