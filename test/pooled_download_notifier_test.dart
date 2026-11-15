import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/providers/pooled_download_notifier.dart';
import 'package:vce1_sakuraview/services/download_notification_service.dart';

class _HangingMediaScannerNotifier extends PooledDownloadNotifier {
  final Completer<void> mediaScannerStarted = Completer<void>();

  _HangingMediaScannerNotifier({
    required super.downloadPathResolver,
  }) : super(
          enableNotifications: true,
          scanOnInit: false,
          chunkInactivityTimeout: const Duration(milliseconds: 250),
        );

  @override
  Future<void> onFileSaved(String fullPath) async {
    if (!mediaScannerStarted.isCompleted) {
      mediaScannerStarted.complete();
    }
    // 模拟 Android MediaScannerConnection.scanFile 永不回调
    await Completer<void>().future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notifChannel = MethodChannel('com.sakuraview.dev/download_notifications');
  final List<MethodCall> notifCalls = [];

  setUpAll(() {
    HttpOverrides.global = null;
  });

  setUp(() {
    DownloadNotificationService.debugOverrideIsSupported = true;
    SharedPreferences.setMockInitialValues({
      'proxy_mode': 'direct',
    });
    notifCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (call) async {
      notifCalls.add(call);
      if (call.method == 'ensurePermission') return true;
      return true;
    });
  });

