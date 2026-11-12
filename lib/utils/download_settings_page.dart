import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  final TextEditingController _downloadPathController = TextEditingController();
  final SettingsService _settingsService = SettingsService();
  String _defaultPath = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloadPath();
  }

  Future<void> _loadDownloadPath() async {
    setState(() {
      _isLoading = true;
    });

    _defaultPath = await _settingsService.getDefaultDownloadPath();
    final String? savedPath = await _settingsService.getDownloadPath();

    setState(() {
      _downloadPathController.text = savedPath ?? _defaultPath;
      _isLoading = false;
    });
  }

  Future<void> _pickDownloadPath() async {
    String? selectedDirectory;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      selectedDirectory = await FilePicker.getDirectoryPath();
    } else if (Platform.isAndroid || Platform.isIOS) {
      selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot select custom directory, using default.'),
            ),
          );
        }
        selectedDirectory = _defaultPath;
      }
    }

    if (selectedDirectory != null) {
      setState(() {
        _downloadPathController.text = selectedDirectory!;
      });
    }
  }

  Future<void> _saveDownloadPath() async {
    final path = _downloadPathController.text.trim();
    if (path.isEmpty) {
      await _settingsService.setDownloadPath(_defaultPath);
      setState(() {
        _downloadPathController.text = _defaultPath;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download path reset to default.')),
        );
      }
    } else {
      await _settingsService.setDownloadPath(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download path saved.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _downloadPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Download Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Current Download Path:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _downloadPathController,
              readOnly: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickDownloadPath,
                ),
                hintText: 'Click to select download path',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Default Path: $_defaultPath',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                onPressed: _saveDownloadPath,
                child: const Text('Save Download Path'),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _downloadPathController.text = _defaultPath;
                  });
                  _saveDownloadPath();
                },
                child: const Text('Reset to Default Path'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
