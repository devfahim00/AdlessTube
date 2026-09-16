import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'storage_service.dart';

class ServiceSelectScreen extends StatefulWidget {
  /// When true, this is opened from Menu (can go back). When false, first-launch flow.
  final bool fromMenu;

  const ServiceSelectScreen({super.key, this.fromMenu = false});

  @override
  State<ServiceSelectScreen> createState() => _ServiceSelectScreenState();
}

class _ServiceSelectScreenState extends State<ServiceSelectScreen> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    // On first launch start with all selected; from menu use current
    _selected = Set<String>.from(storage.enabledServices);
  }

  void _toggle(String key) {
    setState(() {
      if (_selected.contains(key)) {
        // Keep at least one
        if (_selected.length > 1) _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  Future<void> _continue() async {
    await context.read<StorageService>().setEnabledServices(_selected);
    if (widget.fromMenu && mounted) {
      Navigator.pop(context);
    }
    // If first launch, _RootRouter will automatically switch to MainShell
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        StorageService.serviceYoutube,
        Icons.play_circle_filled,
        'YouTube',
        'Home feed, search, channels & videos'
      ),
      (
        StorageService.serviceShorts,
        Icons.slideshow,
        'Shorts',
        'Vertical short videos'
      ),
      (
        StorageService.serviceMusic,
        Icons.music_note,
        'Music',
        'Music player & discovery'
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromMenu ? 'Manage Services' : 'Choose Services'),
        automaticallyImplyLeading: widget.fromMenu,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              widget.fromMenu
                  ? 'Enable or disable the sections you want to use.'
                  : 'Select which features you want in the app. You can change this later from Menu.',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ),
          Expanded(
            child: ListView(
              children: items.map((item) {
                final (key, icon, title, subtitle) = item;
                final selected = _selected.contains(key);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => _toggle(key),
                  secondary: Icon(
                    icon,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    size: 28,
                  ),
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle),
                  activeColor: Theme.of(context).colorScheme.primary,
                );
              }).toList(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected.isEmpty ? null : _continue,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    widget.fromMenu ? 'Save' : 'Continue',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
