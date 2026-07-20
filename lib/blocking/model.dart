import 'dart:convert';
import 'dart:io';

enum WebsiteFilterState {
  notInstalled,
  approvalRequired,
  configured,
  unavailable,
}

class WebsiteFilterStatus {
  const WebsiteFilterStatus(this.state, this.message, {this.active = false});
  const WebsiteFilterStatus.unavailable()
    : active = false,
      state = WebsiteFilterState.unavailable,
      message =
          'Website helper status is unavailable. Choose Refresh to retry.';
  final WebsiteFilterState state;
  final bool active;
  final String message;
  bool get configured => state == WebsiteFilterState.configured;
  bool get canEnable => {
    WebsiteFilterState.notInstalled,
    WebsiteFilterState.approvalRequired,
    WebsiteFilterState.unavailable,
  }.contains(state);
  String get label => switch (state) {
    WebsiteFilterState.notInstalled => 'Setup needed',
    WebsiteFilterState.approvalRequired => 'Finish helper setup',
    WebsiteFilterState.configured => 'Helper ready',
    WebsiteFilterState.unavailable => 'Unavailable',
  };
  static WebsiteFilterStatus decode(Object? value) {
    if (value is! Map ||
        value['status'] is! String ||
        value['message'] is! String ||
        (value['message'] as String).length > 1000) {
      throw const FormatException('Invalid website filter state.');
    }
    final state = WebsiteFilterState.values
        .where((s) => s.name == value['status'])
        .firstOrNull;
    if (state == null) {
      throw const FormatException('Unknown website filter state.');
    }
    if (value['active'] != null && value['active'] is! bool) {
      throw const FormatException('Invalid website protection state.');
    }
    return WebsiteFilterStatus(state, value['message'], active: value['active'] == true);
  }
}

const protectedBundleIds = {
  'io.github.albert2704.stint',
  'com.apple.finder',
  'com.apple.systempreferences',
  'com.apple.systemsettings',
  'com.apple.activitymonitor',
  'com.apple.terminal',
  'com.apple.loginwindow',
  'com.apple.systemuiserver',
  'com.apple.controlcenter',
  'com.apple.securityagent',
  'com.apple.keychainaccess',
  'com.google.chrome',
  'com.google.chrome.beta',
  'com.google.chrome.dev',
  'com.google.chrome.canary',
  'com.microsoft.edgemac',
  'com.microsoft.edgemac.beta',
  'com.microsoft.edgemac.dev',
  'com.microsoft.edgemac.canary',
};

/// A DNS host, not a substring or a URL path. URLs are accepted as input only.
String? normalizeBlockedDomain(String input) {
  final text = input.trim().toLowerCase();
  if (text.isEmpty || text.length > 2048 || text.contains(RegExp(r'\s'))) {
    return null;
  }
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      !uri.hasAuthority) {
    return null;
  }
  var host = uri.host;
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.length > 253 ||
      !host.contains('.') ||
      InternetAddress.tryParse(host) != null) {
    return null;
  }
  final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  if (host.split('.').any((part) => !label.hasMatch(part)) ||
      !RegExp(r'[a-z]').hasMatch(host.split('.').last) ||
      host.endsWith('.localhost')) {
    return null;
  }
  return host;
}

bool blockedDomainMatches(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

class BlockedApp {
  const BlockedApp({required this.bundleId, required this.name});
  final String bundleId;
  final String name;
  bool get isValid =>
      bundleId.length <= 255 &&
      RegExp(
        r'^[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+$',
      ).hasMatch(bundleId) &&
      !protectedBundleIds.contains(bundleId.toLowerCase()) &&
      name.trim().isNotEmpty &&
      name.length <= 200;
  Map<String, Object?> toJson() => {'bundleId': bundleId, 'name': name};
  static BlockedApp fromJson(Object? value) {
    if (value is! Map ||
        value['bundleId'] is! String ||
        value['name'] is! String) {
      throw const FormatException('Invalid app entry.');
    }
    final app = BlockedApp(bundleId: value['bundleId'], name: value['name']);
    if (!app.isValid) throw const FormatException('Invalid or protected app.');
    return app;
  }
}

class BlockerSettings {
  BlockerSettings({
    this.enabled = false,
    List<BlockedApp> apps = const [],
    List<String> domains = const [],
    this.bypassSessionId,
  }) : apps = List.unmodifiable(apps),
       domains = List.unmodifiable(domains);
  final bool enabled;
  final List<BlockedApp> apps;
  final List<String> domains;
  final String? bypassSessionId;
  Map<String, Object?> toJson() => {
    'version': 1,
    'enabled': enabled,
    'apps': apps.map((app) => app.toJson()).toList(),
    'domains': domains,
    'bypassSessionId': bypassSessionId,
  };
  static BlockerSettings decode(String source) {
    final json = jsonDecode(source);
    if (json is! Map ||
        json['version'] != 1 ||
        json['enabled'] is! bool ||
        json['apps'] is! List ||
        json['domains'] is! List ||
        (json['bypassSessionId'] != null &&
            json['bypassSessionId'] is! String)) {
      throw const FormatException('Invalid blocker settings.');
    }
    final apps = (json['apps'] as List).map(BlockedApp.fromJson).toList();
    final rawDomains = json['domains'] as List;
    if (apps.length > 100 ||
        rawDomains.length > 200 ||
        apps.map((app) => app.bundleId.toLowerCase()).toSet().length !=
            apps.length ||
        rawDomains.any(
          (domain) =>
              domain is! String || normalizeBlockedDomain(domain) != domain,
        ) ||
        rawDomains.toSet().length != rawDomains.length) {
      throw const FormatException('Invalid blocklist.');
    }
    return BlockerSettings(
      enabled: json['enabled'],
      apps: apps,
      domains: rawDomains.cast<String>(),
      bypassSessionId: json['bypassSessionId'],
    );
  }
}

abstract class BlockerStore {
  BlockerSettings load();
  void save(BlockerSettings settings);
}

class FileBlockerStore implements BlockerStore {
  FileBlockerStore(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/blocker.json');
  @override
  BlockerSettings load() => file.existsSync()
      ? BlockerSettings.decode(file.readAsStringSync())
      : BlockerSettings();
  @override
  void save(BlockerSettings settings) {
    final source = jsonEncode(settings.toJson());
    BlockerSettings.decode(source);
    directory.createSync(recursive: true);
    final staging = File('${file.path}.tmp');
    staging.writeAsStringSync(source, flush: true);
    staging.renameSync(file.path);
  }
}
