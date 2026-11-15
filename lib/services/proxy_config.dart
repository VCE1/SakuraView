import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Standards-compliant network proxy modes.
enum ProxyMode {
  /// Honors the operating system's global proxy configuration (`ConnectivityManager.getDefaultProxy()`
  /// on Android, or `HTTP_PROXY`/`HTTPS_PROXY` environment variables on desktop), falling back to
  /// `DIRECT` (which also routes transparently through system VPN / TUN interfaces).
  system,

  /// Uses a user-configured HTTP/HTTPS proxy endpoint (`host:port`).
  manual,

  /// Forces direct network connections (`DIRECT`), bypassing any HTTP proxy configuration.
  none;

  String get label {
    switch (this) {
      case ProxyMode.system:
        return '跟随系统代理 (System Proxy)';
      case ProxyMode.manual:
        return '自定义代理 (Custom HTTP Proxy)';
      case ProxyMode.none:
        return '直连模式 (Direct Connection)';
    }
  }

  String get subtitle {
    switch (this) {
      case ProxyMode.system:
        return '使用系统网络代理或 TUN/VPN';
      case ProxyMode.manual:
        return '指定 HTTP 代理主机与端口';
      case ProxyMode.none:
        return '直接连接目标服务器';
    }
  }

  static ProxyMode fromString(String? value) {
    switch (value) {
      case 'manual':
        return ProxyMode.manual;
      case 'none':
        return ProxyMode.none;
      case 'system':
      default:
        return ProxyMode.system;
    }
  }
}

/// Information about the currently detected operating system network proxy.
class SystemProxyInfo {
  final String host;
  final int port;
  final List<String> nonProxyHosts;
  final String source;

  const SystemProxyInfo({
    required this.host,
    required this.port,
    this.nonProxyHosts = const [],
    this.source = 'System Network',
  });

  String get address => '$host:$port';

  bool get isValid => host.isNotEmpty && port > 0 && port <= 65535;

  @override
  String toString() => '$host:$port ($source)';
}

/// Detailed result of a proxy connectivity check.
class ProxyTestResult {
  final bool success;
  final int? statusCode;
  final int elapsedMs;
  final String effectiveDirective;
  final String? errorMessage;

  const ProxyTestResult({
    required this.success,
    required this.elapsedMs,
    required this.effectiveDirective,
    this.statusCode,
    this.errorMessage,
  });
}

/// Global [HttpOverrides] so that [CachedNetworkImage], [Dio], [Image.network],
/// and all [HttpClient] consumers honor the active [ProxyConfig].
class SakuraHttpOverrides extends HttpOverrides {
  ProxyMode mode;
  String manualAddress;
  SystemProxyInfo? systemProxy;

  SakuraHttpOverrides({
    required this.mode,
    required this.manualAddress,
    this.systemProxy,
  });

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 30);
    client.findProxy = (Uri uri) {
      return ProxyConfig.resolveProxyDirectiveForUri(
        uri,
        mode: mode,
        manualAddress: manualAddress,
        systemProxy: systemProxy,
      );
    };
    return client;
  }
}

class ProxyConfig {
  static final Logger _log = Logger('Proxy');
  static const String _addrKey = 'proxyAddress';
  static const String _enableKey = 'enableProxy';
  static const String _modeKey = 'proxyMode';

  static const MethodChannel _androidProxyChannel =
      MethodChannel('com.sakuraview.dev/proxy');

  static ProxyMode _cachedMode = ProxyMode.system;
  static SystemProxyInfo? _cachedSystemProxy;

  static String _defaultManualProxyAddress() {
    final envProxy = _readEnvironmentProxy();
    if (envProxy != null && envProxy.isValid) {
      return envProxy.address;
    }
    return '127.0.0.1:7890';
  }

