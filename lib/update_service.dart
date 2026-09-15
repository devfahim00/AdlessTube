import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  final String tag;
  final Uri url;

  const AppUpdate({required this.tag, required this.url});
}

class UpdateService {
  static final _latestRelease = Uri.parse(
    'https://api.github.com/repos/devfahim00/AdlessTube/releases/latest',
  );

  static Future<AppUpdate?> checkForUpdate() async {
    final client = HttpClient();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // pubspec-এর version

      final request = await client.getUrl(_latestRelease);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'AdlessTube/$currentVersion',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await utf8.decoder.bind(response).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final htmlUrl = json['html_url'] as String?;

      if (tag.isEmpty ||
          htmlUrl == null ||
          !_isNewer(tag, currentVersion)) {
        return null;
      }
      return AppUpdate(tag: tag, url: Uri.parse(htmlUrl));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isNewer(String latest, String current) {
    List<int> parse(String version) => version
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final a = parse(latest);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }
}
