import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'blocker.dart';
import 'data/controller.dart';
import 'data/models.dart';
import 'music.dart';

/// A local snapshot of the settings needed to prepare one kind of focus.
class FocusProfile {
  const FocusProfile({
    required this.id,
    required this.name,
    required this.focusMinutes,
    required this.shortBreakMinutes,
    required this.longBreakMinutes,
    this.mode = FocusMode.pomodoro,
    required this.trackId,
    required this.volume,
    required this.followTimer,
    required this.ambientLevels,
    required this.blockingEnabled,
    required this.apps,
    required this.domains,
  });
  final String id, name, trackId;
  final int focusMinutes, shortBreakMinutes, longBreakMinutes;
  final FocusMode mode;
  final double volume;
  final bool followTimer, blockingEnabled;
  final Map<String, double> ambientLevels;
  final List<BlockedApp> apps;
  final List<String> domains;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'mode': mode.name,
    'trackId': trackId,
    'volume': volume,
    'followTimer': followTimer,
    'ambientLevels': ambientLevels,
    'blockingEnabled': blockingEnabled,
    'apps': apps.map((app) => app.toJson()).toList(),
    'domains': domains,
  };

  factory FocusProfile.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid profile.');
    final id = value['id'], name = value['name'], track = value['trackId'];
    final focus = value['focusMinutes'], short = value['shortBreakMinutes'];
    final long = value['longBreakMinutes'], volume = value['volume'];
    final ambient = value['ambientLevels'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 100 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        track is! String ||
        track.isEmpty ||
        track.length > 300 ||
        focus is! int ||
        focus < 1 ||
        focus > 120 ||
        short is! int ||
        short < 1 ||
        short > 60 ||
        long is! int ||
        long < 1 ||
        long > 60 ||
        volume is! num ||
        !volume.isFinite ||
        volume < 0 ||
        volume > 1 ||
        value['followTimer'] is! bool ||
        value['blockingEnabled'] is! bool ||
        ambient is! Map ||
        value['apps'] is! List ||
        value['domains'] is! List) {
      throw const FormatException('Invalid profile settings.');
    }
    final mode = FocusMode.values
        .where((m) => m.name == value['mode'])
        .firstOrNull;
    if (mode == null) throw const FormatException('Invalid focus mode.');
    final levels = <String, double>{'rain': 0, 'cafe': 0, 'brown_noise': 0};
    for (final entry in ambient.entries) {
      final level = entry.value;
      if (!levels.containsKey(entry.key) ||
          level is! num ||
          !level.isFinite ||
          level < 0 ||
          level > 1) {
        throw const FormatException('Invalid ambient levels.');
      }
      levels[entry.key as String] = level.toDouble();
    }
    final block = BlockerSettings.decode(
      jsonEncode({
        'version': 1,
        'enabled': value['blockingEnabled'],
        'apps': value['apps'],
        'domains': value['domains'],
      }),
    );
    return FocusProfile(
      id: id,
      name: name.trim(),
      focusMinutes: focus,
      shortBreakMinutes: short,
      longBreakMinutes: long,
      mode: mode,
      trackId: track,
      volume: volume.toDouble(),
      followTimer: value['followTimer'],
      ambientLevels: Map.unmodifiable(levels),
      blockingEnabled: block.enabled,
      apps: block.apps,
      domains: block.domains,
    );
  }

  FocusProfile renamed(String name) =>
      FocusProfile.fromJson({...toJson(), 'name': name});
}

abstract class FocusProfileStore {
  String? load();
  void save(String source);
}

