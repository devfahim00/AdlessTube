import 'dart:convert';
import 'dart:io';

/// Search-as-you-type suggestions.
///
/// Uses YouTube's public suggest endpoint (the same one the YouTube search
/// box uses), so results match what users expect while typing.
class SuggestionService {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  Future<List<String>> getSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.parse(
        'https://suggestqueries.google.com/complete/search'
        '?client=firefox&ds=yt&q=${Uri.encodeQueryComponent(q)}',
      );
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return const [];
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is List && data.length > 1 && data[1] is List) {
        return (data[1] as List)
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .take(10)
            .toList();
      }
    } catch (_) {
      // Network issues must never break typing — just return nothing.
    }
    return const [];
  }

  void dispose() {
    _client.close();
  }
}
