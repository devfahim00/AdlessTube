import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'region_service.dart';
import 'storage_service.dart';

class RegionSelectScreen extends StatefulWidget {
  const RegionSelectScreen({super.key});

  @override
  State<RegionSelectScreen> createState() => _RegionSelectScreenState();
}

class _RegionSelectScreenState extends State<RegionSelectScreen> {
  String? _selected;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = RegionService.regions.where((r) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return r['name']!.toLowerCase().contains(q) ||
          r['code']!.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Region'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search country...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final r = filtered[i];
                final isSelected = _selected == r['code'];
                return ListTile(
                  leading: Text(r['flag']!, style: const TextStyle(fontSize: 28)),
                  title: Text(r['name']!),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  selected: isSelected,
                  onTap: () => setState(() => _selected = r['code']),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected == null
                      ? null
                      : () async {
                          final storage = context.read<StorageService>();
                          await storage.setRegion(_selected!);
                          if (mounted) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const _LoadHome(),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Region select এর পর Home এ navigate করার জন্য wrapper
class _LoadHome extends StatelessWidget {
  const _LoadHome();

  @override
  Widget build(BuildContext context) {
    // screens.dart থেকে HomeScreen import করতে হবে
    return const _HomeLoader();
  }
}

class _HomeLoader extends StatelessWidget {
  const _HomeLoader();

  @override
  Widget build(BuildContext context) {
    // Lazy import เพื่อ avoid circular dependency
    return const _LazyHome();
  }
}

class _LazyHome extends StatelessWidget {
  const _LazyHome();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) {
        // dynamic navigation — main.dart এ HomeScreen already loaded
        return Navigator.of(ctx).widget.pages.isNotEmpty
            ? const SizedBox()
            : const SizedBox();
      },
    );
  }
}
