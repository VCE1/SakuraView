import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

class SiteAccountsPage extends StatelessWidget {
  final ImageSite? initialSite;

  const SiteAccountsPage({super.key, this.initialSite});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('站点账号与认证管理'),
      ),
      body: Consumer<SiteConfigProvider>(
        builder: (context, siteProvider, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withAlpha(50)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: cs.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '每个图站均支持独立配置 API 密钥或通过内置 WebView 网页登录自动捕获并持久化 Cookie。登录后可在「收藏 -> 云端收藏」中同步您的云端账号收藏夹。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...ImageSite.values.map((site) {
                final creds = siteProvider.credentialsFor(site);
                final isCurrent = siteProvider.config.site == site;
                final isHighlighted = initialSite == site;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _SiteAccountCard(
                    site: site,
                    credentials: creds,
                    isActiveSite: isCurrent,
                    isHighlighted: isHighlighted,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _SiteAccountCard extends StatelessWidget {
  final ImageSite site;
  final SiteAccountCredentials credentials;
  final bool isActiveSite;
  final bool isHighlighted;

  const _SiteAccountCard({
    required this.site,
    required this.credentials,
    required this.isActiveSite,
    this.isHighlighted = false,
  });

  int _cookieCount(String rawCookies) {
    if (rawCookies.trim().isEmpty) return 0;
    return rawCookies
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.contains('='))
        .length;
  }

  void _showEditCredentialsDialog(BuildContext context) {
    final siteProvider = context.read<SiteConfigProvider>();
    final userCtrl = TextEditingController(text: credentials.username);
    final keyCtrl = TextEditingController(text: credentials.apiKey);
    final cookieCtrl = TextEditingController(text: credentials.cookies);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${site.displayName} 账号与凭证配置'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  site.authDescription,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText: '${site.displayName} 用户名 (Username)',
                    hintText: '用于 API 认证及云端收藏同步',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: site == ImageSite.danbooru
                        ? 'API Key (Danbooru Profile -> API Key)'
                        : 'API Key / Password Hash (选填)',
                    hintText: '填写 API 密钥或令牌',
                    prefixIcon: const Icon(Icons.key_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cookieCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Session Cookies (可通过 WebView 自动获取)',
                    hintText: '例如 cf_clearance=...; _danbooru2_session=...',
                    prefixIcon: Icon(Icons.cookie_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存配置'),
            onPressed: () async {
              await siteProvider.updateSiteCredentials(
                site,
                username: userCtrl.text.trim(),
                apiKey: keyCtrl.text.trim(),
                cookies: cookieCtrl.text.trim(),
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已保存 ${site.displayName} 账号配置'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cookieCount = _cookieCount(credentials.cookies);
    final isConfigured = credentials.isConfigured;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isHighlighted
              ? cs.primary
              : (isConfigured
                  ? cs.primary.withAlpha(90)
                  : cs.outlineVariant.withAlpha(90)),
          width: isHighlighted ? 1.6 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withAlpha(180),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    switch (site) {
                      ImageSite.danbooru => Icons.grid_view_rounded,
                      ImageSite.yandere => Icons.auto_awesome_rounded,
                      ImageSite.zerochan => Icons.collections_bookmark_rounded,
                    },
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            site.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (isActiveSite) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withAlpha(35),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '当前站点',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        site.apiBaseUrl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(credentials: credentials),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              site.authDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _CredentialSummaryRow(
                    label: '用户名',
                    value: credentials.username.isNotEmpty
                        ? credentials.username
                        : '未设置',
                    active: credentials.username.isNotEmpty,
                  ),
                  const SizedBox(height: 6),
                  _CredentialSummaryRow(
                    label: 'API 密钥',
                    value: credentials.apiKey.isNotEmpty
                        ? '已配置 (${credentials.apiKey.length} 位)'
                        : '未设置',
                    active: credentials.apiKey.isNotEmpty,
                  ),
                  const SizedBox(height: 6),
                  _CredentialSummaryRow(
                    label: 'WebView Cookie',
                    value: cookieCount > 0 ? '已保存 ($cookieCount 项字段)' : '未保存',
                    active: cookieCount > 0,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.language_rounded, size: 17),
                  label: const Text('WebView 网页登录'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      SakuraPageRoute(
                        builder: (_) => SiteWebViewLoginPage(site: site),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('配置 API / 账号'),
                  onPressed: () => _showEditCredentialsDialog(context),
                ),
                if (!isActiveSite)
                  TextButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                    label: const Text('切换至此站点'),
                    onPressed: () {
                      context.read<SiteConfigProvider>().setSite(site);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已切换当前站点为 ${site.displayName}'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                if (isConfigured)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('清除凭证'),
                    onPressed: () async {
                      await context
                          .read<SiteConfigProvider>()
                          .clearSiteCredentials(site);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已清除 ${site.displayName} 登录凭证'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SiteAccountCredentials credentials;
  const _StatusBadge({required this.credentials});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool ok = credentials.isConfigured;
    final String label = credentials.hasApiAuth
        ? 'API 已认证'
        : (credentials.hasCookieAuth
            ? 'Cookie 已登录'
            : (credentials.username.isNotEmpty ? '已设用户名' : '未登录'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? Colors.teal.withAlpha(35)
            : cs.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ok ? Colors.teal.withAlpha(120) : cs.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 13,
            color: ok ? Colors.teal : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ok ? Colors.teal : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool active;

  const _CredentialSummaryRow({
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              color: active ? cs.onSurface : cs.onSurfaceVariant.withAlpha(150),
            ),
          ),
        ),
      ],
    );
  }
}

/// Built-in WebView login page that embeds Android's native WebView and
/// captures session cookies (`CookieManager`) + `User-Agent` for [site].
class SiteWebViewLoginPage extends StatefulWidget {
  final ImageSite site;

  const SiteWebViewLoginPage({super.key, required this.site});

  @override
  State<SiteWebViewLoginPage> createState() => _SiteWebViewLoginPageState();
}

class _SiteWebViewLoginPageState extends State<SiteWebViewLoginPage> {
  static const MethodChannel _channel =
      MethodChannel('com.sakuraview.dev/webview_cookies');

  String _currentUrl = '';
  String _capturedCookies = '';
  String _capturedUserAgent = '';
  int _progress = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.site.loginUrl;
    final existing =
        context.read<SiteConfigProvider>().credentialsFor(widget.site);
    _capturedCookies = existing.cookies;
    _capturedUserAgent = existing.userAgent;

    _channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onProgress') {
        final args = call.arguments as Map?;
        setState(() {
          _progress = (args?['progress'] as int?) ?? 0;
        });
      } else if (call.method == 'onPageStateChanged') {
        final args = call.arguments as Map?;
        final url = (args?['url'] as String?) ?? _currentUrl;
        final cookies = (args?['cookies'] as String?) ?? '';
        final ua = (args?['userAgent'] as String?) ?? '';
        final loading = (args?['isLoading'] as bool?) ?? false;
        setState(() {
          _currentUrl = url;
          if (cookies.isNotEmpty) _capturedCookies = cookies;
          if (ua.isNotEmpty) _capturedUserAgent = ua;
          _isLoading = loading;
        });
      }
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  String? _tryExtractUsernameFromCookies(String cookies) {
    final pairs = cookies.split(';').map((s) => s.trim());
    for (final pair in pairs) {
      final idx = pair.indexOf('=');
      if (idx <= 0) continue;
      final k = pair.substring(0, idx).trim().toLowerCase();
      final v = Uri.decodeComponent(pair.substring(idx + 1).trim());
      if ((k == 'user_name' || k == 'login' || k == 'username') &&
          v.isNotEmpty) {
        return v;
      }
    }
    return null;
  }

  Future<void> _saveCapturedCookies() async {
    if (Platform.isAndroid) {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>(
          'getCookies',
          {'url': widget.site.apiBaseUrl},
        );
        if (res != null) {
          final c = (res['cookies'] as String?) ?? '';
          final ua = (res['userAgent'] as String?) ?? '';
          if (c.isNotEmpty) _capturedCookies = c;
          if (ua.isNotEmpty) _capturedUserAgent = ua;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final provider = context.read<SiteConfigProvider>();
    final existing = provider.credentialsFor(widget.site);
    final autoUser = _tryExtractUsernameFromCookies(_capturedCookies);
    final userCtrl = TextEditingController(
      text: existing.username.isNotEmpty ? existing.username : (autoUser ?? ''),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('保存 ${widget.site.displayName} 登录状态'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _capturedCookies.isNotEmpty
                  ? '已成功从网页捕获 Cookie 会话，将自动应用于 ${widget.site.displayName} 的接口与图片请求。'
                  : '当前尚未检测到有效 Cookie，您仍可保存用户名。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: userCtrl,
              decoration: InputDecoration(
                labelText: '${widget.site.displayName} 用户名 (选填，用于云端收藏夹)',
                hintText: '输入您在站点的用户名以同步云端收藏',
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续浏览'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await provider.updateSiteCredentials(
        widget.site,
        username: userCtrl.text.trim(),
        cookies: _capturedCookies,
        userAgent: _capturedUserAgent,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存 ${widget.site.displayName} Cookie 与账号状态'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cookieCount = _capturedCookies
        .split(';')
        .where((s) => s.trim().contains('='))
        .length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.site.displayName} 网页登录',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              _currentUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (Platform.isAndroid) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              tooltip: '后退',
              onPressed: () => _channel.invokeMethod('goBack'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: '刷新网页',
              onPressed: () => _channel.invokeMethod('reload'),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('保存 Cookie'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _saveCapturedCookies,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading && _progress < 100)
            LinearProgressIndicator(
              value: _progress > 0 ? _progress / 100.0 : null,
              minHeight: 2.5,
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: cs.surfaceContainerHighest.withAlpha(120),
            child: Row(
              children: [
                Icon(
                  cookieCount > 0
                      ? Icons.cookie_rounded
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: cookieCount > 0 ? Colors.teal : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cookieCount > 0
                        ? '已实时捕获 $cookieCount 项 Cookie 字段，登录成功后请点击右上角「保存 Cookie」'
                        : '请在下方网页中完成登录，然后点击右上角「保存 Cookie」',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Platform.isAndroid
                ? AndroidView(
                    viewType: 'com.sakuraview.dev/native_webview',
                    creationParams: <String, dynamic>{
                      'initialUrl': widget.site.loginUrl,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                : _DesktopWebViewFallback(
                    site: widget.site,
                    onCookiesPasted: (cookies) {
                      setState(() => _capturedCookies = cookies);
                      _saveCapturedCookies();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DesktopWebViewFallback extends StatefulWidget {
  final ImageSite site;
  final ValueChanged<String> onCookiesPasted;

  const _DesktopWebViewFallback({
    required this.site,
    required this.onCookiesPasted,
  });

  @override
  State<_DesktopWebViewFallback> createState() =>
      _DesktopWebViewFallbackState();
}

class _DesktopWebViewFallbackState extends State<_DesktopWebViewFallback> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.open_in_browser_rounded, size: 48),
                const SizedBox(height: 12),
                Text(
                  '在浏览器中登录 ${widget.site.displayName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  '桌面端可点击下方按钮打开登录页，或直接粘贴 Cookie 字符串保存。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.launch_rounded, size: 18),
                  label: Text('打开 ${widget.site.loginUrl}'),
                  onPressed: () {
                    launchUrl(
                      Uri.parse(widget.site.loginUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ctrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '粘贴 Cookie 字符串',
                    hintText: 'key1=value1; key2=value2',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => widget.onCookiesPasted(_ctrl.text.trim()),
                  child: const Text('保存 Cookie'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
