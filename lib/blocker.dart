import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'blocking/model.dart';
import 'data/controller.dart';
import 'data/models.dart';
export 'blocking/model.dart';

class BlockerController extends ChangeNotifier {
  BlockerController(
    this.timer, {
    required this.store,
    MethodChannel? channel,
    this.automaticHeartbeat = true,
  }) : channel = channel ?? const MethodChannel('stint/blocker');

  final StintController timer;
  final BlockerStore store;
  final MethodChannel channel;
  final bool automaticHeartbeat;
  BlockerSettings _settings = BlockerSettings();
  BlockerSettings get settings => _settings;
  Timer? _heartbeat;
  WebsiteFilterStatus filter = const WebsiteFilterStatus.unavailable();
  bool checkingFilter = false;
  bool enablingFilter = false;
  int _filterRequest = 0;
  String? _storageError, _nativeError, _filterError;
  String? get error => _storageError ?? _nativeError ?? _filterError;
  bool ready = false;
  bool _disposed = false;
  String? _previous;
  Future<void> _nativeQueue = Future.value();
  String? get sessionId => timer.timer.sessionId;
  bool get bypassed =>
      sessionId != null && settings.bypassSessionId == sessionId;
  bool get active =>
      ready &&
      settings.enabled &&
      !bypassed &&
      timer.timer.phase == TimerPhase.focus &&
      timer.timer.running &&
      sessionId != null &&
      (timer.isFlowFocus ||
          (timer.timer.endsAt != null &&
              timer.timer.endsAt!.isAfter(timer.now())));
  String get statusLabel {
    if (!ready) return 'Blocker unavailable';
    if (error != null) return 'Blocker needs attention';
    if (bypassed) return 'Unblocked for this stint';
    if (!settings.enabled) return 'Block distractions';
    if (settings.apps.isEmpty && settings.domains.isEmpty) {
      return 'Choose distractions to block';
    }
    if (!active) return 'Ready for your next focus';
    if (settings.domains.isNotEmpty) {
      if (!filter.configured) {
        return settings.apps.isEmpty
            ? 'Website helper setup needed'
            : 'App guard on · website helper setup needed';
      }
      if (!filter.active) {
        return settings.apps.isEmpty
            ? 'Website protection starting…'
            : 'App guard on · website protection starting…';
      }
    }
    return 'Focus guard on';
  }