class FileFocusProfileStore implements FocusProfileStore {
  FileFocusProfileStore(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/focus-profiles.json');
  @override
  String? load() => file.existsSync() ? file.readAsStringSync() : null;
  @override
  void save(String source) {
    directory.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(source, flush: true);
    temporary.renameSync(file.path);
  }
}

class FocusProfiles extends ChangeNotifier {
  FocusProfiles({
    required this.store,
    required this.timer,
    required this.music,
    required this.blocker,
  }) {
    timer.addListener(_changed);
    music.addListener(_changed);
    blocker.addListener(_changed);
    try {
      final source = store.load();
      if (source != null) {
        final value = jsonDecode(source);
        if (value is! Map ||
            value['version'] != 1 ||
            value['profiles'] is! List) {
          throw const FormatException('Invalid profile file.');
        }
        _profiles = (value['profiles'] as List)
            .map(FocusProfile.fromJson)
            .toList();
        _validate(_profiles);
        _selectedId = value['selectedId'] is String
            ? value['selectedId']
            : null;
        _initialized = true;
      }
    } catch (_) {
      available = false;
      error =
          'Could not read focus-profiles.json. Your saved profiles have been kept.';
    }
  }
  final FocusProfileStore store;
  final StintController timer;
  final FocusMusic music;
  final BlockerController blocker;
  List<FocusProfile> _profiles = [];
  List<FocusProfile> get profiles => List.unmodifiable(_profiles);
  String? _selectedId;
  bool _initialized = false, _disposed = false;
  bool available = true, busy = false;
  bool get needsInitialization => !_initialized;
  String? error, warning;
  FocusProfile? get activeProfile =>
      _profiles.where((p) => p.id == _selectedId && _matches(p)).firstOrNull;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Seed only when the profile control is first opened. Never applies settings.
  void initialize() {
    if (_initialized || !available || busy) return;
    try {
      _write(_starters(), null);
      _initialized = true;
    } catch (_) {
      error = 'Could not save starter profiles. Try again.';
      _changed();
    }
  }

  static List<FocusProfile> _starters() => [
    for (final entry in [
      ('coding', 'Coding', 'quiet_keys', 50, 10, 30),
      ('writing', 'Writing', 'warm_drift', 25, 5, 15),
      ('study', 'Study', 'night_study', 25, 5, 15),
    ])
      FocusProfile(
        id: entry.$1,
        name: entry.$2,
        trackId: entry.$3,
        focusMinutes: entry.$4,
        shortBreakMinutes: entry.$5,
        longBreakMinutes: entry.$6,
        volume: .25,
        followTimer: true,
        ambientLevels: const {'rain': 0, 'cafe': 0, 'brown_noise': 0},
        blockingEnabled: true,
        apps: const [],
        domains: const ['x.com', 'reddit.com', 'facebook.com'],
      ),
  ];

  FocusProfile snapshot({required String id, required String name}) {
    final s = timer.workspace.settings;
    return FocusProfile.fromJson(
      FocusProfile(
        id: id,
        name: name.trim(),
        focusMinutes: s.focusMinutes,
        shortBreakMinutes: s.shortBreakMinutes,
        longBreakMinutes: s.longBreakMinutes,
        mode: s.focusMode,
        trackId: music.selectedId,
        volume: music.volume,
        followTimer: music.followTimer,
        ambientLevels: music.ambientLevels,
        blockingEnabled: blocker.settings.enabled,
        apps: blocker.settings.apps,
        domains: blocker.settings.domains,
      ).toJson(),
    );
  }

  bool _matches(FocusProfile p) {
    final current = snapshot(id: p.id, name: p.name).toJson();
    return jsonEncode(current) == jsonEncode(p.toJson());
  }

  void _validate(List<FocusProfile> profiles) {
    if (profiles.length > 100 ||
        profiles.map((p) => p.id).toSet().length != profiles.length ||
        profiles.map((p) => p.name.toLowerCase()).toSet().length !=
            profiles.length) {
      throw const FormatException(
        'Use a unique profile name. Up to 100 profiles can be saved.',
      );
    }
    for (final p in profiles) {
      FocusProfile.fromJson(p.toJson());
    }
  }

