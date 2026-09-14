/// সমর্থিত region গুলোর তালিকা
class RegionService {
  static const List<Map<String, String>> regions = [
    {'code': 'BD', 'name': 'Bangladesh', 'flag': '🇧🇩'},
    {'code': 'IN', 'name': 'India', 'flag': '🇮🇳'},
    {'code': 'US', 'name': 'United States', 'flag': '🇺🇸'},
    {'code': 'GB', 'name': 'United Kingdom', 'flag': '🇬🇧'},
    {'code': 'PK', 'name': 'Pakistan', 'flag': '🇵🇰'},
    {'code': 'NP', 'name': 'Nepal', 'flag': '🇳🇵'},
    {'code': 'LK', 'name': 'Sri Lanka', 'flag': '🇱🇰'},
    {'code': 'MY', 'name': 'Malaysia', 'flag': '🇲🇾'},
    {'code': 'SA', 'name': 'Saudi Arabia', 'flag': '🇸🇦'},
    {'code': 'AE', 'name': 'UAE', 'flag': '🇦🇪'},
    {'code': 'CA', 'name': 'Canada', 'flag': '🇨🇦'},
    {'code': 'AU', 'name': 'Australia', 'flag': '🇦🇺'},
    {'code': 'DE', 'name': 'Germany', 'flag': '🇩🇪'},
    {'code': 'FR', 'name': 'France', 'flag': '🇫🇷'},
    {'code': 'JP', 'name': 'Japan', 'flag': '🇯🇵'},
    {'code': 'KR', 'name': 'South Korea', 'flag': '🇰🇷'},
    {'code': 'ID', 'name': 'Indonesia', 'flag': '🇮🇩'},
    {'code': 'PH', 'name': 'Philippines', 'flag': '🇵🇭'},
    {'code': 'TH', 'name': 'Thailand', 'flag': '🇹🇭'},
    {'code': 'VN', 'name': 'Vietnam', 'flag': '🇻🇳'},
  ];

  static String nameFor(String code) {
    return regions.firstWhere(
      (r) => r['code'] == code,
      orElse: () => {'name': 'Unknown', 'flag': '🌍'},
    )['name']!;
  }

  static String flagFor(String code) {
    return regions.firstWhere(
      (r) => r['code'] == code,
      orElse: () => {'name': 'Unknown', 'flag': '🌍'},
    )['flag']!;
  }
}
