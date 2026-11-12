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
    '192.168.6.233:7890',
    '10.0.2.2:7890',
    '127.0.0.1:7890',
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
        _validationError = 'Invalid format. Expected host:port (e.g. 192.168.6.233:7890)';
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
          content: Text('Proxy mode saved: ${_mode.label}'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh System / Wi-Fi Proxy',
            onPressed: _refreshSystemProxy,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                              'Proxy Mode',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...ProxyMode.values.map((m) {
                            return RadioListTile<ProxyMode>(
                              value: m,
                              title: Text(m.label),
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
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save'),
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
                            : const Icon(Icons.wifi_find, size: 18),
                        label: Text(_testing ? 'Testing...' : 'Test Connection'),
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
    );
  }

  Widget _buildSystemProxyCard(ThemeData theme) {
    final detected = _systemProxy;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  detected != null ? Icons.wifi_tethering : Icons.public,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Detected System / Wi-Fi Proxy',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _refreshSystemProxy,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Detect'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detected != null
                  ? 'Active Proxy: ${detected.address}\nSource: ${detected.source}'
                  : 'No HTTP proxy mounted on Wi-Fi / OS.\nUsing direct / VPN connection (DIRECT).',
              style: theme.textTheme.bodyMedium,
            ),
            if (detected != null && detected.nonProxyHosts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Bypass hosts: ${detected.nonProxyHosts.join(", ")}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualProxyCard(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual HTTP Proxy Address',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _proxyController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'e.g. 192.168.6.233:7890',
                labelText: 'Proxy Host:Port',
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
    final color = res.success ? Colors.green : theme.colorScheme.error;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              res.success ? Icons.check_circle : Icons.error_outline,
              color: color,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res.success
                        ? 'Connection successful (${res.elapsedMs} ms)'
                        : 'Connection failed (${res.elapsedMs} ms)',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Route: ${res.effectiveDirective}',
                    style: theme.textTheme.bodySmall,
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
