import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_desk/alert_sounds.dart';
import 'package:focus_desk/data/controller.dart';
import 'package:focus_desk/data/store.dart';
import 'package:focus_desk/main.dart';
import 'package:focus_desk/ui/routines.dart';
import 'controller_test.dart' show FailingStore;

class FakeAlertSounds {
  static const sounds = ['Glass', 'Ping', 'Pop', 'Funk', 'Submarine', 'Basso'];
  final calls = <MethodCall>[];
  String selected = 'Glass';
  bool unavailable = false;
  bool failLoad = false;
  bool failPreview = false;
  bool failSave = false;
  String? failSaveSound;
  Completer<void>? pendingLoad;
  Completer<void>? pendingSave;

  Map<String, Object> get state => {
    'selectedSound': selected,
    'sounds': sounds,
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (unavailable) throw MissingPluginException();
    switch (call.method) {
      case 'getAlertSoundSettings':
        await pendingLoad?.future;
        if (failLoad) throw PlatformException(code: 'load_failed');
        return state;
      case 'previewAlertSound':
        if (failPreview) throw PlatformException(code: 'preview_failed');
        return {'durationMilliseconds': 3550};
      case 'setAlertSound':
        await pendingSave?.future;
        if (failSave || call.arguments == failSaveSound) {
          throw PlatformException(code: 'save_failed');
        }
        selected = call.arguments as String;
        return state;
      default:
        throw MissingPluginException();
    }
  }
}

