import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_desk/data/controller.dart';
import 'package:focus_desk/data/store.dart';
import 'package:focus_desk/main.dart';
import 'package:focus_desk/music.dart';
import 'package:focus_desk/ui/music_panel.dart';
import 'package:focus_desk/ui/theme.dart';

class FakeMusicAssets extends CachingAssetBundle {
  final loaded = <String>[];
  Completer<ByteData>? pending;
  final data = ByteData.sublistView(
    Uint8List.fromList([99, 82, 73, 70, 70, 42, 88]),
    1,
    6,
  );

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    return pending == null ? data : pending!.future;
  }
}

/// Models the native contract: persisted library/preferences, explicit playback,
/// and a cancelled file picker that returns the unchanged player state.
class FakeMusicHost {
  final calls = <MethodCall>[];
  final custom = <Map<String, String>>[
    {'id': 'custom-rain', 'title': 'Library rain.wav'},
  ];
  String selectedId = 'warm_drift';
  double volume = .35;
  bool playing = false;
  bool cancelImport = true;
  bool failPlay = false;
  bool followTimer = false;
  Completer<void>? pendingFade;
  Completer<void>? pendingImport;

  Map<String, Object?> get state => {
    'tracks': custom.map((track) => Map<String, String>.of(track)).toList(),
    'selectedId': selectedId,
    'volume': volume,
    'playing': playing,
    'followTimer': followTimer,
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'load':
        playing = false;
      case 'import':
        await pendingImport?.future;
        if (!cancelImport) {
          custom.add({'id': 'custom-own', 'title': 'My focus.mp3'});
        }
      case 'removeCustom':
        final id = call.arguments as String;
        custom.removeWhere((track) => track['id'] == id);
        if (selectedId == id) {
          selectedId = 'quiet_keys';
          playing = false;
        }
      case 'select':
        selectedId = call.arguments as String;
        playing = false;
      case 'play':
        if (failPlay) {
          throw PlatformException(
            code: 'playback_failed',
            message: 'This audio file could not be played.',
          );
        }
        selectedId = (call.arguments as Map)['id'] as String;
        playing = true;
      case 'pause':
        playing = false;
      case 'fadePause':
        await pendingFade?.future;
        playing = false;
      case 'followTimer':
        followTimer = call.arguments as bool;
      case 'volume':
        volume = call.arguments as double;
      default:
        throw MissingPluginException(
          'Unexpected music command: ${call.method}',
        );
    }
    return state;
  }
}

const musicCaptureKey = Key('music-capture');

Future<void> captureMusic(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(musicCaptureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    Directory('docs/screenshots').createSync(recursive: true);
    await File('docs/screenshots/$name.png').writeAsBytes(bytes);
    image.dispose();
  });
}

