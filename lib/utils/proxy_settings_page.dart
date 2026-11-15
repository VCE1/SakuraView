import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/services/proxy_config.dart';

class ProxySettingsPage extends StatefulWidget {
  const ProxySettingsPage({super.key});

  @override
  State<ProxySettingsPage> createState() => _ProxySettingsPageState();
}

class _ProxySettingsPageState extends State<ProxySettingsPage> {
  final TextEditingController _proxyController = TextEditingController();
  ProxyMode _mode = ProxyMode.system;
  SystemProxyInfo? _systemProxy;
  bool _loading = true;
  bool _testing = false;
  ProxyTestResult? _testResult;
  String? _validationError;

  static const List<String> _presetAddresses = [
    '127.0.0.1:7890',
    '127.0.0.1:10809',
    '10.0.2.2:7890',
    '192.168.6.233:7890',
  ];

  @override
  void initState() {
    super.initState();
    _loadProxySettings();
  }

  Future<void> _loadProxySettings() async {
    final mode = await ProxyConfig.getProxyMode();
    final proxyAddress = await ProxyConfig.getProxyAddress();
    final sysProxy = await ProxyConfig.getSystemProxyInfo();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _proxyController.text = proxyAddress;
      _systemProxy = sysProxy;
      _loading = false;
    });
  }

  Future<void> _refreshSystemProxy() async {
    final sysProxy = await ProxyConfig.getSystemProxyInfo();
    await ProxyConfig.refreshGlobalHttpOverrides();
    if (!mounted) return;
    setState(() {
      _systemProxy = sysProxy;
      _testResult = null;
    });
  }

  Future<bool> _saveProxySettings({bool showSnack = true}) async {
    final normalized = ProxyConfig.normalizeProxyAddress(_proxyController.text);
    if (_mode == ProxyMode.manual && !ProxyConfig.isValidProxyAddress(normalized)) {
      setState(() {
        _validationError = '格式无效，请输入 Host:Port（例如 127.0.0.1:7890）';
      });
      return false;
    }

    setState(() {
      _validationError = null;
      _proxyController.text = normalized;
    });

    await ProxyConfig.saveProxyAddress(normalized);
    await ProxyConfig.saveProxyMode(_mode);

    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('网络代理配置已保存：${_mode.label}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  }

  Future<void> _testConnection() async {
    final saved = await _saveProxySettings(showSnack: false);
    if (!saved) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final result = await ProxyConfig.testConnectionWithDetails();

    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = result;
      });
    }
  }

  @override
  void dispose() {
    _proxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('网络代理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: _refreshSystemProxy,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
              children: <Widget>[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: RadioGroup<ProxyMode>(
                      groupValue: _mode,
                      onChanged: (ProxyMode? value) {
                        if (value != null) {
                          setState(() {
                            _mode = value;
                            _validationError = null;
                            _testResult = null;
                          });
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              '代理路由策略',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...ProxyMode.values.map((m) {
                            return RadioListTile<ProxyMode>(
                              value: m,
                              title: Text(
                                m.label,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                m.subtitle,
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_mode == ProxyMode.system) _buildSystemProxyCard(theme),
                if (_mode == ProxyMode.manual) _buildManualProxyCard(theme),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _saveProxySettings(showSnack: true),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: const Text('应用并保存'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !_testing ? _testConnection : null,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_check_rounded, size: 18),
                        label: Text(_testing ? '正在检测连通性...' : '连通性测试'),
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 16),
                  _buildTestResultCard(theme, _testResult!),
                ],
              ],
                ),
              ),
            ),
    );
  }

  Widget _buildSystemProxyCard(ThemeData theme) {
    final detected = _systemProxy;
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Icon(
              detected != null ? Icons.hub_rounded : Icons.public_rounded,
              color: cs.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detected != null
                        ? '系统代理：${detected.address}'
                        : '当前：直接连接 (DIRECT)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (detected != null && detected.nonProxyHosts.isNotEmpty)
                    Text(
                      '绕过：${detected.nonProxyHosts.join(", ")}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: _refreshSystemProxy,
              child: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualProxyCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '自定义 HTTP 代理服务器',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _proxyController,
              decoration: InputDecoration(
                hintText: '例如 127.0.0.1:7890',
                labelText: '代理地址 (Host:Port)',
                errorText: _validationError,
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) {
                setState(() {
                  _validationError = null;
                  _testResult = null;
                });
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _presetAddresses.map((addr) {
                return ActionChip(
                  label: Text(addr, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      _proxyController.text = addr;
                      _validationError = null;
                      _testResult = null;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestResultCard(ThemeData theme, ProxyTestResult res) {
    final color = res.success ? theme.colorScheme.primary : theme.colorScheme.error;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              res.success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res.success
                        ? '连接正常 (${res.elapsedMs} ms)'
                        : '连接失败 (${res.elapsedMs} ms)',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (res.errorMessage != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      res.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
