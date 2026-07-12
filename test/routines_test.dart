import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';
import 'package:stint/main.dart';
import 'package:stint/ui/routines.dart';

Future<void> mountRoutines(
  WidgetTester tester,
  StintController controller,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(StintApp(controller: controller));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alertChannel = MethodChannel('stint/timer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
  late DateTime now;
  late MemoryWorkspaceStore store;
  late StintController controller;
  setUp(() {
    messenger.setMockMethodCallHandler(alertChannel, (call) async {
      if (call.method == 'getAlertSoundSettings') {
        return {
          'selectedSound': 'Glass',
          'sounds': ['Glass', 'Ping', 'Pop', 'Funk', 'Submarine', 'Basso'],
        };
      }
      throw MissingPluginException();
    });
    now = DateTime(2026, 10, 8, 10);
    store = MemoryWorkspaceStore();
    controller = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
  });
  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(alertChannel, null);
  });

  test('old saved data gains built-ins without changing legacy records', () {
    final legacy = Workspace.empty();
    legacy.notes.add(
      StintNote(
        id: 'legacy-note',
        projectId: legacy.projects.single.id,
        title: 'Keep this note',
        body: 'Original writing.',
        updatedAt: now,
      ),
    );
    legacy.tasks.add(
      StintTask(
        id: 'legacy-task',
        projectId: legacy.projects.single.id,
        title: 'Keep this task',
        noteIds: ['legacy-note'],
        createdAt: now,
      ),
    );
    final original = jsonDecode(legacy.encode()) as Map<String, dynamic>;
    (original['settings'] as Map).remove('customRoutines');
    (original['settings'] as Map).remove('preferredRoutineId');
    store.contents = jsonEncode(original);
    final reopened = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
    addTearDown(reopened.dispose);
    expect(reopened.routines.map((routine) => routine.id), [
      'quick',
      'classic',
      'deep',
    ]);
    expect(reopened.activeRoutineId, 'classic');
    expect(reopened.workspace.settings.customRoutines, isEmpty);
    reopened.applyRoutine('quick');
    final saved = jsonDecode(store.contents!) as Map<String, dynamic>;
    for (final key in ['projects', 'tasks', 'notes', 'sessions']) {
      expect(saved[key], original[key]);
    }
    expect(reopened.remaining, 900);
  });

  test(
    'custom routines and preferred duplicate selection survive relaunch',
    () {
      final id = controller.saveRoutine(
        name: '  My classic  ',
        focus: 25,
        shortBreak: 5,
        longBreak: 15,
      );
      expect(controller.activeRoutineId, id);
      expect(controller.routines.last.name, 'My classic');
      controller.applyRoutine(id);
      final reopened = StintController(
        store,
        now: () => now,
        tickAutomatically: false,
      );
      addTearDown(reopened.dispose);
      expect(reopened.activeRoutineId, id);
      expect(
        reopened.routines.last.toJson(),
        controller.routines.last.toJson(),
      );
      reopened.deleteRoutine(id);
      expect(reopened.activeRoutineId, 'classic');
      expect(reopened.workspace.settings.customRoutines, isEmpty);
      expect(store.load()!.settings.customRoutines, isEmpty);
      expect(() => reopened.deleteRoutine('classic'), throwsArgumentError);
      expect(() => FocusRoutine.builtIns.clear(), throwsUnsupportedError);
    },
  );

  test(
    'applying a routine resets to idle focus and preserves completed count',
    () {
      controller.timer.completedCount = 3;
      controller.startTimer();
      now = now.add(const Duration(minutes: 5));
      controller.applyRoutine('deep');
      expect(controller.activeRoutineId, 'deep');
      expect(controller.timer.phase, TimerPhase.focus);
      expect(controller.timer.running, isFalse);
      expect(controller.timer.sessionId, isNull);
      expect(controller.remaining, 3000);
      expect(controller.timer.completedCount, 3);
      expect(controller.workspace.sessions, isEmpty);
      expect(controller.workspace.settings.shortBreakMinutes, 10);
      expect(controller.workspace.settings.longBreakMinutes, 30);
      final saved = store.contents;
      expect(() => controller.applyRoutine('missing'), throwsArgumentError);
      expect(store.contents, saved);

      controller.startTimer();
      now = controller.timer.endsAt!;
      controller.applyRoutine('quick');
      expect(controller.timer.completedCount, 4);
      expect(controller.workspace.sessions.single.seconds, 3000);
      expect(controller.remaining, 900);
      expect(controller.timer.running, isFalse);
    },
  );

  test(
    'manual durations report no active routine unless their values match',
    () {
      expect(controller.activeRoutineId, 'classic');
      controller.setTimerMinutes(26);
      expect(controller.activeRoutineId, isNull);
      controller.setTimerMinutes(25);
      expect(controller.activeRoutineId, 'classic');
      controller.updateSettings(
        focus: 38,
        shortBreak: 8,
        longBreak: 18,
        appearance: 'dark',
      );
      expect(controller.activeRoutineId, isNull);
      controller.startTimer();
      final deadline = controller.timer.endsAt;
      final id = controller.saveRoutine(
        name: 'Writing',
        focus: 38,
        shortBreak: 8,
        longBreak: 18,
      );
      expect(controller.activeRoutineId, id);
      expect(controller.timer.endsAt, deadline);
      expect(controller.timer.running, isTrue);
      controller.deleteRoutine(id);
      expect(controller.activeRoutineId, isNull);
      expect(controller.timer.endsAt, deadline);
    },
  );

  test('invalid routine input and duplicate stored IDs are rejected', () {
    controller.persist();
    final original = store.contents;
    for (final values in [
      ('', 25, 5, 15),
      (List.filled(81, 'x').join(), 25, 5, 15),
      ('Invalid focus', 0, 5, 15),
      ('Invalid focus', 121, 5, 15),
      ('Invalid break', 25, 0, 15),
      ('Invalid break', 25, 61, 15),
      ('Invalid long break', 25, 5, 61),
    ]) {
      expect(
        () => controller.saveRoutine(
          name: values.$1,
          focus: values.$2,
          shortBreak: values.$3,
          longBreak: values.$4,
        ),
        throwsArgumentError,
      );
      expect(store.contents, original);
    }
    final id = controller.saveRoutine(
      name: 'Study',
      focus: 45,
      shortBreak: 8,
      longBreak: 20,
    );
    final data = jsonDecode(store.contents!) as Map<String, dynamic>;
    final customs = data['settings']['customRoutines'] as List;
    customs.add(Map<String, dynamic>.from(customs.single as Map));
    expect(() => Workspace.decode(jsonEncode(data)), throwsFormatException);
    customs.removeLast();
    customs.single['id'] = 'classic';
    expect(() => Workspace.decode(jsonEncode(data)), throwsFormatException);
    expect(controller.routines.last.id, id);
  });

  testWidgets('changing routine confirms before discarding timer progress', (
    tester,
  ) async {
    controller.startTimer();
    now = now.add(const Duration(minutes: 2));
    await mountRoutines(tester, controller);
    final deadline = controller.timer.endsAt;
    await tester.tap(find.byKey(const Key('routine-selection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deep work').last);
    await tester.pumpAndSettle();
    expect(find.text('Switch to Deep work?'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(controller.timer.endsAt, deadline);
    expect(controller.activeRoutineId, 'classic');
    await tester.tap(find.byKey(const Key('routine-selection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deep work').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(controller.activeRoutineId, 'deep');
    expect(controller.timer.running, isFalse);
    expect(find.text('50:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings saves rhythm drafts only with Save settings', (
    tester,
  ) async {
    await mountRoutines(tester, controller);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('duration-focus')), '0');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 120 minutes.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('duration-focus')), '40');
    await tester.enterText(find.byKey(const Key('duration-shortBreak')), '8');
    await tester.enterText(find.byKey(const Key('duration-longBreak')), '20');
    await tester.ensureVisible(find.text('Save these durations'));
    await tester.tap(find.text('Save these durations'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('routine-name')));
    await tester.enterText(find.byKey(const Key('routine-name')), 'Writing');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(controller.workspace.settings.customRoutines, isEmpty);
    expect(find.text('Writing'), findsOneWidget);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(store.load()!.settings.customRoutines.single.name, 'Writing');
    expect(controller.remaining, 1500);
    expect(controller.workspace.settings.focusMinutes, 40);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete Writing'));
    await tester.tap(find.byTooltip('Delete Writing'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(StintSettings),
        matching: find.text('Writing'),
      ),
      findsNothing,
    );
    expect(controller.workspace.settings.customRoutines, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.workspace.settings.customRoutines, hasLength(1));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete Writing'));
    await tester.tap(find.byTooltip('Delete Writing'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(store.load()!.settings.customRoutines, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated Settings requests keep one sheet open', (tester) async {
    await mountRoutines(tester, controller);
    final context = tester.element(find.byTooltip('Settings'));
    showStintSettings(context, controller);
    showStintSettings(context, controller);
    await tester.pumpAndSettle();
    expect(find.byType(StintSettings), findsOneWidget);
    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();
    expect(find.byType(StintSettings), findsNothing);
  });

  testWidgets('rhythm radio and appearance changes stay draft on Cancel', (
    tester,
  ) async {
    await mountRoutines(tester, controller);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deep work'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('duration-focus')))
          .controller!
          .text,
      '50',
    );
    expect(controller.workspace.settings.focusMinutes, 25);
    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.workspace.settings.appearance, 'system');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.workspace.settings.focusMinutes, 25);
    expect(controller.workspace.settings.appearance, 'system');
    expect(find.byType(StintSettings), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
