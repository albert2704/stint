import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_desk/data/controller.dart';
import 'package:focus_desk/data/store.dart';
import 'package:focus_desk/keymap.dart';
import 'package:focus_desk/main.dart';
import 'package:focus_desk/ui/keymap_settings.dart';
import 'package:focus_desk/ui/routines.dart';
import 'package:focus_desk/ui/theme.dart';

Map<String, Object?> chord(int keyCode, String label) => {
  'keyCode': keyCode,
  'modifiers': 11,
  'label': label,
};

Map<String, Object?> defaultConfiguration() => {
  'global': true,
  'bindings': {
    'toggle': chord(35, '⌃⌥⌘P'),
    'reset': chord(15, '⌃⌥⌘R'),
    'skip': chord(45, '⌃⌥⌘N'),
    'panel': chord(1, '⌃⌥⌘S'),
  },
};

class FakeKeymap {
  final calls = <MethodCall>[];
  Map<String, Object?> saved = defaultConfiguration();
  String? initialError;
  bool unavailable = false;
  bool failLoad = false;
  String? saveFailure;
  String? cancelFailure;
  Completer<void>? pendingLoad;
  Completer<void>? pendingSave;
  Completer<Object?>? pendingRecord;

  Map<String, Object?> get state => {
    ...saved,
    'defaults': defaultConfiguration(),
    if (initialError != null) 'error': initialError,
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'getAlertSoundSettings') {
      return {
        'selectedSound': 'Glass',
        'sounds': ['Glass'],
      };
    }
    if (unavailable) throw MissingPluginException();
    switch (call.method) {
      case 'getShortcutSettings':
        await pendingLoad?.future;
        if (failLoad) throw PlatformException(code: 'load_failed');
        return state;
      case 'setShortcutSettings':
        await pendingSave?.future;
        if (saveFailure != null) {
          throw PlatformException(code: 'conflict', message: saveFailure);
        }
        saved = Map<String, Object?>.from(call.arguments as Map);
        initialError = null;
        return state;
      case 'recordShortcut':
        pendingRecord = Completer<Object?>();
        return pendingRecord!.future;
      case 'cancelShortcutRecording':
        if (pendingRecord?.isCompleted == false) {
          pendingRecord!.complete(null);
        }
        if (cancelFailure != null) {
          throw PlatformException(code: 'restore', message: cancelFailure);
        }
        return null;
      default:
        throw MissingPluginException();
    }
  }

  Iterable<MethodCall> get saves =>
      calls.where((call) => call.method == 'setShortcutSettings');
}

