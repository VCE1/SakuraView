import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/core/sources/source_config_parser.dart';
import 'package:vce1_sakuraview/core/sources/source_developer_template.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

/// 图源管理页面：支持启用/禁用内置及新适配图源、连通性检测、JSON 导入导出及开发者模板。
class SourceManagementPage extends StatefulWidget {
  const SourceManagementPage({super.key});

  @override
  State<SourceManagementPage> createState() => _SourceManagementPageState();
}

class _SourceManagementPageState extends State<SourceManagementPage> {
  final Set<String> _testingIds = {};

  Future<void> _testConnection(
    SiteConfigProvider provider,
    SourceDescriptor source,
  ) async {
    if (_testingIds.contains(source.id)) return;
    setState(() => _testingIds.add(source.id));
    try {
      final result = await provider.testSourceConnection(source.id);
      if (!mounted) return;
      final message = result.isHealthy
          ? '${source.name} 连接正常 (${result.lastLatencyMs ?? 0} ms)'
          : '${source.name} 测试失败：${result.lastError ?? '未知错误'}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testingIds.remove(source.id));
      }
    }
  }

  Future<void> _showImportJsonDialog(SiteConfigProvider provider) async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('JSON 导入图源'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '支持导入单个图源配置对象，或包含多条图源的数组 / {"sources": [...]} 清单。导入后默认保持关闭状态，需手动开启后使用。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.paste_rounded, size: 17),
                      label: const Text('从剪贴板粘贴'),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          controller.text = data!.text!;
                          setDialogState(() => errorText = null);
                        }
                      },
                    ),
                  ),
                  TextField(
                    controller: controller,
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: '在此粘贴图源 JSON 配置...',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
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
            FilledButton(
              onPressed: () async {
                try {
                  final count =
                      await provider.importSourcesJson(controller.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已成功导入 $count 个图源（默认处于禁用状态）'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(
                    () => errorText = e.toString().replaceFirst('FormatException: ', ''),
                  );
                }
              },
              child: const Text('校验并导入'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showAddCustomSourceDialog(SiteConfigProvider provider) async {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var selectedEngine = SourceEngineType.moebooru;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加自定义图源'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idCtrl,
                    decoration: const InputDecoration(
                      labelText: '图源 ID（小写字母/数字/下划线）',
                      hintText: '例如：my_moebooru',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '显示名称',
                      hintText: '例如：My Booru',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<SourceEngineType>(
                    initialValue: selectedEngine,
                    decoration: const InputDecoration(labelText: '协议引擎'),
                    items: SourceEngineType.values
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedEngine = val);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: baseUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: '站点根地址 (Base URL)',
                      hintText: 'https://example.com',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: '简介说明（选填）',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final candidate = SourceConfigParser.validateAndBuild({
                    'id': idCtrl.text.trim().toLowerCase(),
                    'name': nameCtrl.text.trim(),
                    'engine': selectedEngine.name,
                    'baseUrl': baseUrlCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'capabilities': {
                      'supportsSafeMode': true,
                      'supportsArtistFilter': true,
                    },
                  }, forceDisabled: true);

                  await provider.addOrUpdateCustomSource(candidate);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已添加图源「${candidate.name}」，可按需开启使用'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  setDialogState(
                    () => errorText = e.toString().replaceFirst('FormatException: ', ''),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    idCtrl.dispose();
    nameCtrl.dispose();
    baseUrlCtrl.dispose();
    descCtrl.dispose();
  }

  void _showDeveloperTemplateDialog() {
    var mode = 0; // 0: JSON 模板, 1: Dart 适配器骨架
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final codeText = mode == 0
              ? SourceDeveloperTemplate.jsonTemplate
              : SourceDeveloperTemplate.dartAdapterSkeleton;
          return AlertDialog(
            title: const Text('图源开发模板'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('JSON 清单模板')),
                        ButtonSegment(value: 1, label: Text('Dart 适配器骨架')),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) {
                        setDialogState(() => mode = s.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest
                            .withAlpha(130),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        codeText,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('复制代码'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: codeText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('模板已复制到剪贴板'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final provider = context.watch<SiteConfigProvider>();
    final sources = provider.allSources;
    final enabledCount = provider.enabledSources.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('图源管理'),
        actions: [
          IconButton(
            tooltip: '添加图源',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddCustomSourceDialog(provider),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'import') {
                _showImportJsonDialog(provider);
              } else if (value == 'template') {
                _showDeveloperTemplateDialog();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'import',
                child: Text('导入 JSON 配置'),
              ),
              PopupMenuItem(
                value: 'template',
                child: Text('查看配置模板'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '已启用 $enabledCount / ${sources.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...sources.map((source) {
            final isActive = source.id == provider.currentSourceId;
            final health = provider.healthStateFor(source.id);
            final isTesting = _testingIds.contains(source.id);
            final requiresAuth =
                source.authType == SourceAuthType.userIdApiKey;

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              color: cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isActive
                      ? cs.primary
                      : cs.outlineVariant.withAlpha(90),
                  width: isActive ? 1.4 : 0.8,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                                  if (!source.isBuiltIn) ...[
                                    const SizedBox(width: 8),
                                    _BadgePill(
                                      label: '自定义',
                                      background: cs.surfaceContainerHighest,
                                      foreground: cs.onSurfaceVariant,
                                    ),
                                  ],
                                  if (isActive) ...[
                                    const SizedBox(width: 6),
                                    _BadgePill(
                                      label: '使用中',
                                      background: cs.primaryContainer,
                                      foreground: cs.onPrimaryContainer,
                                    ),
                                  ],
                                ],
                              ),
                              if (!source.isBuiltIn) ...[
                                const SizedBox(height: 3),
                                Text(
                                  source.cleanBaseUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (requiresAuth) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.key_rounded,
                                      size: 13,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '需配置 User ID 与 API Key',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Switch(
                          value: source.isEnabled,
                          onChanged: (val) async {
                            final ok = await provider.setSourceEnabled(
                              source.id,
                              val,
                            );
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('至少保留一个图源'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    if (health != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        health.isHealthy
                            ? '连接正常 (${health.lastLatencyMs ?? 0} ms)'
                            : '连接异常：${health.lastError ?? '请求失败'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: health.isHealthy ? cs.primary : cs.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (source.isEnabled && !isActive)
                          TextButton.icon(
                            icon: const Icon(Icons.check_circle_outline_rounded,
                                size: 16),
                            label: const Text('设为当前'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              provider.setSourceById(source.id);
                            },
                          ),
                        TextButton.icon(
                          icon: isTesting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.network_check_rounded,
                                  size: 16),
                          label: Text(isTesting ? '测试中' : '测试'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _testConnection(provider, source),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.key_outlined, size: 16),
                          label: const Text('账号'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              SakuraPageRoute(
                                builder: (_) => SiteAccountsPage(
                                  initialSourceId: source.id,
                                ),
                              ),
                            );
                          },
                        ),
                        if (!source.isBuiltIn)
                          TextButton.icon(
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 16, color: cs.error),
                            label: Text(
                              '删除',
                              style: TextStyle(color: cs.error),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              await provider.removeCustomSource(source.id);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _BadgePill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
