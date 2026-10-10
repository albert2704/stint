import 'dart:io';
import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_desk/data/controller.dart';
import 'package:focus_desk/data/store.dart';
import 'package:focus_desk/main.dart';
import 'package:focus_desk/ui/pomodoro.dart';
import 'package:focus_desk/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('assets/fonts/HankenGrotesk/HankenGrotesk-Regular.ttf');
    await (FontLoader('HankenGrotesk')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
        .load();
  });

  testWidgets(
    'icon controls expose their label and tap action on one button node',
    (tester) async {
      final c = DeskController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(FocusDeskApp(controller: c));
        await tester.pumpAndSettle();
        for (final label in [
          'Settings',
          'Reset',
          'Skip to next',
          'Remove a minute',
          'Add a minute',
        ]) {
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          final data = node.getSemanticsData();
          expect(data.label, label);
          expect(data.flagsCollection.isButton, isTrue, reason: label);
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
        }
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'current cycle label and proportions reflect adjustment, not next defaults',
    (tester) async {
      var now = DateTime(2026, 10, 9, 12);
      final c = DeskController(
        MemoryWorkspaceStore(),
        now: () => now,
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: deskTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => CycleTrack(controller: c),
                ),
              ),
            ),
          ),
        ),
      );
      final current = find.byKey(const Key('cycle-step-0'));
      final future = find.byKey(const Key('cycle-step-2'));
      expect(find.byTooltip('Focus, 25 minutes, current'), findsOneWidget);
      expect(
        tester.getSize(current).width,
        closeTo(tester.getSize(future).width, .001),
      );
      c.adjustCurrent(1);
      await tester.pump();
      expect(find.byTooltip('Focus, 26 minutes, current'), findsOneWidget);
      expect(
        tester.getSize(current).width / tester.getSize(future).width,
        closeTo(26 / 25, .001),
      );
      c.adjustCurrent(-1);
      c.updateSettings(
        focus: 40,
        shortBreak: 5,
        longBreak: 15,
        appearance: 'light',
      );
      await tester.pump();
      expect(c.remaining, 1500);
      expect(find.byTooltip('Focus, 25 minutes, current'), findsOneWidget);
      expect(find.byTooltip('Focus, 40 minutes'), findsNWidgets(3));
      expect(
        tester.getSize(current).width / tester.getSize(future).width,
        closeTo(25 / 40, .001),
      );
      c.startTimer();
      now = now.add(const Duration(seconds: 29));
      c.adjustCurrent(-100);
      await tester.pump();
      expect(c.timer.totalSeconds, 89);
      expect(
        find.byTooltip('Focus, 1 minute 29 seconds, current'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation announces its title without making countdown a live region',
    (tester) async {
      final c = DeskController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      addTearDown(c.dispose);
      c.startTimer();
      c.requestReset();
      await tester.pumpWidget(
        MaterialApp(
          theme: deskTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(width: 420, child: TimerConfirmBar(controller: c)),
          ),
        ),
      );
      final live = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.liveRegion == true)
          .toList();
      expect(live, hasLength(1));
      expect(live.single.child, isA<Text>());
      expect((live.single.child as Text).data, 'Reset this stint?');
      expect(tester.takeException(), isNull);
    },
  );
}
