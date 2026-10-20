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

FocusSession stint(DateTime end, {int minutes = 25, String? id}) =>
    FocusSession(
      id: id ?? 'stint-${end.microsecondsSinceEpoch}-$minutes',
      taskTitle: 'Open focus',
      projectName: '',
      seconds: minutes * 60,
      finishedAt: end,
    );

Future<void> mount(
  WidgetTester tester,
  StintController c, {
  Size size = const Size(480, 790),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('capture'),
      child: StintApp(controller: c),
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
  // Friday 9 October 2026, noon local time.
  final friday = DateTime(2026, 10, 9, 12);

  group('Progress sheet', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const timerChannel = MethodChannel('stint/timer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() {
      messenger.setMockMethodCallHandler(timerChannel, (call) async {
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

    StintController seeded({String appearance = 'dark'}) {
      final c = StintController(
        MemoryWorkspaceStore(),
        now: () => friday,
        tickAutomatically: false,
      );
      c.workspace.settings.appearance = appearance;
      // Sample week, Sunday start in the test locale: 4, 6, 8, 9, 5, then 3 today.
      final perDay = {4: 4, 5: 6, 6: 8, 7: 9, 8: 5, 9: 3};
      for (final MapEntry(key: day, value: count) in perDay.entries) {
        for (var i = 0; i < count; i++) {
          c.workspace.sessions.insert(
            0,
            stint(DateTime(2026, 10, day, 9, 5 + i * 35)),
          );
        }
      }
      c.workspace.sessions.add(stint(DateTime(2026, 9, 24, 10)));
      c.persist();
      return c;
    }

    testWidgets('header shows today against the goal and opens the sheet', (
      tester,
    ) async {
      final c = seeded();
      addTearDown(c.dispose);
      await mount(tester, c);
      expect(find.text('3/8'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Progress, 3 of 8 stints today'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('progress-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-sheet')), findsOneWidget);
      expect(find.text('5 more to reach today’s goal.'), findsOneWidget);
      expect(find.text('35 stints · 14h 35m'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byTooltip('Wed, Oct 7 · 9 stints · 3h 45m'), findsOneWidget);
      expect(find.text('6 days'), findsOneWidget, reason: 'six-day streak');
      expect(
        tester.getSize(find.byKey(const Key('progress-sheet'))),
        const Size(480, 790),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'progress-dark');

      final next = tester.widget<IconButton>(
        find.byKey(const Key('progress-week-next')),
      );
      expect(next.onPressed, isNull);
      await tester.tap(find.byKey(const Key('progress-week-prev')));
      await tester.pumpAndSettle();
      expect(find.text('LAST WEEK'), findsOneWidget);
      await tester.tap(find.byKey(const Key('progress-week-prev')));
      await tester.pumpAndSettle();
      expect(find.text('WEEK OF SEP 20'), findsOneWidget);
      final prev = tester.widget<IconButton>(
        find.byKey(const Key('progress-week-prev')),
      );
      expect(prev.onPressed, isNull);
      await tester.tap(find.byTooltip('Close progress'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress-sheet')), findsNothing);
    });

    testWidgets('goal stepper saves at once and respects its limits', (
      tester,
    ) async {
      final c = seeded();
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.tap(find.byKey(const Key('progress-button')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('daily-goal-down')));
        await tester.pump();
      }
      expect(c.workspace.settings.dailyGoal, 3);
      expect(find.text('Goal met. Anything more is a bonus.'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('daily-goal-down')));
        await tester.pump();
      }
      expect(c.workspace.settings.dailyGoal, 1);
      await tester.tap(find.byKey(const Key('daily-goal-down')));
      await tester.pump();
      expect(c.workspace.settings.dailyGoal, 1);
      expect(find.text('+2'), findsOneWidget);
      expect(
        Workspace.decode(
          (c.store as MemoryWorkspaceStore).contents!,
        ).settings.dailyGoal,
        1,
      );
      for (var i = 0; i < 15; i++) {
        await tester.tap(find.byKey(const Key('daily-goal-up')));
        await tester.pump();
      }
      expect(c.workspace.settings.dailyGoal, 16);
      final raise = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const Key('daily-goal-up')),
          matching: find.byType(IconButton),
        ),
      );
      expect(raise.onPressed, isNull);
      expect(
        find.bySemanticsLabel(
          'Daily goal: 16 stints. 13 more to reach today’s goal.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty history and light theme', (tester) async {
      final c = StintController(
        MemoryWorkspaceStore(),
        now: () => friday,
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      c.workspace.settings.appearance = 'light';
      await mount(tester, c);
      expect(find.text('0/8'), findsOneWidget);
      await tester.tap(find.byKey(const Key('progress-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('No stints yet today. Finish one and it shows up here.'),
        findsOneWidget,
      );
      expect(find.text('0 stints · 0m'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('progress-week-prev')))
            .onPressed,
        isNull,
      );
      expect(find.text('0 days'), findsOneWidget);
      expect(find.text('0 of 6 days'), findsOneWidget);
      expect(find.text('0 min'), findsOneWidget);
      await capture(tester, 'progress-empty');
      await tester.tap(find.byTooltip('Close progress'));
      await tester.pumpAndSettle();
      final light = seeded(appearance: 'light');
      addTearDown(light.dispose);
      await mount(tester, light);
      await tester.tap(find.byKey(const Key('progress-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'progress-light');
    });

    testWidgets('header fits the smallest window with a long rhythm name', (
      tester,
    ) async {
      final c = seeded();
      addTearDown(c.dispose);
      c.applyRoutine('deep');
      await mount(tester, c, size: const Size(420, 600));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('progress-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('progress-button')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('progress-sheet'))),
        const Size(420, 600),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'progress-small');
      await tester.ensureVisible(
        find.textContaining('Only finished focus stints count.'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Only finished focus stints count.').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
