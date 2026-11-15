import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  final TextEditingController _customPathController = TextEditingController();
  final SettingsService _settingsService = SettingsService();

  DownloadStoragePreset _selectedPreset = DownloadStoragePreset.publicPictures;
  DownloadQuality _selectedQuality = DownloadQuality.original;
  Map<DownloadStoragePreset, String> _resolvedPaths = {};
  String _activePath = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final preset = await _settingsService.getDownloadPreset();
    final quality = await _settingsService.getDownloadQuality();
    final savedPath = await _settingsService.getDownloadPath();

    final Map<DownloadStoragePreset, String> paths = {};
    for (final p in DownloadStoragePreset.values) {
      if (p == DownloadStoragePreset.custom) {
        paths[p] = savedPath ?? '';
      } else {
        paths[p] = await _settingsService.resolvePathForPreset(p);
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedPreset = preset;
      _selectedQuality = quality;
      _resolvedPaths = paths;
      _activePath = savedPath ?? paths[preset] ?? '';
      _customPathController.text = _activePath;
      _isLoading = false;
    });
  }

  Future<void> _selectDownloadQuality(DownloadQuality quality) async {
    await _settingsService.setDownloadQuality(quality);
    if (!mounted) return;
    setState(() => _selectedQuality = quality);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          quality == DownloadQuality.original
              ? '默认下载画质已设为：原图'
              : '默认下载画质已设为：中等尺寸',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _selectPreset(DownloadStoragePreset preset) async {
    if (preset == DownloadStoragePreset.custom) {
      setState(() {
        _selectedPreset = preset;
      });
      return;
    }

    await _settingsService.setDownloadPreset(preset);
    final newPath = await _settingsService.getDownloadPath() ?? '';
    if (!mounted) return;
    setState(() {
      _selectedPreset = preset;
      _activePath = newPath;
      _customPathController.text = newPath;
    });

    try {
      await context.read<BaseDownloadNotifier>().scanForDownloadedImages();
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换下载位置：${preset.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickCustomFolder() async {
    String? selectedDirectory;
    try {
      selectedDirectory = await FilePicker.getDirectoryPath();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开系统文件夹选择器失败: $e')),
        );
      }
      return;
    }

    if (selectedDirectory != null && selectedDirectory.trim().isNotEmpty) {
      await _settingsService.setDownloadPreset(
        DownloadStoragePreset.custom,
        customPath: selectedDirectory.trim(),
      );
      final resolved = await _settingsService.getDownloadPath() ?? selectedDirectory.trim();
      if (!mounted) return;
      setState(() {
        _selectedPreset = DownloadStoragePreset.custom;
        _activePath = resolved;
        _customPathController.text = resolved;
        _resolvedPaths[DownloadStoragePreset.custom] = resolved;
      });
      try {
        await context.read<BaseDownloadNotifier>().scanForDownloadedImages();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已设置自定义下载路径：$resolved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveCustomPathText() async {
    final text = _customPathController.text.trim();
    if (text.isEmpty) return;
    await _settingsService.setDownloadPreset(
      DownloadStoragePreset.custom,
      customPath: text,
    );
    final resolved = await _settingsService.getDownloadPath() ?? text;
    if (!mounted) return;
    setState(() {
      _selectedPreset = DownloadStoragePreset.custom;
      _activePath = resolved;
      _customPathController.text = resolved;
    });
    try {
      await context.read<BaseDownloadNotifier>().scanForDownloadedImages();
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存下载路径：$resolved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('下载路径')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final presets = Platform.isAndroid
        ? DownloadStoragePreset.values
        : Platform.isIOS
            ? [
                DownloadStoragePreset.publicDownloads,
                DownloadStoragePreset.appPrivate,
                DownloadStoragePreset.custom,
              ]
            : [
                DownloadStoragePreset.publicDownloads,
                DownloadStoragePreset.appPrivate,
                DownloadStoragePreset.custom,
              ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('下载设置'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RadioGroup<DownloadQuality>(
                groupValue: _selectedQuality,
                onChanged: (val) {
                  if (val != null) {
                    _selectDownloadQuality(val);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        '默认画质',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const RadioListTile<DownloadQuality>(
                      value: DownloadQuality.original,
                      title: Text('原图'),
                    ),
                    const RadioListTile<DownloadQuality>(
                      value: DownloadQuality.sample,
                      title: Text('中等尺寸'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(Icons.folder_outlined, color: cs.primary),
              title: const Text('当前保存路径'),
              subtitle: SelectableText(
                _activePath,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RadioGroup<DownloadStoragePreset>(
                groupValue: _selectedPreset,
                onChanged: (val) {
                  if (val != null) {
                    _selectPreset(val);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        '存储目录',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...presets.map((preset) {
                      final resolved = _resolvedPaths[preset] ?? '';
                      return RadioListTile<DownloadStoragePreset>(
                        value: preset,
                        title: Text(preset.title),
                        subtitle: Text(
                          resolved.isNotEmpty && preset != DownloadStoragePreset.custom
                              ? resolved
                              : preset.subtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: resolved.isNotEmpty &&
                                    preset != DownloadStoragePreset.custom
                                ? 'monospace'
                                : null,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '自定义路径',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customPathController,
                    decoration: InputDecoration(
                      labelText: '文件夹路径',
                      hintText: '/storage/emulated/0/Pictures/SakuraView',
                      prefixIcon: const Icon(Icons.folder_outlined),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open_rounded),
                        tooltip: '选择文件夹',
                        onPressed: _pickCustomFolder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickCustomFolder,
                          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                          label: const Text('浏览'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saveCustomPathText,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}
