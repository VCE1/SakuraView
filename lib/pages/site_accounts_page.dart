import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/models/site_config.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

class SiteAccountsPage extends StatelessWidget {
  final ImageSite? initialSite;
  final String? initialSourceId;

  const SiteAccountsPage({
    super.key,
    this.initialSite,
    this.initialSourceId,
  });

  @override
  Widget build(BuildContext context) {
    final highlightId = initialSourceId ?? initialSite?.name;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('站点账号'),
      ),
      body: Consumer<SiteConfigProvider>(
        builder: (context, siteProvider, _) {
          final sources = siteProvider.allSources;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              ...sources.map((source) {
                final creds = siteProvider.credentialsForSource(source.id);
                final isCurrent = siteProvider.currentSourceId == source.id;
                final isHighlighted = highlightId == source.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _SourceAccountCard(
                    source: source,
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

class _SourceAccountCard extends StatelessWidget {
  final SourceDescriptor source;
  final SourceAccountCredentials credentials;
  final bool isActiveSite;
  final bool isHighlighted;

  const _SourceAccountCard({
    required this.source,
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
    final userIdCtrl = TextEditingController(text: credentials.userId);
    final keyCtrl = TextEditingController(text: credentials.apiKey);
    final cookieCtrl = TextEditingController(text: credentials.cookies);
    final needsUserId = source.authType == SourceAuthType.userIdApiKey;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${source.name} 账号与凭证配置'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (source.authDescription.isNotEmpty) ...[
                  Text(
                    source.authDescription,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (needsUserId) ...[
                  TextField(
                    controller: userIdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'User ID (user_id)',
                      hintText: '在账号个人主页 / Account Options 查看数字 ID',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText: needsUserId
                        ? '${source.name} 用户名 (选填)'
                        : '${source.name} 用户名 (非邮箱)',
                    hintText: source.id == 'danbooru'
                        ? '填写 Danbooru 用户名（不可填邮箱）'
                        : '用于 API 认证或云端收藏同步',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                  ),
                ),
                if (source.id == 'danbooru') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .primaryContainer
                          .withAlpha(70),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '说明：手动配置必须填写 Danbooru「用户名（非邮箱）」与官网 Profile -> API Key 生成的「API Key（非登录密码）」。若使用邮箱密码登录或遇到 Cloudflare 验证，请点击卡片上的「网页登录」。',
                      style: TextStyle(fontSize: 11.5, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: source.id == 'danbooru'
                        ? 'API Key (Danbooru Profile -> API Key)'
                        : (needsUserId
                            ? 'API Key (Account Options -> API Access)'
                            : 'API Key / Password Hash (选填)'),
                    hintText: source.id == 'danbooru'
                        ? '填写 API Key（不要填写登录密码）'
                        : '填写 API 密钥或访问令牌',
                    prefixIcon: const Icon(Icons.key_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cookieCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Session Cookies (可通过 WebView 登录获取)',
                    hintText: '例如 cf_clearance=...; session=...',
                    prefixIcon: Icon(Icons.cookie_outlined, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SiteWebViewLoginPage(source: source),
                ),
              );
            },
            child: const Text('网页登录'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存配置'),
            onPressed: () async {
              final rawUser = userCtrl.text.trim();
              if (source.id == 'danbooru' && rawUser.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Danbooru 手动配置不可填邮箱，请填写官网用户名，或点击「网页登录」使用邮箱登录',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              await siteProvider.updateCredentialsById(
                source.id,
                username: rawUser,
                userId: userIdCtrl.text.trim(),
                apiKey: keyCtrl.text.trim(),
                cookies: cookieCtrl.text.trim(),
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已保存 ${source.name} 账号配置'),
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
    final showUserId = source.authType == SourceAuthType.userIdApiKey ||
        credentials.userId.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isHighlighted
              ? cs.primary
              : (isConfigured
                  ? cs.primary.withAlpha(110)
                  : cs.outlineVariant.withAlpha(90)),
          width: isHighlighted ? 1.5 : 0.9,
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
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.public_rounded,
                    color: isConfigured ? cs.primary : cs.onSurfaceVariant,
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
                          Flexible(
                            child: Text(
                              source.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isActiveSite) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '当前站点',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                          if (!source.isEnabled) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '未启用',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.cleanBaseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            if (source.authDescription.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                source.authDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (showUserId) ...[
                    _CredentialSummaryRow(
                      label: 'User ID',
                      value: credentials.userId.isNotEmpty
                          ? credentials.userId
                          : '未设置',
                      active: credentials.userId.isNotEmpty,
                    ),
                    const SizedBox(height: 6),
                  ],
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
                  label: const Text('网页登录'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      SakuraPageRoute(
                        builder: (_) => SiteWebViewLoginPage(source: source),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('配置密钥'),
                  onPressed: () => _showEditCredentialsDialog(context),
                ),
                if (!isActiveSite)
                  TextButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                    label: Text(source.isEnabled ? '切换使用' : '启用并切换'),
                    onPressed: () async {
                      final provider = context.read<SiteConfigProvider>();
                      if (!source.isEnabled) {
                        await provider.setSourceEnabled(source.id, true);
                      }
                      await provider.setSourceById(source.id);
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
                          .clearCredentialsById(source.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已清除 ${source.name} 登录凭证'),
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
  final SourceAccountCredentials credentials;
  const _StatusBadge({required this.credentials});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool ok = credentials.isConfigured;
    final String label = credentials.hasApiAuth
        ? 'API 已认证'
        : (credentials.hasCookieAuth
            ? 'Cookie 已登录'
            : (credentials.username.isNotEmpty || credentials.userId.isNotEmpty
                ? '已填账号'
                : '未登录'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? cs.secondaryContainer
            : cs.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ok ? cs.primary.withAlpha(90) : cs.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 13,
            color: ok ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ok ? cs.onSecondaryContainer : cs.onSurfaceVariant,
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

/// 内置 WebView 登录页，自动捕获目标站点的 Cookie 与 User-Agent。
class SiteWebViewLoginPage extends StatefulWidget {
  final SourceDescriptor source;

  const SiteWebViewLoginPage({super.key, required this.source});

  @override
  State<SiteWebViewLoginPage> createState() => _SiteWebViewLoginPageState();
}

class _SiteWebViewLoginPageState extends State<SiteWebViewLoginPage> {
  static const MethodChannel _channel =
      MethodChannel('com.sakuraview.dev/webview_cookies');

  String _currentUrl = '';
  String _capturedCookies = '';
  String _capturedUserAgent = '';
  String _detectedUserName = '';
  String _detectedUserId = '';
  int _progress = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.source.effectiveLoginUrl;
    final existing = context
        .read<SiteConfigProvider>()
        .credentialsForSource(widget.source.id);
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
      } else if (call.method == 'onUserMetaDetected') {
        final args = call.arguments as Map?;
        final uname = (args?['currentUserName'] as String?)?.trim() ?? '';
        final uid = (args?['currentUserId'] as String?)?.trim() ?? '';
        if (uname.isNotEmpty || uid.isNotEmpty) {
          setState(() {
            if (uname.isNotEmpty && uname.toLowerCase() != 'anonymous') {
              _detectedUserName = uname;
            }
            if (uid.isNotEmpty) {
              _detectedUserId = uid;
            }
          });
        }
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

  String? _tryExtractUserIdFromCookies(String cookies) {
    final pairs = cookies.split(';').map((s) => s.trim());
    for (final pair in pairs) {
      final idx = pair.indexOf('=');
      if (idx <= 0) continue;
      final k = pair.substring(0, idx).trim().toLowerCase();
      final v = Uri.decodeComponent(pair.substring(idx + 1).trim());
      if (k == 'user_id' && int.tryParse(v) != null) {
        return v;
      }
    }
    return null;
  }

  Future<void> _saveCapturedCookies() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>(
          'getCookies',
          {'url': widget.source.cleanBaseUrl},
        );
        if (res != null) {
          final c = (res['cookies'] as String?) ?? '';
          final ua = (res['userAgent'] as String?) ?? '';
          final metaUser =
              (res['currentUserName'] as String?)?.trim() ?? '';
          final metaId = (res['currentUserId'] as String?)?.trim() ?? '';
          if (c.isNotEmpty) _capturedCookies = c;
          if (ua.isNotEmpty) _capturedUserAgent = ua;
          if (metaUser.isNotEmpty && metaUser.toLowerCase() != 'anonymous') {
            _detectedUserName = metaUser;
          }
          if (metaId.isNotEmpty) {
            _detectedUserId = metaId;
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final provider = context.read<SiteConfigProvider>();
    final existing = provider.credentialsForSource(widget.source.id);
    final autoUser = _detectedUserName.isNotEmpty
        ? _detectedUserName
        : _tryExtractUsernameFromCookies(_capturedCookies);
    final autoUserId = _detectedUserId.isNotEmpty
        ? _detectedUserId
        : _tryExtractUserIdFromCookies(_capturedCookies);
    final initialUser = (autoUser != null && autoUser.isNotEmpty)
        ? autoUser
        : (existing.username.contains('@') ? '' : existing.username);
    final userCtrl = TextEditingController(text: initialUser);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('保存 ${widget.source.name} 登录状态'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _capturedCookies.isNotEmpty
                  ? '已捕获网页 Cookie 会话，将自动应用于 ${widget.source.name} 的接口与图片请求。'
                  : '尚未检测到有效 Cookie，仍可保存用户名。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            if (_detectedUserName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已从页面自动识别当前用户名：$_detectedUserName',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: userCtrl,
              decoration: InputDecoration(
                labelText: '${widget.source.name} 用户名 (非邮箱)',
                hintText: '用于云端收藏夹同步（若留空保存后将尝试自动解析）',
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
      await provider.updateCredentialsById(
        widget.source.id,
        username: userCtrl.text.trim(),
        userId: (autoUserId != null && autoUserId.isNotEmpty)
            ? autoUserId
            : existing.userId,
        cookies: _capturedCookies,
        userAgent: _capturedUserAgent,
      );

      // 对 Danbooru 等支持 `/profile.json` 的站点：若仍缺少官网用户名，自动联网解析一次。
      if (mounted &&
          widget.source.id == 'danbooru' &&
          userCtrl.text.trim().isEmpty &&
          _capturedCookies.isNotEmpty) {
        final adapter = provider.adapterFor('danbooru');
        if (adapter is DanbooruSourceAdapter) {
          final resolved = await adapter.resolveAuthenticatedProfile();
          if (resolved != null && resolved.name.isNotEmpty && mounted) {
            await provider.updateCredentialsById(
              widget.source.id,
              username: resolved.name,
              userId: resolved.id.isNotEmpty ? resolved.id : null,
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存 ${widget.source.name} Cookie 状态'),
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
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.source.name} 网页登录',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
          if (Platform.isAndroid || Platform.isIOS) ...[
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
                  color: cookieCount > 0 ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _detectedUserName.isNotEmpty
                        ? '已识别账号 $_detectedUserName · 已捕获 $cookieCount 项 Cookie，可点击右上角「保存 Cookie」'
                        : (cookieCount > 0
                            ? '已捕获 $cookieCount 项 Cookie，登录完成后点击右上角「保存 Cookie」'
                            : '请在网页完成登录，随后点击右上角「保存 Cookie」'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _detectedUserName.isNotEmpty
                          ? cs.primary
                          : cs.onSurfaceVariant,
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
                      'initialUrl': widget.source.effectiveLoginUrl,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                : Platform.isIOS
                    ? UiKitView(
                        viewType: 'com.sakuraview.dev/native_webview',
                        creationParams: <String, dynamic>{
                          'initialUrl': widget.source.effectiveLoginUrl,
                        },
                        creationParamsCodec: const StandardMessageCodec(),
                      )
                    : _DesktopWebViewFallback(
                        source: widget.source,
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
  final SourceDescriptor source;
  final ValueChanged<String> onCookiesPasted;

  const _DesktopWebViewFallback({
    required this.source,
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
    final loginUrl = widget.source.effectiveLoginUrl;
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
                  '在浏览器中登录 ${widget.source.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  '桌面端可打开外部浏览器登录后，将 Cookie 字符串粘贴到下方保存。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.launch_rounded, size: 18),
                  label: Text('打开 $loginUrl'),
                  onPressed: () {
                    launchUrl(
                      Uri.parse(loginUrl),
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
