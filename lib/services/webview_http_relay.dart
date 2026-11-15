import 'dart:io';

import 'package:flutter/services.dart';

/// WebView Chromium 同源请求结果（用于在 Android 端复用已通过网页登录得到的
/// `cf_clearance` 与会话 Cookie，解决 Dart HttpClient TLS 指纹与浏览器不一致导致的 403）。
class WebViewFetchResult {
  final int statusCode;
  final String body;
  final String cookies;

  const WebViewFetchResult({
    required this.statusCode,
    required this.body,
    required this.cookies,
  });
}

/// 仅在 Android 运行时可用的 Chromium WebView 同源 JSON 请求中继。
///
/// 不参与任何验证码或 Turnstile 自动点击/绕过；若网站仍返回验证页，
/// 会原样返回状态码与提示，由用户通过「网页登录」亲自完成。
class WebViewHttpRelay {
  const WebViewHttpRelay._();

  static const MethodChannel _channel =
      MethodChannel('com.sakuraview.dev/webview_cookies');

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<WebViewFetchResult?> fetchJson({
    required Uri uri,
    required String baseUrl,
    String cookies = '',
    String userAgent = '',
  }) =>
      sendRequest(
        method: 'GET',
        uri: uri,
        baseUrl: baseUrl,
        cookies: cookies,
        userAgent: userAgent,
      );

  /// 通过原生 WebView 会话发起 GET / POST / DELETE 请求（非 GET 自动提取 CSRF Token）。
  static Future<WebViewFetchResult?> sendRequest({
    required String method,
    required Uri uri,
    required String baseUrl,
    String cookies = '',
    String userAgent = '',
  }) async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'webViewFetch',
        <String, dynamic>{
          'method': method.toUpperCase(),
          'url': uri.toString(),
          'baseUrl': baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
          'cookies': cookies,
          'userAgent': userAgent,
        },
      );
      if (res == null) return null;
      final status = (res['statusCode'] as int?) ?? -1;
      if (status <= 0) return null;
      return WebViewFetchResult(
        statusCode: status,
        body: (res['body'] as String?) ?? '',
        cookies: (res['cookies'] as String?) ?? '',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
