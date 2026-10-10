import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';
import 'package:stint/main.dart';
import 'package:stint/music.dart';
import 'package:stint/ui/theme.dart';

Future<void> mount(
  WidgetTester tester,
  StintController c, {
  Size size = const Size(480, 758),
  FocusMusic? music,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('capture'),
      child: StintApp(controller: c, music: music),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timerChannel = MethodChannel('stint/timer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(timerChannel, (call) async {
      if (call.method == 'getAlertSoundSettings') {
        return {
          'selectedSound': 'Glass',
          'sounds': ['Glass', 'Ping', 'Pop', 'Funk', 'Submarine', 'Basso'],
        };
      }
      throw MissingPluginException();
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(timerChannel, null));
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final family in ['HankenGrotesk', 'MartianMono']) {
      final loader = FontLoader(family);
      for (final file in Directory(
        'assets/fonts/$family',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
      await loader.load();
    }
  });

  testWidgets('only Pomodoro controls remain and pause/resume work', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 8, 10);
    final c = StintController(
      MemoryWorkspaceStore(),
      now: () => now,
      tickAutomatically: false,
    );
    addTearDown(c.dispose);
    await mount(tester, c);
    for (final removed in [
      'Task board',
      'New board',
      'Notebooks',
      'New task',
      'Session history',
      'Show desktop cat',
    ]) {
      expect(find.text(removed), findsNothing);
    }
    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pumpAndSettle();
    expect(c.timer.running, isTrue);
    now = now.add(const Duration(seconds: 30));
    c.tick();
    await tester.pumpAndSettle();
    expect(find.text('24:30'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(hours: 1));
    expect(c.remaining, 1470);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(c.timer.endsAt, now.add(const Duration(seconds: 1470)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing phase confirms before replacing unfinished time', (
    tester,
  ) async {
    final c = StintController(MemoryWorkspaceStore(), tickAutomatically: false);
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.tap(find.text('Start focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('phase-shortBreak')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(c.timer.phase, TimerPhase.focus);
    expect(c.timer.running, isTrue);
    await tester.tap(find.byKey(const Key('phase-shortBreak')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(c.timer.running, isFalse);
    expect(c.timer.phase, TimerPhase.shortBreak);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('Start break'), findsOneWidget);
    expect(c.workspace.sessions, isEmpty);
  });

  testWidgets('duration preferences validate and preserve a running interval', (
    tester,
  ) async {
    final c = StintController(MemoryWorkspaceStore(), tickAutomatically: false);
    addTearDown(c.dispose);
    c.startFocus();
    final deadline = c.timer.endsAt;
    await mount(tester, c, size: const Size(420, 600));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('duration-focus')), '0');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 120 minutes.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('duration-focus')), '40');
    await tester.enterText(find.byKey(const Key('duration-shortBreak')), '7');
    await tester.enterText(find.byKey(const Key('duration-longBreak')), '20');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(c.timer.endsAt, deadline);
    expect(c.timer.totalSeconds, 1500);
    expect(c.store.load()!.settings.focusMinutes, 40);
    expect(c.store.load()!.settings.shortBreakMinutes, 7);
    expect(c.store.load()!.settings.longBreakMinutes, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stint surfaces render in both themes and small windows', (
    tester,
  ) async {
    final c = StintController(MemoryWorkspaceStore(), tickAutomatically: false);
    final music = FocusMusic();
    addTearDown(c.dispose);
    addTearDown(music.dispose);
    c.workspace.settings.appearance = 'light';
    await mount(tester, c, music: music);
    expect(find.text('stint'), findsOneWidget);
    await capture(tester, 'stint-light');
    c.workspace.settings.appearance = 'dark';
    c.persist();
    await tester.pumpAndSettle();
    await capture(tester, 'stint-dark');
    tester.view.physicalSize = const Size(420, 600);
    await tester.pumpAndSettle();
    await capture(tester, 'stint-small');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await capture(tester, 'stint-settings');
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'minute controls affect current time and reset uses inline confirmation',
    (tester) async {
      final c = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.tap(find.byTooltip('Add a minute'));
      await tester.pumpAndSettle();
      expect(find.text('26:00'), findsOneWidget);
      expect(c.workspace.settings.focusMinutes, 25);
      expect(c.timerHasProgress, isFalse);
      await tester.tap(find.byTooltip('Remove a minute'));
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timer-confirmation')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(c.timer.running, isTrue);
      await tester.tap(find.byTooltip('Skip to next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();
      expect(c.timer.cycleStep, 1);
      expect(c.timer.completedCount, 0);
      expect(c.workspace.sessions, isEmpty);
    },
  );

  test(
    'Stint text and accent tokens meet normal text contrast in both themes',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      for (final c in [StintColors.light, StintColors.dark]) {
        for (final background in [c.ground, c.surface]) {
          for (final foreground in [
            c.ink,
            c.ink2,
            c.muted,
            c.focusText,
            c.breakText,
          ]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
        }
        expect(contrast(c.onAccent, c.focus), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onAccent, c.breakColor), greaterThanOrEqualTo(4.5));
      }
    },
  );
}