  Future<void> initialize() async {
    try {
      _settings = store.load();
      ready = true;
    } catch (_) {
      _storageError =
          'Could not read blocker.json. Your saved blocklist has been kept.';
    }
    if (_disposed) return;
    channel.setMethodCallHandler(_handle);
    timer.addListener(_sync);
    if (automaticHeartbeat) {
      _heartbeat = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _sync(force: true),
      );
    }
    _sync(force: true);
    await refreshFilter();
    _notify();
  }

  Map<String, Object?> get nativeState {
    final now = timer.now().millisecondsSinceEpoch;
    // Flow has no planned end. Renew the same short lease used for crash
    // recovery so native protection cannot outlive a stalled controller.
    final deadline = timer.isFlowFocus
        ? now + 30000
        : timer.timer.endsAt?.millisecondsSinceEpoch;
    final isActive = active;
    return {
      'active': isActive,
      'flowFocus': timer.isFlowFocus,
      'sessionId': sessionId,
      'deadlineMilliseconds': deadline,
      'leaseExpiresAt': isActive ? min(now + 30000, deadline!) : now + 30000,
      'domains': settings.domains,
      'apps': settings.apps.map((app) => app.toJson()).toList(),
      'appearance': timer.workspace.settings.appearance,
    };
  }

  Future<void> refreshFilter() => _loadFilterStatus();

  Future<void> enableFilter() => _loadFilterStatus(enable: true);

  Future<void> removeFilter() => _loadFilterStatus(remove: true);

  Future<void> _loadFilterStatus({
    bool enable = false,
    bool remove = false,
  }) async {
    if (_disposed || checkingFilter) return;
    final request = ++_filterRequest;
    checkingFilter = true;
    enablingFilter = enable;
    _notify();
    try {
      final raw = await channel.invokeMethod<Object?>(
        remove ? 'removeFilter' : (enable ? 'enableFilter' : 'filterStatus'),
      );
      if (_disposed || request != _filterRequest) return;
      filter = WebsiteFilterStatus.decode(raw);
      _filterError = null;
    } catch (_) {
      if (_disposed || request != _filterRequest) return;
      filter = const WebsiteFilterStatus.unavailable();
      _filterError =
          'Website helper unavailable. Choose Refresh to reconnect. App blocking is independent.';
    } finally {
      if (!_disposed) {
        checkingFilter = false;
        enablingFilter = false;
        _notify();
      }
    }
  }

  bool relaxesProtection({
    required bool enabled,
    required List<BlockedApp> apps,
    required List<String> domains,
  }) {
    if (!active) return false;
    if (!enabled) return true;
    final ids = apps.map((app) => app.bundleId.toLowerCase()).toSet();
    return settings.apps.any(
          (app) => !ids.contains(app.bundleId.toLowerCase()),
        ) ||
        settings.domains.any(
          (old) => !domains.any((domain) => blockedDomainMatches(old, domain)),
        );
  }

  Future<void> save({
    required bool enabled,
    required List<BlockedApp> apps,
    required List<String> domains,
  }) async {
    if (!ready || _disposed) {
      throw StateError('Blocker settings are unavailable.');
    }
    final normalized = <String>[];
    for (final input in domains) {
      final host = normalizeBlockedDomain(input);
      if (host == null) {
        throw const FormatException('Enter a valid website domain.');
      }
      if (!normalized.contains(host)) normalized.add(host);
    }
    final uniqueApps = <String, BlockedApp>{};
    for (final app in apps) {
      if (!app.isValid) {
        throw const FormatException('This app cannot be blocked.');
      }
      uniqueApps[app.bundleId.toLowerCase()] = app;
    }
    final next = BlockerSettings(
      enabled: enabled,
      apps: uniqueApps.values.toList(),
      domains: normalized,
      bypassSessionId: settings.bypassSessionId,
    );
    BlockerSettings.decode(jsonEncode(next.toJson()));
    _persist(next);
  }

  Future<void> unblock(String expectedSessionId) async {
    if (!active || expectedSessionId != sessionId) return;
    _persist(
      BlockerSettings(
        enabled: settings.enabled,
        apps: settings.apps,
        domains: settings.domains,
        bypassSessionId: expectedSessionId,
      ),
    );
  }

  void _persist(BlockerSettings next) {
    try {
      store.save(next);
      _settings = next;
      _storageError = null;
    } catch (_) {
      _storageError =
          'Could not save the blocklist. Your previous settings are still in use.';
      _notify();
      throw StateError(_storageError!);
    }
    _sync(force: true);
  }

  Future<List<BlockedApp>> chooseApps() async {
    final raw = await channel.invokeListMethod<Object?>('chooseApps') ?? [];
    return raw.map(BlockedApp.fromJson).toList();
  }

  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    final args = call.arguments;
    if (call.method == 'unblock' &&
        args is Map &&
        args['sessionId'] is String) {
      await unblock(args['sessionId']);
    } else if (call.method == 'status' && args is Map) {
      _nativeError = args['error'] is String ? args['error'] : null;
      _notify();
    } else if (call.method == 'filter') {
      ++_filterRequest;
      try {
        filter = WebsiteFilterStatus.decode(args);
        _filterError = null;
      } catch (_) {
        filter = const WebsiteFilterStatus.unavailable();
        _filterError =
            'Website helper returned an unknown state. Choose Refresh to retry.';
      }
      _notify();
    }
  }

  void _sync({bool force = false}) {
    if (_disposed) return;
    final current = nativeState;
    final comparison = jsonEncode({...current, 'leaseExpiresAt': null});
    if (force || comparison != _previous) {
      _previous = comparison;
      final native = current;
      _nativeQueue = _nativeQueue.then((_) async {
        if (_disposed) return;
        try {
          await channel.invokeMethod<void>('update', native);
        } catch (_) {
          _nativeError =
              'App blocking is unavailable. Reopen Stint to reconnect.';
          _notify();
        }
      });
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    timer.removeListener(_sync);
    _heartbeat?.cancel();
    channel.setMethodCallHandler(null);
    unawaited(
      channel
          .invokeMethod<void>('update', {'active': false})
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
