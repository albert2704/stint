import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';
import 'package:stint/main.dart';
import 'package:stint/ui/progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('stint/timer'),
      (_) async => null,
    );
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('stint/timer'),
      null,
    ),
  );

  Future<void> mount(WidgetTester tester, StintController controller) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(StintApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Flow displays elapsed focus and finishing offers a counted-down break',
    (tester) async {
      var now = DateTime(2026, 10, 20, 12);
      final c = StintController(
        MemoryWorkspaceStore(),
        now: () => now,
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('mode-flow')));
      await tester.pumpAndSettle();
      expect(find.text('00:00'), findsOneWidget);
      expect(find.byTooltip('Add a minute'), findsNothing);
      await tester.tap(find.byKey(const Key('timer-toggle')));
      now = now.add(const Duration(minutes: 11));
      c.tick();
      await tester.pumpAndSettle();
      expect(find.text('11:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-take-break')));
      await tester.pumpAndSettle();
      expect(c.workspace.sessions.single.seconds, 660);
      expect(c.timer.phase, TimerPhase.shortBreak);
      expect(c.timer.running, false);
      expect(find.byTooltip('Add a minute'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching mode preserves work on cancel and changes only after confirmation',
    (tester) async {
      final c = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      await mount(tester, c);
      c.startTimer();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mode-flow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timer-confirmation')), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(c.timer.mode, FocusMode.pomodoro);
      expect(c.timer.running, true);
      await tester.tap(find.byKey(const ValueKey('mode-flow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();
      expect(c.timer.mode, FocusMode.flow);
      expect(c.timer.running, false);
    },
  );

  testWidgets('Pick up here saves, reopens and clears one compact reminder', (
    tester,
  ) async {
    final c = StintController(MemoryWorkspaceStore(), tickAutomatically: false);
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.tap(find.byKey(const Key('pick-up-here')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('continuation-note')),
      'Continue the introduction',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.workspace.settings.continuationNote, 'Continue the introduction');
    expect(find.text('Continue the introduction'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-up-here')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(c.workspace.settings.continuationNote, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'weekly recap uses selected week and target persists independently',
    (tester) async {
      final store = MemoryWorkspaceStore();
      final c = StintController(
        store,
        now: () => DateTime(2026, 10, 20, 12),
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      c.workspace.sessions.addAll([
        FocusSession(
          id: 'today',
          taskTitle: 'Open focus',
          projectName: '',
          seconds: 1800,
          finishedAt: DateTime(2026, 10, 20, 11),
        ),
        FocusSession(
          id: 'last',
          taskTitle: 'Open focus',
          projectName: '',
          seconds: 3000,
          finishedAt: DateTime(2026, 10, 13, 11),
        ),
      ]);
      await mount(tester, c);
      await tester.tap(find.byKey(const Key('progress-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('weekly-recap')));
      await tester.pumpAndSettle();
      final recap = find.byKey(const Key('weekly-recap'));
      expect(
        find.descendant(of: recap, matching: find.text('30m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: recap, matching: find.text('30 min')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('weekly-goal-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weekly-goal-up')));
      await tester.pumpAndSettle();
      expect(c.workspace.settings.weeklyGoalMinutes, 630);
      expect(store.load()!.settings.weeklyGoalMinutes, 630);
      expect(find.byType(StintProgress), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
