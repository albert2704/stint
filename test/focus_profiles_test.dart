import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:stint/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/blocker.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';
import 'package:stint/focus_profiles.dart';
import 'package:stint/music.dart';

class ProfileStore implements FocusProfileStore {
  String? source;
  bool fail = false;
  @override
  String? load() => source;
  @override
  void save(String value) {
    if (fail) throw StateError('disk full');
    source = value;
  }
}

class BlockStore implements BlockerStore {
  BlockerSettings value = BlockerSettings();
  bool fail = false;
  @override
  BlockerSettings load() => value;
  @override
  void save(BlockerSettings value) {
    if (fail) throw StateError('disk full');
    this.value = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StintController timer;
  late FocusMusic music;
  late BlockerController blocker;
  late FocusProfiles profiles;
  late ProfileStore store;
  late BlockStore blockStore;
  late List<String> calls;
  late Map<String, Object?> sound;
  late DateTime now;
  bool failSound = false;
  setUp(() async {
    calls = [];
    failSound = false;
    sound = {
      'selectedId': 'quiet_keys',
      'volume': .35,
      'followTimer': false,
      'playing': false,
      'ambientPlaying': false,
      'ambientLevels': {'rain': 0.0, 'cafe': 0.0, 'brown_noise': 0.0},
      'tracks': [],
    };
    messenger.setMockMethodCallHandler(const MethodChannel('stint/music'), (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'applyProfile') {
        if (failSound) {
          throw PlatformException(code: 'failed', message: 'Unavailable');
        }
        sound.addAll(Map<String, Object?>.from(call.arguments as Map));
        sound['playing'] = false;
        sound['ambientPlaying'] = false;
      }
      return sound;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('stint/blocker'), (
      call,
    ) async {
      if (call.method == 'filterStatus') return {'state': 'notInstalled'};
      return null;
    });
    now = DateTime(2026, 10, 20, 10);
    timer = StintController(
      MemoryWorkspaceStore(),
      now: () => now,
      tickAutomatically: false,
    );
    music = FocusMusic();
    await music.load();
    blockStore = BlockStore();
    blocker = BlockerController(
      timer,
      store: blockStore,
      automaticHeartbeat: false,
    );
    await blocker.initialize();
    store = ProfileStore();
    profiles = FocusProfiles(
      store: store,
      timer: timer,
      music: music,
      blocker: blocker,
    );
  });
  tearDown(() {
    profiles.dispose();
    blocker.dispose();
    music.dispose();
    timer.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('stint/music'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('stint/blocker'),
      null,
    );
  });
  Future<void> settleProfile() async {
    for (var i = 0; i < 30 && timer.externalActionBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(timer.externalActionBusy, false);
  }

  test(
    'first use seeds profiles without changing timer, audio or protection',
    () {
      final before = timer.workspace.encode();
      final previousCalls = List.of(calls);
      expect(profiles.profiles, isEmpty);
      profiles.initialize();
      expect(profiles.profiles.map((p) => p.name), [
        'Coding',
        'Writing',
        'Study',
      ]);
      expect(timer.workspace.encode(), before);
      expect(calls, previousCalls);
      expect(blocker.settings.enabled, false);
      expect(profiles.activeProfile, isNull);
      final saved = store.source;
      profiles.initialize();
      expect(store.source, saved);
    },
  );

  test('cancel pending profile preserves every subsystem', () async {
    profiles.initialize();
    timer.startTimer();
    now = now.add(const Duration(minutes: 2));
    final before = timer.workspace.encode();
    final previousCalls = List.of(calls);
    profiles.requestApply('coding');
    expect(timer.pendingAction?.kind, 'external');
    timer.cancelPending();
    await settleProfile();
    expect(timer.workspace.encode(), before);
    expect(calls, previousCalls);
    expect(blocker.settings.enabled, false);
  });

  test(
    'confirmed profile prepares idle focus and silently applies sound and blocker',
    () async {
      profiles.initialize();
      timer.startTimer();
      profiles.requestApply('writing');
      timer.confirmPending();
      await settleProfile();
      expect(timer.timer.running, false);
      expect(timer.timer.phase, TimerPhase.focus);
      expect(music.selectedId, 'warm_drift');
      expect(music.playing, false);
      expect(blocker.settings.enabled, true);
      expect(blocker.active, false);
      expect(blocker.settings.domains, contains('x.com'));
      expect(profiles.activeProfile?.id, 'writing');
    },
  );

  test(
    'saved snapshots include Flow and mixer; CRUD rejects duplicate names and disk errors',
    () {
      profiles.initialize();
      timer.applyMode(FocusMode.flow);
      expect(profiles.saveCurrent('My setup'), true);
      final custom = profiles.profiles.last;
      expect(custom.mode, FocusMode.flow);
      expect(
        custom.ambientLevels.keys,
        containsAll(['rain', 'cafe', 'brown_noise']),
      );
      expect(profiles.rename(custom.id, 'Writing'), false);
      expect(profiles.profiles.last.name, 'My setup');
      expect(profiles.rename(custom.id, 'Evening'), true);
      store.fail = true;
      expect(profiles.delete(custom.id), false);
      expect(profiles.profiles.last.id, custom.id);
      store.fail = false;
      expect(profiles.delete(custom.id), true);
    },
  );

  test(
    'failed sound apply reports partial failure without claiming an active profile',
    () async {
      profiles.initialize();
      failSound = true;
      profiles.requestApply('coding');
      await settleProfile();
      expect(profiles.activeProfile, isNull);
      expect(profiles.error, contains('could not be fully applied'));
      expect(timer.timer.running, false);
      expect(blocker.settings.enabled, false);
    },
  );

  test('corrupt saved profiles are preserved and cannot be overwritten', () {
    profiles.dispose();
    store.source = '{broken';
    profiles = FocusProfiles(
      store: store,
      timer: timer,
      music: music,
      blocker: blocker,
    );
    profiles.initialize();
    expect(profiles.available, false);
    expect(profiles.saveCurrent('New'), false);
    expect(store.source, '{broken');
  });

  test('deleting every profile does not reseed after relaunch', () {
    profiles.initialize();
    for (final profile in profiles.profiles) {
      profiles.delete(profile.id);
    }
    profiles.dispose();
    profiles = FocusProfiles(
      store: store,
      timer: timer,
      music: music,
      blocker: blocker,
    );
    profiles.initialize();
    expect(profiles.profiles, isEmpty);
  });

  test(
    'profile file round trips independently of workspace and rejects invalid settings',
    () {
      profiles.initialize();
      final dir = Directory.systemTemp.createTempSync('stint-profiles-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = FileFocusProfileStore(dir);
      file.save(store.source!);
      expect(file.load(), store.source);
      expect(
        () => FocusProfile.fromJson({
          ...profiles.profiles.first.toJson(),
          'volume': double.nan,
        }),
        throwsFormatException,
      );
      expect(
        () => FocusProfile.fromJson({
          ...profiles.profiles.first.toJson(),
          'domains': ['not a domain'],
        }),
        throwsFormatException,
      );
    },
  );
  test('editing a profile invalidates its old pending application', () {
    profiles.initialize();
    timer.startTimer();
    profiles.requestApply('coding');
    expect(timer.pendingAction, isNotNull);
    profiles.rename('coding', 'Development');
    expect(timer.pendingAction, isNull);
    timer.confirmPending();
    expect(timer.workspace.settings.focusMinutes, 25);
    expect(blocker.settings.enabled, false);
  });

  testWidgets(
    'profile sheet saves and renames current setup in compact window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(StintApp(controller: timer, profiles: profiles));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Main compact layout');
      await tester.tap(find.byKey(const Key('focus-profiles')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Profiles compact layout');
      expect(find.text('Coding'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('save-current-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-current-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-name')), 'Evening');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(profiles.profiles.last.name, 'Evening');
      await tester.ensureVisible(find.byTooltip('Evening options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Evening options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-name')), 'Night');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(profiles.profiles.last.name, 'Night');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile selection closes sheet and uses shared timer confirmation',
    (tester) async {
      timer.startTimer();
      await tester.pumpWidget(StintApp(controller: timer, profiles: profiles));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('focus-profiles')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Coding'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to Coding?'), findsOneWidget);
      expect(timer.timer.running, true);
      await tester.ensureVisible(find.text('Keep going'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(timer.workspace.settings.focusMinutes, 25);
      expect(blocker.settings.enabled, false);
      expect(tester.takeException(), isNull);
    },
  );
}
