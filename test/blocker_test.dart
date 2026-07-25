import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/blocker.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';

class MemoryBlockerStore implements BlockerStore {
  BlockerSettings value = BlockerSettings();
  bool fail = false;
  @override
  BlockerSettings load() => value;
  @override
  void save(BlockerSettings settings) {
    if (fail) throw const FileSystemException('Test disk unavailable');
    value = settings;
  }
}

Map<String, String> filterRow([String state = 'configured']) => {
  'status': state,
  'message': 'Test filter state',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('stint/blocker-test');
  const app = BlockedApp(
    bundleId: 'com.example.Distraction',
    name: 'Distraction',
  );
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'filterStatus' ? filterRow() : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('normalizes domains without widening host boundaries', () {
    expect(
      normalizeBlockedDomain(' HTTPS://Reddit.com/r/test?q=1 '),
      'reddit.com',
    );
    expect(normalizeBlockedDomain('www.youtube.com.'), 'www.youtube.com');
    expect(normalizeBlockedDomain('xn--bcher-kva.de'), 'xn--bcher-kva.de');
    expect(blockedDomainMatches('old.reddit.com', 'reddit.com'), isTrue);
    expect(blockedDomainMatches('www.reddit.com', 'reddit.com'), isTrue);
    expect(blockedDomainMatches('reddit.com.evil.test', 'reddit.com'), isFalse);
    expect(blockedDomainMatches('notreddit.com', 'reddit.com'), isFalse);
    for (final invalid in [
      'localhost',
      'localhost.localhost',
      '127.0.0.1',
      '[::1]',
      '*.reddit.com',
      'https://user:pass@reddit.com',
      'file:///etc/hosts',
      '-bad.com',
      'bad-.com',
      'two..com',
      'two words.com',
      'bücher.de',
      'example.123',
    ]) {
      expect(normalizeBlockedDomain(invalid), isNull, reason: invalid);
    }
  });

  test(
    'settings validate size, protected apps, duplicate and damaged data',
    () {
      for (final bundle in protectedBundleIds) {
        expect(BlockedApp(bundleId: bundle, name: 'Recovery').isValid, isFalse);
      }
      final value = BlockerSettings(
        enabled: true,
        apps: [app],
        domains: ['example.com'],
      );
      expect(
        BlockerSettings.decode(jsonEncode(value.toJson())).apps.single.name,
        'Distraction',
      );
      for (final changed in [
        {...value.toJson(), 'version': 2},
        {
          ...value.toJson(),
          'domains': ['example.com', 'example.com'],
        },
        {
          ...value.toJson(),
          'domains': ['http://example.com'],
        },
        {...value.toJson(), 'domains': List.generate(201, (i) => 'site$i.com')},
        {
          ...value.toJson(),
          'apps': [app.toJson(), app.toJson()],
        },
      ]) {
        expect(
          () => BlockerSettings.decode(jsonEncode(changed)),
          throwsFormatException,
        );
      }
    },
  );

  test('file settings persist without modifying timer or unrelated files', () {
    final directory = Directory.systemTemp.createTempSync('stint-blocker-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = FileBlockerStore(directory);
    final other = File('${directory.path}/workspace.json')
      ..writeAsStringSync('untouched');
    store.save(
      BlockerSettings(
        enabled: true,
        apps: [app],
        domains: ['example.com'],
        bypassSessionId: 'session-a',
      ),
    );
    expect(FileBlockerStore(directory).load().bypassSessionId, 'session-a');
    expect(other.readAsStringSync(), 'untouched');
    expect(File('${store.file.path}.tmp').existsSync(), isFalse);
    store.file.writeAsStringSync('damaged');
    expect(store.load, throwsFormatException);
    expect(store.file.readAsStringSync(), 'damaged');
  });

  test('filter state decoding rejects unknown or malformed data', () {
    for (final state in WebsiteFilterState.values) {
      expect(WebsiteFilterStatus.decode(filterRow(state.name)).state, state);
    }
    for (final invalid in [
      null,
      [],
      {},
      filterRow('pretendReady'),
      {'status': 'configured', 'message': 2},
    ]) {
      expect(() => WebsiteFilterStatus.decode(invalid), throwsFormatException);
    }
    final unsigned = WebsiteFilterStatus.decode(filterRow('notInstalled'));
    expect(unsigned.configured, isFalse);
    expect(unsigned.canEnable, isTrue);
  });

  test(
    'initialization and refresh preflight never request permission or use old pairing',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'stint-native-blocker-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final obsolete = File('${directory.path}/browser-pairing.json')
        ..writeAsStringSync('old private data');
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final blocker = BlockerController(
        timer,
        store: FileBlockerStore(directory),
        channel: channel,
        automaticHeartbeat: false,
      );
      addTearDown(() {
        blocker.dispose();
        timer.dispose();
      });
      await blocker.initialize();
      await blocker.refreshFilter();
      expect(blocker.filter.state, WebsiteFilterState.configured);
      expect(
        calls.where((call) => call.method == 'filterStatus'),
        hasLength(2),
      );
      expect(
        calls.every((call) => {'update', 'filterStatus'}.contains(call.method)),
        isTrue,
      );
      expect(obsolete.readAsStringSync(), 'old private data');
      expect(directory.listSync().length, 1);
    },
  );

  test(
    'permission requests are explicit and denial leaves app protection running',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'filterStatus') {
              return filterRow('notInstalled');
            }
            if (call.method == 'enableFilter') {
              return filterRow('approvalRequired');
            }
            return null;
          });
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final blocker = BlockerController(
        timer,
        store: MemoryBlockerStore(),
        channel: channel,
        automaticHeartbeat: false,
      );
      addTearDown(() {
        blocker.dispose();
        timer.dispose();
      });
      await blocker.initialize();
      await blocker.save(enabled: true, apps: [app], domains: ['example.com']);
      timer.startTimer();
      expect(calls.any((call) => call.method == 'enableFilter'), isFalse);
      await blocker.enableFilter();
      final requests = calls.where((call) => call.method == 'enableFilter');
      expect(requests, hasLength(1));
      expect(requests.single.arguments, isNull);
      expect(blocker.filter.state, WebsiteFilterState.approvalRequired);
      expect(blocker.active, isTrue);
      expect(blocker.statusLabel, 'App guard on · website helper setup needed');
      expect(blocker.error, isNull);
      expect(blocker.nativeState['domains'], ['example.com']);
    },
  );

  test(
    'new native filter status wins over an older preflight response',
    () async {
      final pending = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'filterStatus') return pending.future;
            return null;
          });
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final blocker = BlockerController(
        timer,
        store: MemoryBlockerStore(),
        channel: channel,
        automaticHeartbeat: false,
      );
      addTearDown(() {
        blocker.dispose();
        timer.dispose();
      });
      final initialization = blocker.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(blocker.checkingFilter, isTrue);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall('filter', filterRow('approvalRequired')),
            ),
            null,
          );
      pending.complete(filterRow());
      await initialization;
      expect(blocker.filter.state, WebsiteFilterState.approvalRequired);
      expect(blocker.checkingFilter, isFalse);
    },
  );

  test(
    'filter status errors fail closed without stopping app blocking and can recover',
    () async {
      var valid = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'filterStatus') {
              if (!valid) throw PlatformException(code: 'unavailable');
              return filterRow();
            }
            return null;
          });
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final blocker = BlockerController(
        timer,
        store: MemoryBlockerStore(),
        channel: channel,
        automaticHeartbeat: false,
      );
      addTearDown(() {
        blocker.dispose();
        timer.dispose();
      });
      await blocker.initialize();
      await blocker.save(enabled: true, apps: [app], domains: ['example.com']);
      timer.startTimer();
      valid = false;
      await blocker.refreshFilter();
      expect(blocker.filter.state == WebsiteFilterState.unavailable, isTrue);
      expect(blocker.error, contains('Website helper unavailable'));
      expect(blocker.active, isTrue);
      valid = true;
      await blocker.refreshFilter();
      expect(blocker.error, isNull);
      expect(blocker.filter.state, WebsiteFilterState.configured);
      expect(blocker.statusLabel, 'App guard on · website protection starting…');
      blocker.filter = const WebsiteFilterStatus(
        WebsiteFilterState.configured,
        'Proxy routing active',
        active: true,
      );
      expect(blocker.statusLabel, 'Focus guard on');
    },
  );

  test('damaged blocklist is preserved and does not stop the timer', () async {
    final directory = Directory.systemTemp.createTempSync(
      'stint-bad-blocklist-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/blocker.json')
      ..writeAsStringSync('damaged');
    final timer = StintController(
      MemoryWorkspaceStore(),
      tickAutomatically: false,
    );
    final blocker = BlockerController(
      timer,
      store: FileBlockerStore(directory),
      channel: channel,
      automaticHeartbeat: false,
    );
    await blocker.initialize();
    expect(blocker.ready, isFalse);
    timer.startTimer();
    expect(timer.timer.running, isTrue);
    expect(blocker.active, isFalse);
    expect(file.readAsStringSync(), 'damaged');
    blocker.dispose();
    timer.dispose();
  });

  test('timer policy releases on pause, break, reset and deadline', () async {
    var now = DateTime(2026, 10, 11, 10);
    final timer = StintController(
      MemoryWorkspaceStore(),
      now: () => now,
      tickAutomatically: false,
    );
    final store = MemoryBlockerStore();
    final blocker = BlockerController(
      timer,
      store: store,
      channel: channel,
      automaticHeartbeat: false,
    );
    addTearDown(() {
      blocker.dispose();
      timer.dispose();
    });
    await blocker.initialize();
    await blocker.save(enabled: true, apps: [app], domains: ['example.com']);
    expect(blocker.active, isFalse);
    timer.startTimer();
    expect(blocker.active, isTrue);
    expect(
      blocker.nativeState['leaseExpiresAt'],
      now.millisecondsSinceEpoch + 30000,
    );
    timer.pauseTimer();
    expect(blocker.active, isFalse);
    timer.startTimer();
    expect(blocker.active, isTrue);
    now = now.add(const Duration(minutes: 26));
    expect(
      blocker.active,
      isFalse,
      reason: 'absolute deadline even before Dart tick',
    );
    timer.tick();
    expect(timer.timer.phase, TimerPhase.shortBreak);
    timer.startTimer();
    expect(blocker.active, isFalse);
    timer.selectPhase(TimerPhase.focus);
    timer.startTimer();
    expect(blocker.active, isTrue);
    timer.resetTimer();
    expect(blocker.active, isFalse);
    await Future<void>.delayed(Duration.zero);
    final updates = calls.where((call) => call.method == 'update');
    expect(
      updates.any((call) => (call.arguments as Map)['active'] == true),
      isTrue,
    );
    expect((updates.last.arguments as Map)['active'], isFalse);
  });

  test(
    'override survives resume and reload; stale override cannot release new focus',
    () async {
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final store = MemoryBlockerStore();
      var blocker = BlockerController(
        timer,
        store: store,
        channel: channel,
        automaticHeartbeat: false,
      );
      addTearDown(() {
        blocker.dispose();
        timer.dispose();
      });
      await blocker.initialize();
      await blocker.save(enabled: true, apps: [app], domains: []);
      timer.startTimer();
      final first = blocker.sessionId!;
      await blocker.unblock(first);
      expect(blocker.bypassed, isTrue);
      timer.pauseTimer();
      timer.startTimer();
      expect(blocker.active, isFalse);
      blocker.dispose();
      blocker = BlockerController(
        timer,
        store: store,
        channel: channel,
        automaticHeartbeat: false,
      );
      await blocker.initialize();
      expect(blocker.active, isFalse);
      timer.resetTimer();
      timer.startTimer();
      expect(blocker.active, isTrue);
      await blocker.unblock(first);
      expect(blocker.active, isTrue);
    },
  );

  test(
    'save failure preserves policy; timer still releases during storage failure',
    () async {
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final store = MemoryBlockerStore();
      final blocker = BlockerController(
        timer,
        store: store,
        channel: channel,
        automaticHeartbeat: false,
      );
      addTearDown(() {
        blocker.dispose();
        timer.dispose();
      });
      await blocker.initialize();
      await blocker.save(enabled: true, apps: [app], domains: ['example.com']);
      timer.startTimer();
      expect(
        blocker.relaxesProtection(
          enabled: true,
          apps: [app],
          domains: ['sub.example.com'],
        ),
        isTrue,
      );
      expect(
        blocker.relaxesProtection(
          enabled: true,
          apps: [app],
          domains: ['example.com', 'new.example'],
        ),
        isFalse,
      );
      store.fail = true;
      await expectLater(blocker.unblock(blocker.sessionId!), throwsStateError);
      expect(blocker.active, isTrue);
      expect(blocker.error, contains('previous settings'));
      timer.pauseTimer();
      expect(blocker.active, isFalse);
    },
  );
}