  tearDown(() {
    DownloadNotificationService.debugOverrideIsSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, null);
  });

  group('PooledDownloadNotifier completion & stall recovery', () {
    test('completes queue and notification immediately even if onFileSaved hangs',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_hang_');
      final payload = List<int>.generate(4096, (i) => i % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });

      final notifier = _HangingMediaScannerNotifier(
        downloadPathResolver: () async => tempDir.path,
      );
      addTearDown(notifier.dispose);

      final url = 'http://127.0.0.1:${server.port}/101.jpg';
      final result = await notifier.enqueueDownload({
        'id': 101,
        'site_id': 'danbooru',
        'file_url': url,
        'file_ext': 'jpg',
      });
      expect(result.name, 'success');

      // 等待队列清空与完成通知，不应被永不返回的新增媒体扫描阻塞
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (notifier.downloadingTasks.isNotEmpty ||
          !notifCalls.any((c) => c.method == 'showComplete')) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Download stayed stuck despite completed HTTP transfer');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(notifier.downloadingTasks, isEmpty);
      expect(notifier.downloadedItems.length, 1);
      expect(
        await File('${tempDir.path}${Platform.pathSeparator}101.jpg').length(),
        payload.length,
      );
      final completeCall =
          notifCalls.lastWhere((c) => c.method == 'showComplete');
      expect((completeCall.arguments as Map)['title'], '下载完成');
    });

    test('recovers from 99% stream stall via inactivity timeout and retries cleanly',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_stall_');
      final payload = List<int>.generate(2000, (i) => (i * 7) % 256);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int requests = 0;

      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      server.listen((req) async {
        requests++;
        if (requests == 1) {
          // 第一次请求发送 99%（1980 字节）后挂死不关闭连接
          req.response.statusCode = HttpStatus.ok;
          req.response.contentLength = payload.length;
          req.response.add(payload.sublist(0, 1980));
          await req.response.flush();
          // 保持连接挂起以触发 chunkInactivityTimeout
          return;
        }
        // 重试请求（可能携带 Range）正常返回剩余或完整内容
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range != null && range.startsWith('bytes=')) {
          final start = int.parse(
            range.replaceFirst('bytes=', '').split('-').first,
          );
          final slice = payload.sublist(start);
          req.response.statusCode = HttpStatus.partialContent;
          req.response.contentLength = slice.length;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${payload.length - 1}/${payload.length}',
          );
          req.response.add(slice);
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.contentLength = payload.length;
          req.response.add(payload);
          await req.response.close();
        }
      });

      final notifier = PooledDownloadNotifier(
        enableNotifications: true,
        scanOnInit: false,
        downloadPathResolver: () async => tempDir.path,
        chunkInactivityTimeout: const Duration(milliseconds: 220),
      );
      addTearDown(notifier.dispose);

      await notifier.enqueueDownload({
        'id': 102,
        'site_id': 'danbooru',
        'file_url': 'http://127.0.0.1:${server.port}/102.jpg',
        'file_ext': 'jpg',
      });

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.downloadingTasks.isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Download stalled at 99% without retrying');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(requests, greaterThanOrEqualTo(2));
      expect(notifier.downloadedItems.length, 1);
      final savedBytes =
          await File('${tempDir.path}${Platform.pathSeparator}102.jpg')
              .readAsBytes();
      expect(savedBytes, payload);
      expect(notifCalls.any((c) => c.method == 'showComplete'), isTrue);
    });

    test('rejects premature truncated EOF at 98% and retries to 100% integrity',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_eof_');
      final payload = List<int>.generate(1000, (i) => i % 256);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int attempts = 0;

      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      server.listen((req) async {
        attempts++;
        if (attempts == 1) {
          // 声明 1000 字节但发到 98%（980 字节）即强制断流
          final socket = await req.response.detachSocket();
          socket.add(
            'HTTP/1.1 200 OK\r\nContent-Length: ${payload.length}\r\nConnection: close\r\n\r\n'
                .codeUnits,
          );
          socket.add(payload.sublist(0, 980));
          await socket.flush();
          await socket.close();
          return;
        }
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });

      final notifier = PooledDownloadNotifier(
        enableNotifications: true,
        scanOnInit: false,
        downloadPathResolver: () async => tempDir.path,
        chunkInactivityTimeout: const Duration(milliseconds: 250),
      );
      addTearDown(notifier.dispose);

      await notifier.enqueueDownload({
        'id': 103,
        'site_id': 'danbooru',
        'file_url': 'http://127.0.0.1:${server.port}/103.png',
        'file_ext': 'png',
      });

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.downloadingTasks.isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Truncated download did not finish retrying');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(attempts, greaterThanOrEqualTo(2));
      final savedBytes =
          await File('${tempDir.path}${Platform.pathSeparator}103.png')
              .readAsBytes();
      expect(savedBytes, payload);
    });

    test('batch download emits single completion after all items finish',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_batch_');
      final payload = List<int>.generate(512, (i) => i % 200);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });

      final notifier = PooledDownloadNotifier(
        enableNotifications: true,
        scanOnInit: false,
        downloadPathResolver: () async => tempDir.path,
      );
      addTearDown(notifier.dispose);

      final posts = List.generate(
        6,
        (idx) => {
          'id': 200 + idx,
          'site_id': 'danbooru',
          'file_url': 'http://127.0.0.1:${server.port}/${200 + idx}.jpg',
          'file_ext': 'jpg',
        },
      );

      final summary = await notifier.enqueueBatchDownload(posts);
      expect(summary.added, 6);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.downloadingTasks.isNotEmpty ||
          notifier.downloadedItems.length < 6) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'Batch stalled: remaining=${notifier.downloadingTasks.length}, '
            'done=${notifier.downloadedItems.length}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final completeCalls =
          notifCalls.where((c) => c.method == 'showComplete').toList();
      expect(completeCalls.length, 1);
      expect(
        (completeCalls.first.arguments as Map)['body'],
        '已成功保存 6 项作品到本地图库',
      );
    });

    test('completes at 100% via EOF grace when server keeps socket open after Content-Length',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_eof_');
      final payload = List<int>.generate(4096, (i) => i % 241);
      final rawServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final openSockets = <Socket>[];
      addTearDown(() async {
        for (final s in openSockets) {
          s.destroy();
        }
        await rawServer.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      rawServer.listen((socket) async {
        openSockets.add(socket);
        // Consume HTTP request headers lightly without waiting for half-close
        socket.listen((_) {});
        final header = 'HTTP/1.1 200 OK\r\n'
            'Content-Type: image/jpeg\r\n'
            'Content-Length: ${payload.length}\r\n'
            '\r\n';
        socket.add(ascii.encode(header));
        socket.add(payload);
        await socket.flush();
        // Deliberately hold the socket open well past inactivity timeout (900ms > 500ms)
        await Future<void>.delayed(const Duration(seconds: 2));
        await socket.close();
      });

      final notifier = PooledDownloadNotifier(
        enableNotifications: true,
        scanOnInit: false,
        chunkInactivityTimeout: const Duration(milliseconds: 500),
        downloadPathResolver: () async => tempDir.path,
      );
      addTearDown(notifier.dispose);

      await notifier.enqueueDownload({
        'id': 7001,
        'site_id': 'danbooru',
        'file_url': 'http://127.0.0.1:${rawServer.port}/7001.jpg',
        'file_ext': 'jpg',
      });

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.downloadingTasks.isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('EOF grace failed to finalize task; remaining=${notifier.downloadingTasks.map((t) => '${t.taskId}:${t.progress}%')}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final targetFile = File('${tempDir.path}${Platform.pathSeparator}7001.jpg');
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.readAsBytes(), payload);
      expect(
        notifCalls.where((c) => c.method == 'showComplete').length,
        1,
      );
    });

    test('finalizes already-complete .part on HTTP 416 with matching Content-Range',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_416_');
      final payload = List<int>.generate(2048, (i) => (i * 7) % 256);
      final partFile = File('${tempDir.path}${Platform.pathSeparator}7002.jpg.part');
      await partFile.writeAsBytes(payload, flush: true);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int reqCount = 0;
      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      server.listen((req) async {
        reqCount++;
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${payload.length}',
        );
        await req.response.close();
      });

      final notifier = PooledDownloadNotifier(
        enableNotifications: true,
        scanOnInit: false,
        chunkInactivityTimeout: const Duration(milliseconds: 250),
        downloadPathResolver: () async => tempDir.path,
      );
      addTearDown(notifier.dispose);

      await notifier.enqueueDownload({
        'id': 7002,
        'site_id': 'yande',
        'file_url': 'http://127.0.0.1:${server.port}/7002.jpg',
        'file_ext': 'jpg',
      });

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.downloadingTasks.isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('416 recovery did not complete');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(reqCount, 1);
      final targetFile = File('${tempDir.path}${Platform.pathSeparator}7002.jpg');
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.readAsBytes(), payload);
    });

    test('retry failure on one concurrent task does not abort sibling download in pool',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('sakuraview_dl_sibling_');
      final slowPayload = List<int>.generate(8192, (i) => i % 251);
      final fastPayload = List<int>.generate(1024, (i) => (i + 3) % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int slowRequests = 0;
      int flakyRequests = 0;
      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      server.listen((req) async {
        if (req.uri.path.contains('7003')) {
          slowRequests++;
          req.response.statusCode = HttpStatus.ok;
          req.response.contentLength = slowPayload.length;
          const mid = 4096;
          req.response.add(slowPayload.sublist(0, mid));
          await req.response.flush();
          // Stay active past retry backoff of sibling
          await Future<void>.delayed(const Duration(milliseconds: 650));
          req.response.add(slowPayload.sublist(mid));
          await req.response.close();
          return;
        }
        flakyRequests++;
        if (flakyRequests == 1) {
          req.response.statusCode = HttpStatus.serviceUnavailable;
          await req.response.close();
          return;
        }
        req.response.statusCode = HttpStatus.ok;
        req.response.contentLength = fastPayload.length;
        req.response.add(fastPayload);
        await req.response.close();
      });

      final notifier = PooledDownloadNotifier(
        enableNotifications: false,
        scanOnInit: false,
        chunkInactivityTimeout: const Duration(seconds: 2),
        downloadPathResolver: () async => tempDir.path,
      );
      addTearDown(notifier.dispose);

      await notifier.enqueueBatchDownload([
        {
          'id': 7003,
          'site_id': 'yande',
          'file_url': 'http://127.0.0.1:${server.port}/7003.jpg',
          'file_ext': 'jpg',
        },
        {
          'id': 7004,
          'site_id': 'yande',
          'file_url': 'http://127.0.0.1:${server.port}/7004.jpg',
          'file_ext': 'jpg',
        },
      ]);

      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (notifier.downloadingTasks.isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Sibling batch stalled');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(slowRequests, 1, reason: 'Slow sibling must finish without being force-closed by retry');
      expect(flakyRequests, 2);
      expect(
        await File('${tempDir.path}${Platform.pathSeparator}7003.jpg').readAsBytes(),
        slowPayload,
      );
      expect(
        await File('${tempDir.path}${Platform.pathSeparator}7004.jpg').readAsBytes(),
        fastPayload,
      );
    });
  });
}
