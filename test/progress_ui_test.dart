import 'dart:async';
import 'dart:ui' show Tristate;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_desk/data/controller.dart';
import 'package:focus_desk/data/models.dart';
import 'package:focus_desk/data/store.dart';
import 'package:focus_desk/ui/progress.dart';
import 'package:focus_desk/ui/theme.dart';

final _friday = DateTime(2026, 10, 9, 12);

FocusSession _stint(int day, int hour) => FocusSession(
  id: '$day-$hour',
  taskTitle: 'Open focus',
  projectName: '',
  seconds: 25 * 60,
  finishedAt: DateTime(2026, 10, day, hour),
);

Future<void> _mount(
  WidgetTester tester,
  DeskController controller, {
  bool localized = false,
  bool duplicateOpen = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: deskTheme(Brightness.light),
      localizationsDelegates: [
        if (localized) const _MondayLocalizationsDelegate(),
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              unawaited(showStintProgress(context, controller));
              if (duplicateOpen) {
                unawaited(showStintProgress(context, controller));
              }
            },
            child: const Text('Show progress'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show progress'));
  await tester.pumpAndSettle();
}

class _FailingStore extends MemoryWorkspaceStore {
  bool failing = true;
  @override
  void save(Workspace workspace) {
    if (failing) throw StateError('disk full');
    super.save(workspace);
  }
}

/// Exercises the MaterialLocalizations contract without adding a runtime
/// localization dependency to an app whose current language is English.
class _MondayLocalizations extends DefaultMaterialLocalizations {
  const _MondayLocalizations();
  @override
  int get firstDayOfWeekIndex => 1;
  static const weekdays = [
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.',
  ];
  @override
  String formatMediumDate(DateTime date) =>
      '${weekdays[date.weekday - 1]}, ${formatShortMonthDay(date)}';
  @override
  String formatShortMonthDay(DateTime date) => '${date.day} oct.';
}

class _MondayLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _MondayLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture(const _MondayLocalizations());
  @override
  bool shouldReload(_MondayLocalizationsDelegate old) => false;
}

void main() {
  testWidgets('locale controls week start, dates and weekday labels', (
    tester,
  ) async {
    final controller = DeskController(
      MemoryWorkspaceStore(),
      now: () => _friday,
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    controller.workspace.sessions.addAll([_stint(4, 9), _stint(5, 9)]);
    controller.persist();
    await _mount(tester, controller, localized: true);
    expect(find.text('lun.'), findsOneWidget);
    expect(find.text('dim.'), findsOneWidget);
    expect(
      find.text('1 stint · 25m'),
      findsOneWidget,
      reason: 'Sunday belongs to the preceding week in this locale',
    );
    expect(find.byTooltip('lun., 5 oct. · 1 stint · 25m'), findsOneWidget);
    expect(find.byTooltip('sam. · upcoming'), findsOneWidget);
    expect(find.bySemanticsLabel('dim. · upcoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all chart days are keyboard buttons, including upcoming days', (
    tester,
  ) async {
    final controller = DeskController(
      MemoryWorkspaceStore(),
      now: () => _friday,
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    final labels = [
      'Sun, Oct 4 · 0 stints · 0m',
      'Mon, Oct 5 · 0 stints · 0m',
      'Tue, Oct 6 · 0 stints · 0m',
      'Wed, Oct 7 · 0 stints · 0m',
      'Thu, Oct 8 · 0 stints · 0m',
      'Fri, Oct 9 · 0 stints · 0m',
      'Sat · upcoming',
    ];
    for (final label in labels) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(node.flagsCollection.isButton, isTrue, reason: label);
      expect(
        node.flagsCollection.isFocused != Tristate.none,
        isTrue,
        reason: label,
      );
    }
    final visited = <String>{};
    for (var i = 0; i < 14; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 250));
      for (final label in labels) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        if (node.flagsCollection.isFocused == Tristate.isTrue) {
          visited.add(label);
          expect(
            find.text(label),
            findsOneWidget,
            reason: 'focusing a chart day reveals its tooltip',
          );
        }
      }
    }
    expect(visited, labels.toSet());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('failed immediate goal save is visible and can be retried', (
    tester,
  ) async {
    final store = _FailingStore();
    final controller = DeskController(
      store,
      now: () => _friday,
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const Key('daily-goal-up')));
    await tester.pump();
    expect(controller.workspace.settings.dailyGoal, 9);
    expect(store.contents, isNull);
    expect(find.text(controller.saveError!), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
    store.failing = false;
    await tester.tap(find.text('Retry save'));
    await tester.pump();
    expect(find.text('Retry save'), findsNothing);
    expect(Workspace.decode(store.contents!).settings.dailyGoal, 9);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated open requests produce one modal route', (tester) async {
    final controller = DeskController(
      MemoryWorkspaceStore(),
      now: () => _friday,
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    await _mount(tester, controller, duplicateOpen: true);
    expect(find.byKey(const Key('progress-sheet')), findsOneWidget);
    await tester.tap(find.byTooltip('Close progress'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-sheet')), findsNothing);
    expect(find.text('Show progress').hitTestable(), findsOneWidget);
  });

  testWidgets('above-goal counts fit compact layout and pips are decorative', (
    tester,
  ) async {
    final controller = DeskController(
      MemoryWorkspaceStore(),
      now: () => _friday,
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    for (var i = 0; i < 25; i++) {
      controller.workspace.sessions.add(
        FocusSession(
          id: 'today-$i',
          taskTitle: 'Open focus',
          projectName: '',
          seconds: 25 * 60,
          finishedAt: DateTime(2026, 10, 9, 0, 30 + i * 26),
        ),
      );
    }
    controller.persist();
    await _mount(tester, controller);
    expect(find.text('+17'), findsOneWidget);
    expect(find.bySemanticsLabel('+17'), findsNothing);
    expect(find.text('Goal met. Anything more is a bonus.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