Future<void> openSoundSettings(
  WidgetTester tester,
  DeskController controller, {
  Size size = const Size(520, 820),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(FocusDeskApp(controller: controller));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Settings'));
  // This also supports tests that deliberately leave the native load pending.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> chooseSound(WidgetTester tester, String sound) async {
  await tester.ensureVisible(find.byKey(Key('alert-sound-$sound')));
  await tester.tap(find.byKey(Key('alert-sound-$sound')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('focus_desk/timer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeAlertSounds native;
  late DeskController controller;

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
    native = FakeAlertSounds();
    messenger.setMockMethodCallHandler(channel, native.handle);
    controller = DeskController(
      MemoryWorkspaceStore(),
      tickAutomatically: false,
    );
  });

  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'native settings reject invalid choices instead of creating an invalid dropdown',
    () {
      expect(
        AlertSoundSettings.fromNative(native.state).selectedSound,
        'Glass',
      );
      for (final invalid in [
        null,
        {'selectedSound': 'Glass', 'sounds': <String>[]},
        {
          'selectedSound': 'Unknown',
          'sounds': ['Glass'],
        },
        {
          'selectedSound': 'Glass',
          'sounds': ['Glass', 'Glass'],
        },
        {
          'selectedSound': 'Glass',
          'sounds': ['Glass', 42],
        },
      ]) {
        expect(
          () => AlertSoundSettings.fromNative(invalid),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets(
    'native choices preview without saving, then Save persists sound and durations',
    (tester) async {
      controller.startTimer();
      final deadline = controller.timer.endsAt;
      await openSoundSettings(tester, controller);
      await tester.pumpAndSettle();
      expect(
        find.text('Plays twice when a stint or break ends.'),
        findsOneWidget,
      );
      for (final sound in FakeAlertSounds.sounds) {
        expect(find.byKey(Key('alert-sound-$sound')), findsOneWidget);
      }
      await chooseSound(tester, 'Funk');
      await tester.tap(find.byKey(const Key('preview-alert-sound')));
      await tester.pumpAndSettle();
      expect(native.calls.last.method, 'previewAlertSound');
      expect(native.calls.last.arguments, 'Funk');
      expect(find.text('Playing Funk twice…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3550));
      expect(
        find.text('Plays twice when a stint or break ends.'),
        findsOneWidget,
      );
      expect(native.selected, 'Glass');
      expect(
        native.calls.where((call) => call.method == 'setAlertSound'),
        isEmpty,
      );
      await tester.ensureVisible(find.byKey(const Key('duration-focus')));
      await tester.enterText(find.byKey(const Key('duration-focus')), '40');
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(native.selected, 'Funk');
      expect(
        native.calls.where((call) => call.method == 'setAlertSound'),
        hasLength(1),
      );
      expect(controller.workspace.settings.focusMinutes, 40);
      expect(controller.timer.endsAt, deadline);
      expect(find.byType(StintSettings), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancel discards sound and duration drafts in a compact window', (
    tester,
  ) async {
    await openSoundSettings(tester, controller, size: const Size(420, 600));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('duration-focus')), '45');
    await chooseSound(tester, 'Submarine');
    await tester.ensureVisible(find.byKey(const Key('preview-alert-sound')));
    await tester.tap(find.byKey(const Key('preview-alert-sound')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(native.selected, 'Glass');
    expect(controller.workspace.settings.focusMinutes, 25);
    expect(
      native.calls.where((call) => call.method == 'setAlertSound'),
      isEmpty,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Preview Glass'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading blocks Save, load failure offers Retry, and Cancel can dismiss pending load',
    (tester) async {
      native.pendingLoad = Completer<void>();
      native.failLoad = true;
      await openSoundSettings(tester, controller);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save settings'),
            )
            .onPressed,
        isNull,
      );
      native.pendingLoad!.complete();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Alert sounds could not be loaded. Try again.'),
      );
      expect(
        find.text('Alert sounds could not be loaded. Try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save settings'),
            )
            .onPressed,
        isNull,
      );
      native.failLoad = false;
      await tester.tap(find.text('Retry alert sounds'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-sound-selection')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      native.pendingLoad = Completer<void>();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      native.pendingLoad!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StintSettings), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview and save errors stay visible without applying duration changes',
    (tester) async {
      await openSoundSettings(tester, controller);
      await tester.pumpAndSettle();
      await chooseSound(tester, 'Ping');
      native.failPreview = true;
      await tester.tap(find.byKey(const Key('preview-alert-sound')));
      await tester.pumpAndSettle();
      expect(
        find.text('This alert sound could not be previewed. Try again.'),
        findsOneWidget,
      );
      expect(native.selected, 'Glass');
      await tester.ensureVisible(find.byKey(const Key('duration-focus')));
      await tester.enterText(find.byKey(const Key('duration-focus')), '35');
      native.failSave = true;
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your alert sound could not be saved. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(StintSettings), findsOneWidget);
      expect(controller.workspace.settings.focusMinutes, 25);
      expect(native.selected, 'Glass');
      native.failSave = false;
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(native.selected, 'Ping');
      expect(controller.workspace.settings.focusMinutes, 35);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed workspace Save restores settings and sound, then retries the draft',
    (tester) async {
      controller.dispose();
      final store = FailingStore();
      controller = DeskController(store, tickAutomatically: false);
      controller.startTimer();
      final deadline = controller.timer.endsAt;
      store.fail = true;
      await openSoundSettings(tester, controller);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('duration-focus')), '40');
      await chooseSound(tester, 'Ping');
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(controller.workspace.settings.focusMinutes, 25);
      expect(controller.timer.endsAt, deadline);
      expect(native.selected, 'Glass');
      expect(
        native.calls
            .where((call) => call.method == 'setAlertSound')
            .map((call) => call.arguments),
        ['Ping', 'Glass'],
      );
      expect(find.textContaining('Your draft is still here'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('duration-focus')))
            .controller!
            .text,
        '40',
      );
      store.fail = false;
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(native.selected, 'Ping');
      expect(controller.workspace.settings.focusMinutes, 40);
      expect(controller.timer.endsAt, deadline);
      expect(find.byType(StintSettings), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed sound rollback is reported without claiming it was restored',
    (tester) async {
      controller.dispose();
      final store = FailingStore()..fail = true;
      controller = DeskController(store, tickAutomatically: false);
      await openSoundSettings(tester, controller);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('duration-focus')), '40');
      await chooseSound(tester, 'Ping');
      native.failSaveSound = 'Glass';
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(controller.workspace.settings.focusMinutes, 25);
      expect(native.selected, 'Ping');
      expect(
        find.textContaining(
          'The alert sound may have changed and could not be restored.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.workspace.settings.focusMinutes, 25);
      expect(find.byType(StintSettings), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'platforms without the native sound API can still save timer settings',
    (tester) async {
      native.unavailable = true;
      await openSoundSettings(tester, controller);
      await tester.pumpAndSettle();
      expect(
        find.text('Alert sounds are unavailable on this platform.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('duration-shortBreak')), '7');
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(controller.workspace.settings.shortBreakMinutes, 7);
      expect(find.byType(StintSettings), findsNothing);
      expect(native.calls.map((call) => call.method), [
        'getAlertSoundSettings',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