Future<void> mountMusicScreen(
  WidgetTester tester,
  DeskController controller,
  FocusMusic music, {
  Size size = const Size(520, 820),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: musicCaptureKey,
      child: FocusDeskApp(controller: controller, music: music),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('focus_desk/music-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeMusicAssets assets;
  late FakeMusicHost host;
  late FocusMusic music;

  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (font.existsSync()) {
      await (FontLoader('.AppleSystemUIFont')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
  });

  setUp(() {
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    assets = FakeMusicAssets();
    host = FakeMusicHost();
    messenger.setMockMethodCallHandler(channel, host.handle);
    music = FocusMusic(channel: channel, assets: assets);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue();
    music.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'load restores the library and selection without starting playback',
    () async {
      host.selectedId = 'custom-rain';
      host.volume = .6;
      expect(host.calls, isEmpty);
      await music.load();
      expect(host.calls.map((call) => call.method), ['load']);
      expect(music.tracks.map((track) => track.id), [
        'quiet_keys',
        'warm_drift',
        'night_study',
        'custom-rain',
      ]);
      expect(music.selected.id, 'custom-rain');
      expect(music.selected.asset, isNull);
      expect(music.volume, .6);
      expect(music.playing, isFalse);
      expect(music.busy, isFalse);
      expect(assets.loaded, isEmpty);
    },
  );

  test(
    'custom playback sends an ID and built-in playback sends only its asset bytes',
    () async {
      await music.load();
      await music.select('custom-rain');
      expect(host.calls.last.method, 'select');
      expect(host.calls.last.arguments, 'custom-rain');
      await music.play();
      expect(host.calls.last.method, 'play');
      expect(host.calls.last.arguments, {'id': 'custom-rain'});
      expect(assets.loaded, isEmpty);
      expect(music.playing, isTrue);

      await music.pause();
      await music.select('night_study');
      await music.play();
      expect(assets.loaded, ['assets/music/night_study.wav']);
      final arguments = host.calls.last.arguments as Map;
      expect(arguments['id'], 'night_study');
      expect(arguments['data'], isA<Uint8List>());
      expect(arguments['data'], orderedEquals([82, 73, 70, 70, 42]));
      expect(music.playing, isTrue);
    },
  );

  test(
    'removing an imported sound uses the saved ID and resets selected playback',
    () async {
      await music.load();
      await music.select('custom-rain');
      await music.play();
      await music.removeCustom('custom-rain');
      expect(host.calls.last.method, 'removeCustom');
      expect(host.calls.last.arguments, 'custom-rain');
      expect(music.imported, isEmpty);
      expect(music.selectedId, 'quiet_keys');
      expect(music.playing, isFalse);
      expect(assets.loaded, isEmpty);
    },
  );

  test(
    'pause and volume updates follow native state and preview stays local',
    () async {
      await music.load();
      await music.play();
      await music.pause();
      expect(host.calls.last.method, 'pause');
      expect(music.playing, isFalse);
      final count = host.calls.length;
      music.previewVolume(.72);
      expect(music.volume, .72);
      expect(host.calls, hasLength(count));
      await music.saveVolume(.72);
      expect(host.calls.last.method, 'volume');
      expect(host.calls.last.arguments, isA<double>());
      expect(host.volume, .72);
      expect(music.volume, .72);
      music.previewVolume(-1);
      expect(music.volume, 0);
      music.previewVolume(2);
      expect(music.volume, 1);
    },
  );

  test(
    'cancelling import keeps the current selection, library, and playback',
    () async {
      await music.load();
      await music.play();
      final before = host.state;
      await music.importFiles();
      expect(host.calls.last.method, 'import');
      expect(host.state, before);
      expect(music.selectedId, before['selectedId']);
      expect(music.playing, isTrue);
      expect(music.imported.single.id, 'custom-rain');
      expect(music.error, isNull);

      host.cancelImport = false;
      await music.importFiles();
      expect(music.imported.map((track) => track.id), [
        'custom-rain',
        'custom-own',
      ]);
      expect(music.selectedId, before['selectedId']);
      expect(music.playing, before['playing']);
      await music.select('custom-own');
      await music.play();
      expect(host.calls.last.arguments, {'id': 'custom-own'});
    },
  );

  test('playback errors surface and a successful retry clears them', () async {
    await music.load();
    host.failPlay = true;
    await music.play();
    expect(music.error, 'This audio file could not be played.');
    expect(music.playing, isFalse);
    expect(music.busy, isFalse);
    host.failPlay = false;
    await music.play();
    expect(music.error, isNull);
    expect(music.playing, isTrue);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('error', 'The selected file is no longer available.'),
      ),
      null,
    );
    expect(music.error, 'The selected file is no longer available.');
    expect(music.playing, isFalse);
  });

  test(
    'a fresh music controller restores preferences without autoplay',
    () async {
      await music.load();
      await music.select('custom-rain');
      await music.saveVolume(.55);
      await music.play();
      music.dispose();
      music = FocusMusic(channel: channel, assets: assets);
      host.calls.clear();
      await music.load();
      expect(music.selectedId, 'custom-rain');
      expect(music.volume, .55);
      expect(music.playing, isFalse);
      expect(host.calls.map((call) => call.method), ['load']);
    },
  );

  test(
    'loading a built-in asset blocks duplicate play and selection commands',
    () async {
      await music.load();
      assets.pending = Completer<ByteData>();
      final playing = music.play();
      expect(music.busy, isTrue);
      await music.play();
      await music.select('quiet_keys');
      expect(assets.loaded, ['assets/music/warm_drift.wav']);
      expect(host.calls.where((call) => call.method == 'select'), isEmpty);
      expect(host.calls.where((call) => call.method == 'play'), isEmpty);
      assets.pending!.complete(assets.data);
      await playing;
      expect(host.calls.where((call) => call.method == 'play'), hasLength(1));
      expect(music.selectedId, 'warm_drift');
      expect(music.playing, isTrue);
      expect(music.busy, isFalse);
    },
  );

  testWidgets(
    'music controls list built-ins, import files, play, pause, and show errors',
    (tester) async {
      await music.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: deskTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 400, child: MusicPanel(music: music)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add'), findsOneWidget);
      expect(find.byTooltip('Play sound'), findsOneWidget);
      for (final title in [
        'Quiet Keys',
        'Warm Drift',
        'Night Study',
        'Library rain.wav',
      ]) {
        expect(find.text(title), findsWidgets);
      }
      await tester.tap(find.text('Night Study').last);
      await tester.pumpAndSettle();
      expect(music.selectedId, 'night_study');
      await tester.tap(find.byTooltip('Play sound'));
      await tester.pumpAndSettle();
      expect(music.playing, isTrue);
      expect(find.byTooltip('Pause sound'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause sound'));
      await tester.pumpAndSettle();
      expect(music.playing, isFalse);
      await tester.tap(find.byKey(const Key('music-follow-timer')));
      await tester.pumpAndSettle();
      expect(music.followTimer, isTrue);
      expect(host.followTimer, isTrue);
      expect(music.playing, isFalse);

      host.cancelImport = false;
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio file…'));
      await tester.pumpAndSettle();
      expect(music.selectedId, 'night_study');
      await tester.tap(find.text('My focus.mp3').last);
      await tester.pumpAndSettle();
      expect(music.selectedId, 'custom-own');
      expect(find.text('My focus.mp3'), findsWidgets);
      await tester.tap(find.byType(Slider));
      await tester.pumpAndSettle();
      expect(host.calls.last.method, 'volume');
      expect(music.volume, closeTo(.5, .1));

      host.failPlay = true;
      await tester.tap(find.byTooltip('Play sound'));
      await tester.pumpAndSettle();
      expect(find.text('This audio file could not be played.'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(music.selectedId, 'custom-own');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(music.selectedId, 'quiet_keys');
      expect(music.tracks.any((track) => track.id == 'custom-own'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pomodoro and music playback remain independently controllable', (
    tester,
  ) async {
    final controller = DeskController(
      MemoryWorkspaceStore(),
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    await music.load();
    await mountMusicScreen(tester, controller, music);
    expect(find.text('SOUND'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Play sound'));
    await tester.tap(find.byTooltip('Play sound'));
    await tester.pumpAndSettle();
    expect(music.playing, isTrue);
    expect(controller.timer.running, isFalse);
    await tester.ensureVisible(find.byKey(const Key('timer-toggle')));
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pumpAndSettle();
    expect(controller.timer.running, isTrue);
    expect(music.playing, isTrue);
    await tester.ensureVisible(find.byTooltip('Pause sound'));
    await tester.tap(find.byTooltip('Pause sound'));
    await tester.pumpAndSettle();
    expect(controller.timer.running, isTrue);
    expect(music.playing, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('music layouts render in light, dark, and small windows', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 8, 10);
    final controller = DeskController(
      MemoryWorkspaceStore(),
      now: () => now,
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    host.custom.clear();
    await music.load();
    await mountMusicScreen(tester, controller, music);
    expect(find.byTooltip('Add'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureMusic(tester, 'pomodoro-music-light');

    controller.startTimer();
    now = now.add(const Duration(minutes: 7));
    controller.tick();
    controller.workspace.settings.appearance = 'dark';
    controller.persist();
    await music.play();
    await tester.pumpAndSettle();
    expect(find.text('18:00'), findsOneWidget);
    expect(find.byTooltip('Pause sound'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureMusic(tester, 'pomodoro-music-dark');

    tester.view.physicalSize = const Size(420, 600);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(Slider),
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause sound').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Add').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureMusic(tester, 'pomodoro-music-small');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