  void _write(List<FocusProfile> profiles, String? selected) {
    _validate(profiles);
    store.save(
      jsonEncode({
        'version': 1,
        'profiles': profiles.map((p) => p.toJson()).toList(),
        'selectedId': selected,
      }),
    );
    final pendingId = timer.pendingAction?.externalActionId;
    if (pendingId != null && pendingId.startsWith('profile:')) {
      final id = pendingId.substring('profile:'.length);
      final before = _profiles.where((p) => p.id == id).firstOrNull;
      final after = profiles.where((p) => p.id == id).firstOrNull;
      if (jsonEncode(before?.toJson()) != jsonEncode(after?.toJson())) {
        timer.cancelPending();
      }
    }
    _profiles = List.of(profiles);
    _selectedId = selected;
    error = null;
    _changed();
  }

  bool _edit(void Function() action) {
    if (!available || busy) return false;
    try {
      action();
      return true;
    } on FormatException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not save profiles. Your previous profiles have been kept.';
    }
    _changed();
    return false;
  }

  bool saveCurrent(String name) => _edit(() {
    final p = snapshot(id: newId(), name: name);
    _write([..._profiles, p], p.id);
    _initialized = true;
  });
  bool updateCurrent(String id) => _edit(() {
    final old = _profiles.firstWhere((p) => p.id == id);
    final p = snapshot(id: id, name: old.name);
    _write([for (final item in _profiles) item.id == id ? p : item], id);
  });
  bool rename(String id, String name) => _edit(
    () => _write([
      for (final p in _profiles) p.id == id ? p.renamed(name.trim()) : p,
    ], _selectedId),
  );
  bool delete(String id) => _edit(
    () => _write(
      _profiles.where((p) => p.id != id).toList(),
      _selectedId == id ? null : _selectedId,
    ),
  );

  void requestApply(String id) {
    if (!available || busy) return;
    final profile = _profiles.where((p) => p.id == id).firstOrNull;
    if (profile == null) return;
    timer.requestExternalAction(
      id: 'profile:$id',
      title: 'Switch to ${profile.name}?',
      onConfirm: () => _apply(profile),
    );
  }

  Future<void> _apply(FocusProfile profile) async {
    if (_disposed || busy || !available) return;
    busy = true;
    error = null;
    warning = null;
    _selectedId = null;
    _changed();
    final previous = snapshot(id: '_previous', name: 'Previous settings');
    try {
      timer.applyProfileTimer(
        focus: profile.focusMinutes,
        shortBreak: profile.shortBreakMinutes,
        longBreak: profile.longBreakMinutes,
        mode: profile.mode,
      );
      if (timer.saveError != null) {
        throw StateError('Timer settings could not be saved.');
      }
      final applied = await music.applySoundProfile(
        selectedId: profile.trackId,
        volume: profile.volume,
        followTimer: profile.followTimer,
        ambientLevels: profile.ambientLevels,
      );
      if (!applied) {
        throw StateError(music.error ?? 'Sound settings could not be applied.');
      }
      await blocker.save(
        enabled: profile.blockingEnabled,
        apps: profile.apps,
        domains: profile.domains,
      );
      warning = music.profileWarning;
      // A missing imported track is an explicit fallback, not an exact profile match.
      _write(_profiles, warning == null ? profile.id : null);
    } catch (_) {
      var restored = true;
      try {
        timer.applyProfileTimer(
          focus: previous.focusMinutes,
          shortBreak: previous.shortBreakMinutes,
          longBreak: previous.longBreakMinutes,
          mode: previous.mode,
        );
        restored = timer.saveError == null;
        final restoredSound = await music.applySoundProfile(
          selectedId: previous.trackId,
          volume: previous.volume,
          followTimer: previous.followTimer,
          ambientLevels: previous.ambientLevels,
        );
        restored = restored && restoredSound;
        await blocker.save(
          enabled: previous.blockingEnabled,
          apps: previous.apps,
          domains: previous.domains,
        );
      } catch (_) {
        restored = false;
      }
      error = restored
          ? 'This profile could not be fully applied. The timer is ready but idle; previous settings were restored. Try again.'
          : 'This profile could not be fully applied. The timer is idle. Review Sound and Block distractions before starting.';
      _selectedId = null;
    } finally {
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    timer.removeListener(_changed);
    music.removeListener(_changed);
    blocker.removeListener(_changed);
    super.dispose();
  }
}