  /// Normalizes a user-entered proxy string (e.g., strips `http://`, converts
  /// full-width colon `：` to ASCII `:`, trims spaces).
  static String normalizeProxyAddress(String raw) {
    var cleaned = raw.trim().replaceAll('\uFF1A', ':');
    cleaned = cleaned.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    if (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned.trim();
  }

  /// Validates whether [raw] is a well-formed `host:port` string.
  static bool isValidProxyAddress(String raw) {
    final normalized = normalizeProxyAddress(raw);
    if (normalized.isEmpty || !normalized.contains(':')) return false;
    final lastColon = normalized.lastIndexOf(':');
    final host = normalized.substring(0, lastColon).trim();
    final portStr = normalized.substring(lastColon + 1).trim();
    if (host.isEmpty || host.contains(' ')) return false;
    final port = int.tryParse(portStr);
    return port != null && port >= 1 && port <= 65535;
  }

  /// Reads the current [ProxyMode] from SharedPreferences.
  static Future<ProxyMode> getProxyMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_modeKey);
    if (modeStr != null) {
      _cachedMode = ProxyMode.fromString(modeStr);
      return _cachedMode;
    }
    _cachedMode = ProxyMode.system;
    return _cachedMode;
  }

  static Future<void> saveProxyMode(ProxyMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    await prefs.setBool(_enableKey, mode != ProxyMode.none);
    _cachedMode = mode;
    _log.info('Proxy mode saved => ${mode.name}');
    await refreshGlobalHttpOverrides();
  }

  static Future<String> getProxyAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_addrKey);
    if (stored != null && stored.trim().isNotEmpty) {
      return normalizeProxyAddress(stored);
    }
    return _defaultManualProxyAddress();
  }

  static Future<bool> isProxyEnabled() async {
    final mode = await getProxyMode();
    return mode != ProxyMode.none;
  }

  static Future<void> saveProxyAddress(String addr) async {
    final normalized = normalizeProxyAddress(addr);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addrKey, normalized);
    _log.info('Proxy address saved => "$normalized"');
    await refreshGlobalHttpOverrides();
  }

  static Future<void> saveProxyEnabled(bool enabled) async {
    final currentMode = await getProxyMode();
    if (!enabled) {
      await saveProxyMode(ProxyMode.none);
    } else if (currentMode == ProxyMode.none) {
      await saveProxyMode(ProxyMode.system);
    }
  }

  /// Queries the operating system network proxy settings.
  static Future<SystemProxyInfo?> getSystemProxyInfo() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final result = await _androidProxyChannel
            .invokeMapMethod<String, dynamic>('getSystemProxy');
        if (result != null) {
          final host = (result['host'] as String?)?.trim() ?? '';
          final port = (result['port'] as int?) ?? 0;
          final nonProxyRaw = (result['nonProxyHosts'] as String?) ?? '';
          if (host.isNotEmpty && port > 0 && port <= 65535) {
            final exclusions = nonProxyRaw
                .split(RegExp(r'[,|]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            final info = SystemProxyInfo(
              host: host,
              port: port,
              nonProxyHosts: exclusions,
              source: Platform.isIOS
                  ? 'iOS CFNetwork Proxy'
                  : 'Android ConnectivityManager',
            );
            _cachedSystemProxy = info;
            return info;
          }
        }
      } catch (e) {
        _log.fine('Mobile system proxy channel unavailable or empty: $e');
      }
    }

    final envProxy = _readEnvironmentProxy();
    if (envProxy != null && envProxy.isValid) {
      _cachedSystemProxy = envProxy;
      return envProxy;
    }

    _cachedSystemProxy = null;
    return null;
  }

  static SystemProxyInfo? _readEnvironmentProxy([Map<String, String>? env]) {
    final environment = env ?? Platform.environment;
    final rawProxy = environment['HTTPS_PROXY'] ??
        environment['https_proxy'] ??
        environment['HTTP_PROXY'] ??
        environment['http_proxy'] ??
        '';
    if (rawProxy.trim().isEmpty) return null;

    final normalized = normalizeProxyAddress(rawProxy);
    if (!isValidProxyAddress(normalized)) return null;

    final lastColon = normalized.lastIndexOf(':');
    final host = normalized.substring(0, lastColon).trim();
    final port = int.parse(normalized.substring(lastColon + 1).trim());

    final rawNoProxy =
        environment['NO_PROXY'] ?? environment['no_proxy'] ?? '';
    final exclusions = rawNoProxy
        .split(RegExp(r'[,;|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return SystemProxyInfo(
      host: host,
      port: port,
      nonProxyHosts: exclusions,
      source: 'OS Environment',
    );
  }

  /// Checks whether [host] should bypass the proxy according to [nonProxyHosts].
  static bool shouldBypassProxy(String host, [List<String> nonProxyHosts = const []]) {
    final lowerHost = host.toLowerCase().trim();
    if (lowerHost.isEmpty ||
        lowerHost == 'localhost' ||
        lowerHost == '127.0.0.1' ||
        lowerHost == '::1' ||
        lowerHost == '[::1]') {
      return true;
    }

    for (final rawRule in nonProxyHosts) {
      final rule = rawRule.toLowerCase().trim();
      if (rule.isEmpty) continue;
      if (rule == '*') return true;
      if (lowerHost == rule) return true;
      if (rule.startsWith('*.')) {
        final suffix = rule.substring(1);
        if (lowerHost.endsWith(suffix)) return true;
      } else if (rule.startsWith('.')) {
        if (lowerHost.endsWith(rule)) return true;
      } else if (rule.endsWith('.*')) {
        final prefix = rule.substring(0, rule.length - 1);
        if (lowerHost.startsWith(prefix)) return true;
      }
    }
    return false;
  }

  /// Computes the PAC proxy directive (`"PROXY host:port"` or `"DIRECT"`) for [uri].
  static String resolveProxyDirectiveForUri(
    Uri uri, {
    required ProxyMode mode,
    required String manualAddress,
    SystemProxyInfo? systemProxy,
  }) {
    if (mode == ProxyMode.none) {
      return 'DIRECT';
    }

    if (mode == ProxyMode.manual) {
      final normalized = normalizeProxyAddress(manualAddress);
      if (!isValidProxyAddress(normalized)) {
        return 'DIRECT';
      }
      if (shouldBypassProxy(uri.host)) {
        return 'DIRECT';
      }
      return 'PROXY $normalized; DIRECT';
    }

    // ProxyMode.system:
    final activeSystemProxy = systemProxy ?? _cachedSystemProxy ?? _readEnvironmentProxy();
    if (activeSystemProxy != null && activeSystemProxy.isValid) {
      if (shouldBypassProxy(uri.host, activeSystemProxy.nonProxyHosts)) {
        return 'DIRECT';
      }
      return 'PROXY ${activeSystemProxy.address}; DIRECT';
    }

    try {
      return HttpClient.findProxyFromEnvironment(uri, environment: Platform.environment);
    } catch (_) {
      return 'DIRECT';
    }
  }

  /// Initializes and installs [SakuraHttpOverrides] globally so all network
  /// clients ([CachedNetworkImage], [Dio], [http], [Image.network]) use the active proxy.
  static Future<void> initGlobalHttpOverrides() async {
    await refreshGlobalHttpOverrides();
  }

  static Future<void> refreshGlobalHttpOverrides() async {
    final mode = await getProxyMode();
    final manualAddr = await getProxyAddress();
    final sysProxy = await getSystemProxyInfo();

    HttpOverrides.global = SakuraHttpOverrides(
      mode: mode,
      manualAddress: manualAddr,
      systemProxy: sysProxy,
    );
    _log.info(
      'Global HttpOverrides updated: mode=${mode.name}, manual="$manualAddr", system=${sysProxy?.toString() ?? "none"}',
    );
  }

  /// Creates a configured native [HttpClient] honoring the current proxy settings.
  static Future<HttpClient> createNativeHttpClient({
    Duration connectionTimeout = const Duration(seconds: 15),
    Duration idleTimeout = const Duration(seconds: 30),
    int? maxConnectionsPerHost,
  }) async {
    final mode = await getProxyMode();
    final manualAddress = await getProxyAddress();
    final sysProxy = mode == ProxyMode.system ? await getSystemProxyInfo() : null;

    _log.info(
      'createNativeHttpClient: mode=${mode.name}, manual="$manualAddress", system=${sysProxy?.address ?? "DIRECT"}',
    );

    final httpClient = HttpClient();
    httpClient.connectionTimeout = connectionTimeout;
    httpClient.idleTimeout = idleTimeout;
    if (maxConnectionsPerHost != null) {
      httpClient.maxConnectionsPerHost = maxConnectionsPerHost;
    }

    httpClient.findProxy = (Uri uri) {
      final directive = resolveProxyDirectiveForUri(
        uri,
        mode: mode,
        manualAddress: manualAddress,
        systemProxy: sysProxy,
      );
      _log.fine('findProxy(${uri.host}) => $directive');
      return directive;
    };
    return httpClient;
  }

  /// Creates an [http.Client] configured with the current proxy settings.
  static Future<http.Client> createClient() async {
    try {
      final httpClient = await createNativeHttpClient();
      return IOClient(httpClient);
    } catch (e, st) {
      _log.severe('createClient FAILED: $e\n$st');
      return http.Client();
    }
  }

  /// Tests connectivity and returns a detailed [ProxyTestResult].
  static Future<ProxyTestResult> testConnectionWithDetails({
    Duration timeout = const Duration(seconds: 10),
    Uri? targetUri,
  }) async {
    final testUri = targetUri ?? Uri.parse('https://yande.re/tag.json?limit=1');
    final mode = await getProxyMode();
    final manualAddress = await getProxyAddress();
    final sysProxy = mode == ProxyMode.system ? await getSystemProxyInfo() : null;
    final directive = resolveProxyDirectiveForUri(
      testUri,
      mode: mode,
      manualAddress: manualAddress,
      systemProxy: sysProxy,
    );

    _log.info('=== testConnection(mode=${mode.name}, directive="$directive") ===');
    http.Client? client;
    final sw = Stopwatch()..start();
    try {
      client = await createClient();
      final resp = await client.get(
        testUri,
        headers: const {'User-Agent': 'vce1.sakuraview/1.2'},
      ).timeout(timeout);
      sw.stop();
      final ok = resp.statusCode >= 200 && resp.statusCode < 400;
      _log.info(
        'test => HTTP ${resp.statusCode} in ${sw.elapsedMilliseconds}ms ${ok ? "PASS" : "FAIL"}',
      );
      return ProxyTestResult(
        success: ok,
        statusCode: resp.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        effectiveDirective: directive,
        errorMessage: ok ? null : 'HTTP ${resp.statusCode}',
      );
    } on TimeoutException catch (e) {
      sw.stop();
      _log.severe('test => TIMEOUT after $timeout: $e');
      return ProxyTestResult(
        success: false,
        elapsedMs: sw.elapsedMilliseconds,
        effectiveDirective: directive,
        errorMessage: '连接超时 (${timeout.inSeconds}s)',
      );
    } on SocketException catch (e) {
      sw.stop();
      _log.severe('test => SOCKET: $e');
      return ProxyTestResult(
        success: false,
        elapsedMs: sw.elapsedMilliseconds,
        effectiveDirective: directive,
        errorMessage: '网络套接字错误: ${e.message}',
      );
    } on HttpException catch (e) {
      sw.stop();
      _log.severe('test => HTTP: $e');
      return ProxyTestResult(
        success: false,
        elapsedMs: sw.elapsedMilliseconds,
        effectiveDirective: directive,
        errorMessage: 'HTTP 协议错误: ${e.message}',
      );
    } catch (e, st) {
      sw.stop();
      _log.severe('test => ERROR: $e\n$st');
      return ProxyTestResult(
        success: false,
        elapsedMs: sw.elapsedMilliseconds,
        effectiveDirective: directive,
        errorMessage: e.toString(),
      );
    } finally {
      client?.close();
    }
  }

  static Future<bool> testConnection({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final result = await testConnectionWithDetails(timeout: timeout);
    return result.success;
  }
}