Future<void> openEditor(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: deskTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showKeymapSettings(context),
            child: const Text('Open shortcuts'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open shortcuts'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('focus_desk/timer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeKeymap native;

  setUp(() {
    native = FakeKeymap();
    messenger.setMockMethodCallHandler(channel, native.handle);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('settings decode native defaults and reject malformed payloads', () {
    final settings = ShortcutSettings.fromNative(native.state);
    expect(settings.configuration.global, isTrue);
    expect(
      settings.defaults.bindings[StintShortcutAction.toggle]!.label,
      '⌃⌥⌘P',
    );
    expect(settings.configuration.toNative(), defaultConfiguration());
    for (final value in [
      null,
      {...native.state, 'global': 1},
      {...native.state, 'bindings': <String, Object?>{}},
      {...native.state, 'defaults': null},
      {...native.state, 'error': 42},
      {
        ...native.state,
        'bindings': {
          ...(native.saved['bindings'] as Map),
          'toggle': {'keyCode': 35, 'modifiers': 11, 'label': ''},
        },
      },
    ]) {
      expect(() => ShortcutSettings.fromNative(value), throwsFormatException);
    }
    for (final binding in [
      {'keyCode': -1, 'modifiers': 11, 'label': 'P'},
      {'keyCode': 35.0, 'modifiers': 11, 'label': 'P'},
      {'keyCode': 35, 'modifiers': 0, 'label': 'P'},
      {'keyCode': 35, 'modifiers': 2, 'label': 'P'},
      {'keyCode': 35, 'modifiers': 16, 'label': 'P'},
    ]) {
      expect(() => ShortcutBinding.fromNative(binding), throwsFormatException);
    }
  });

  test('API uses existing channel and round trips disabled actions', () async {
    const api = StintKeymap();
    await api.load();
    final disabled = ShortcutConfiguration(
      global: false,
      bindings: {for (final action in StintShortcutAction.values) action: null},
    );
    final saved = await api.save(disabled);
    expect(saved.configuration.global, isFalse);
    expect(saved.configuration.bindings.values.every((v) => v == null), isTrue);
    expect(native.saves.single.arguments, disabled.toNative());
    final recorded = api.record();
    await Future<void>.delayed(Duration.zero);
    native.pendingRecord!.complete(chord(11, '⌃⌥⌘B'));
    expect((await recorded)!.keyCode, 11);
    await api.cancelRecording();
    expect(native.calls.last.method, 'cancelShortcutRecording');
  });

  testWidgets('loading blocks save and a cancelled load never opens again', (
    tester,
  ) async {
    native.pendingLoad = Completer<void>();
    await openEditor(tester);
    expect(find.text('Loading keyboard shortcuts…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save shortcuts'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('shortcut-cancel')));
    await tester.pumpAndSettle();
    native.pendingLoad!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(KeymapSettings), findsNothing);
    expect(native.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load error can retry and missing plugin is explicit', (
    tester,
  ) async {
    native.failLoad = true;
    await openEditor(tester);
    expect(
      find.text('Keyboard shortcuts could not be loaded. Try again.'),
      findsOneWidget,
    );
    native.failLoad = false;
    await tester.tap(find.text('Retry keyboard shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('⌃⌥⌘P'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shortcut-cancel')));
    await tester.pumpAndSettle();
    native.unavailable = true;
    await tester.tap(find.text('Open shortcuts'));
    await tester.pumpAndSettle();
    expect(
      find.text('Keyboard shortcuts are unavailable on this platform.'),
      findsOneWidget,
    );
    expect(find.text('Retry keyboard shortcuts'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save shortcuts'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('clear and scope remain drafts until save', (tester) async {
    await openEditor(tester);
    await tapVisible(tester, find.byKey(const Key('shortcut-clear-toggle')));
    expect((native.saved['bindings'] as Map)['toggle'], isNotNull);
    await tapVisible(tester, find.byType(DropdownButtonFormField<bool>));
    await tester.tap(find.text('Only in Stint').last);
    await tester.pumpAndSettle();
    expect(native.saved['global'], isTrue);
    await tester.tap(find.text('Save shortcuts'));
    await tester.pumpAndSettle();
    expect(native.saved['global'], isFalse);
    expect((native.saved['bindings'] as Map)['toggle'], isNull);
    expect(native.saves, hasLength(1));
    expect(find.byType(KeymapSettings), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel discards clear and restore drafts', (tester) async {
    native.saved = {
      'global': false,
      'bindings': {
        ...(native.saved['bindings'] as Map),
        'toggle': chord(11, '⌃⌥⌘B'),
      },
    };
    await openEditor(tester);
    await tapVisible(tester, find.byKey(const Key('shortcut-clear-toggle')));
    await tapVisible(tester, find.text('Restore defaults'));
    expect(find.text('⌃⌥⌘P'), findsOneWidget);
    expect(native.saved['global'], isFalse);
    await tester.tap(find.byKey(const Key('shortcut-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('⌃⌥⌘B'), findsOneWidget);
    expect(native.saved['global'], isFalse);
    expect(native.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native conflict stays visible and retains recorded draft', (
    tester,
  ) async {
    native.initialError = 'A saved shortcut is currently in use.';
    await openEditor(tester);
    expect(find.text(native.initialError!), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('shortcut-record-toggle')));
    expect(find.text('Press shortcut…'), findsOneWidget);
    expect(find.text('Escape cancels.'), findsOneWidget);
    native.pendingRecord!.complete(chord(11, '⌃⌥⌘B'));
    await tester.pumpAndSettle();
    native.saveFailure =
        'This shortcut is already used by Reset. Choose another shortcut.';
    await tester.tap(find.text('Save shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text(native.saveFailure!), findsOneWidget);
    expect(find.text('⌃⌥⌘B'), findsOneWidget);
    expect((native.saved['bindings'] as Map)['toggle'], chord(35, '⌃⌥⌘P'));
    expect(find.byType(KeymapSettings), findsOneWidget);
    native.saveFailure = null;
    await tester.tap(find.text('Save shortcuts'));
    await tester.pumpAndSettle();
    expect((native.saved['bindings'] as Map)['toggle'], chord(11, '⌃⌥⌘B'));
    expect(find.byType(KeymapSettings), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving disables actions and double submission', (tester) async {
    native.pendingSave = Completer<void>();
    await openEditor(tester);
    await tester.tap(find.text('Save shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('shortcut-cancel')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('shortcut-record-toggle')),
          )
          .onPressed,
      isNull,
    );
    native.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(native.saves, hasLength(1));
    expect(find.byType(KeymapSettings), findsNothing);
  });

  testWidgets(
    'record cancellation keeps old binding and allows another attempt',
    (tester) async {
      await openEditor(tester);
      await tapVisible(tester, find.byKey(const Key('shortcut-record-toggle')));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save shortcuts'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('shortcut-cancel-recording')));
      await tester.pumpAndSettle();
      expect(native.calls.last.method, 'cancelShortcutRecording');
      expect(find.text('⌃⌥⌘P'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shortcut-record-toggle')));
      await tester.pumpAndSettle();
      native.pendingRecord!.complete(
        null,
      ); // Native Escape or app deactivation.
      await tester.pumpAndSettle();
      expect(find.text('Press shortcut…'), findsNothing);
      expect(find.text('⌃⌥⌘P'), findsOneWidget);
      expect(native.saves, isEmpty);
    },
  );

  testWidgets('closing while recording cancels native capture first', (
    tester,
  ) async {
    await openEditor(tester);
    await tapVisible(tester, find.byKey(const Key('shortcut-record-toggle')));
    await tester.tap(find.byKey(const Key('shortcut-cancel')));
    await tester.pumpAndSettle();
    expect(native.calls.last.method, 'cancelShortcutRecording');
    expect(find.byType(KeymapSettings), findsNothing);
    expect(native.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancellation restoration failure keeps editor and error visible',
    (tester) async {
      await openEditor(tester);
      await tapVisible(tester, find.byKey(const Key('shortcut-record-toggle')));
      native.cancelFailure =
          'The prior shortcut could not be restored. Save another shortcut.';
      await tester.tap(find.byKey(const Key('shortcut-cancel')));
      await tester.pumpAndSettle();
      expect(find.text(native.cancelFailure!), findsOneWidget);
      expect(find.byType(KeymapSettings), findsOneWidget);
      expect(find.text('Press shortcut…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing an active recording cancels without leaking callbacks',
    (tester) async {
      await openEditor(tester);
      await tapVisible(tester, find.byKey(const Key('shortcut-record-toggle')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(native.calls.last.method, 'cancelShortcutRecording');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings shortcut save is separate from unsaved duration drafts',
    (tester) async {
      final controller = DeskController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(FocusDeskApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('duration-focus')), '40');
      await tapVisible(
        tester,
        find.byKey(const Key('open-keyboard-shortcuts')),
      );
      await tapVisible(tester, find.byKey(const Key('shortcut-clear-toggle')));
      await tester.tap(find.text('Save shortcuts'));
      await tester.pumpAndSettle();
      expect(find.byType(StintSettings), findsOneWidget);
      expect(find.text('Keyboard shortcuts save separately.'), findsOneWidget);
      expect(controller.workspace.settings.focusMinutes, 25);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.workspace.settings.focusMinutes, 25);
      expect((native.saved['bindings'] as Map)['toggle'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
