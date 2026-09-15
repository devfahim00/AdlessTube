import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../region_service.dart';
import '../storage_service.dart';

class RegionChangeScreen extends StatelessWidget {
  const RegionChangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Region')),
      body: ListView.builder(
        itemCount: RegionService.regions.length,
        itemBuilder: (_, i) {
          final r = RegionService.regions[i];
          final storage = context.read<StorageService>();
          final isSelected = storage.regionCode == r['code'];
          return ListTile(
            leading:
                Text(r['flag']!, style: const TextStyle(fontSize: 28)),
            title: Text(r['name']!),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            selected: isSelected,
            onTap: () async {
              await context.read<StorageService>().setRegion(r['code']!);
              if (context.mounted) Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
