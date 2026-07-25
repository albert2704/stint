import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/blocker.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/store.dart';
import 'package:stint/ui/blocker_settings.dart';
import 'package:stint/ui/routines.dart';
import 'package:stint/ui/theme.dart';

class FakeBlockerController extends ChangeNotifier
    implements BlockerController {
  @override
  BlockerSettings settings = BlockerSettings(
    enabled: false,
    apps: [BlockedApp(bundleId: 'com.example.chat', name: 'Chat')],
    domains: ['reddit.com'],
    bypassSessionId: null,
  );
  @override
  bool ready = true;
  @override
  bool active = false;
  @override
  String? error;
  @override
  WebsiteFilterStatus filter = const WebsiteFilterStatus(
    WebsiteFilterState.notInstalled,
    'Enable the website filter.',
  );
  @override
  bool checkingFilter = false;
  @override
  bool enablingFilter = false;
  @override
  String statusLabel = 'Ready for your next stint';
  @override
  String? sessionId = 'session-1';
  @override
  bool bypassed = false;

  bool failSave = false;
  int saves = 0;
  final unblockedSessions = <String>[];
  List<BlockedApp> selectedApps = [];

  @override
  Future<List<BlockedApp>> chooseApps() async => selectedApps;

  @override
  Future<void> refreshFilter() async {
    refreshes++;
    notifyListeners();
  }

  int refreshes = 0;
  int setupRequests = 0;
  int removals = 0;
  @override
  Future<void> removeFilter() async {
    removals++;
    filter = const WebsiteFilterStatus(
      WebsiteFilterState.approvalRequired,
      'Open the removal command in Finder, then finish in Terminal.',
    );
    notifyListeners();
  }

  @override
  Future<void> enableFilter() async {
    setupRequests++;
    filter = const WebsiteFilterStatus(
      WebsiteFilterState.approvalRequired,
      'Open the setup command in Finder, then finish in Terminal.',
    );
    notifyListeners();
  }

  @override
  bool relaxesProtection({
    required bool enabled,
    required List<BlockedApp> apps,
    required List<String> domains,
  }) =>
      active &&
      (!enabled ||
          settings.apps.any(
            (old) => !apps.any((app) => app.bundleId == old.bundleId),
          ) ||
          settings.domains.any((domain) => !domains.contains(domain)));

  @override
  Future<void> save({
    required bool enabled,
    required List<BlockedApp> apps,
    required List<String> domains,
  }) async {
    if (failSave) throw Exception('Disk unavailable');
    saves++;
    settings = BlockerSettings(
      enabled: enabled,
      apps: apps,
      domains: domains,
      bypassSessionId: settings.bypassSessionId,
    );
    notifyListeners();
  }

  @override
  Future<void> unblock(String sessionId) async {
    unblockedSessions.add(sessionId);
    active = false;
    bypassed = true;
    statusLabel = 'Unblocked for this stint';
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openEditor(
  WidgetTester tester,
  FakeBlockerController controller,
) async {
  tester.view.physicalSize = const Size(420, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: stintTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBlockerSettings(context, controller),
            child: const Text('Open blocker'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open blocker'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('repeated native requests keep a single editor and its draft', (
    tester,
  ) async {
    final controller = FakeBlockerController();
    await openEditor(tester, controller);
    await tapVisible(
      tester,
      find.byKey(const Key('blocker-remove-app-com.example.chat')),
    );
    final sourceContext = tester.element(
      find.text('Open blocker', skipOffstage: false),
    );
    unawaited(showBlockerSettings(sourceContext, controller));
    unawaited(showBlockerSettings(sourceContext, controller));
    await tester.pumpAndSettle();
    expect(
      find.byType(BlockerSettingsDialog, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('No apps selected.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('blocker-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(BlockerSettingsDialog), findsNothing);
    await tester.tap(find.text('Open blocker'));
    await tester.pumpAndSettle();
    expect(find.byType(BlockerSettingsDialog), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(controller.saves, 0);
  });

  testWidgets('cancel discards draft edits at menu panel size', (tester) async {
    final controller = FakeBlockerController();
    await openEditor(tester, controller);
    await tapVisible(tester, find.byKey(const Key('blocker-enabled')));
    await tapVisible(
      tester,
      find.byKey(const Key('blocker-remove-app-com.example.chat')),
    );
    await tester.tap(find.byKey(const Key('blocker-cancel')));
    await tester.pumpAndSettle();

    expect(controller.saves, 0);
    expect(controller.settings.enabled, isFalse);
    expect(controller.settings.apps.single.name, 'Chat');
    expect(find.byType(BlockerSettingsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings reveals a covered blocker and preserves both unsaved drafts',
    (tester) async {
      final controller = FakeBlockerController();
      final timer = StintController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      addTearDown(timer.dispose);
      await openEditor(tester, controller);
      final input = find.byKey(const Key('blocker-domain-input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'example.com');
      await tapVisible(tester, find.byKey(const Key('blocker-add-domain')));
      await tester.enterText(input, 'pending.example.com');
      final sourceContext = tester.element(
        find.text('Open blocker', skipOffstage: false),
      );

      // A native Settings request can cover an already-open blocker editor.
      unawaited(showStintSettings(sourceContext, timer, blocker: controller));
      await tester.pumpAndSettle();
      final duration = find.byKey(const Key('duration-focus'));
      await tester.ensureVisible(duration);
      await tester.enterText(duration, '37');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Block distractions…'));

      expect(
        ModalRoute.of(
          tester.element(find.byType(BlockerSettingsDialog)),
        )!.isCurrent,
        isTrue,
        reason: 'An existing blocker editor must be brought above Settings.',
      );
      expect(
        find.byType(BlockerSettingsDialog, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('example.com'), findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'pending.example.com',
      );
      expect(controller.settings.domains, ['reddit.com']);
      expect(controller.saves, 0);

      // Switching back through the native Settings entry preserves its draft.
      unawaited(showStintSettings(sourceContext, timer, blocker: controller));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.byType(StintSettings)))!.isCurrent,
        isTrue,
      );
      expect(find.byType(StintSettings, skipOffstage: false), findsOneWidget);
      expect(tester.widget<TextFormField>(duration).controller!.text, '37');

      // A native blocker request also reveals the same editor a second time.
      unawaited(showBlockerSettings(sourceContext, controller));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(find.byType(BlockerSettingsDialog)),
        )!.isCurrent,
        isTrue,
      );
      expect(
        find.byType(BlockerSettingsDialog, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('example.com'), findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'pending.example.com',
      );

      await tester.tap(find.byKey(const Key('blocker-cancel')));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.byType(StintSettings)))!.isCurrent,
        isTrue,
      );
      expect(tester.widget<TextFormField>(duration).controller!.text, '37');
      expect(timer.workspace.settings.focusMinutes, 25);
      expect(
        find.byType(BlockerSettingsDialog, skipOffstage: false),
        findsNothing,
      );

      // Cancel Settings too: neither draft is saved or left hidden underneath.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(StintSettings, skipOffstage: false), findsNothing);
      expect(
        find.byType(BlockerSettingsDialog, skipOffstage: false),
        findsNothing,
      );
      await tester.tap(find.text('Open blocker'));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(find.byType(BlockerSettingsDialog)),
        )!.isCurrent,
        isTrue,
      );
      expect(find.text('example.com'), findsNothing);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid domain prevents save and pending valid URL is included',
    (tester) async {
      final controller = FakeBlockerController();
      await openEditor(tester, controller);
      final input = find.byKey(const Key('blocker-domain-input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'localhost');
      await tester.tap(find.byKey(const Key('blocker-save')));
      await tester.pumpAndSettle();
      expect(controller.saves, 0);
      expect(find.textContaining('Enter a website such as'), findsOneWidget);

      await tester.enterText(input, 'https://Example.com/path');
      await tester.tap(find.byKey(const Key('blocker-save')));
      await tester.pumpAndSettle();
      expect(controller.saves, 1);
      expect(controller.settings.domains, ['reddit.com', 'example.com']);
      expect(find.byType(BlockerSettingsDialog), findsNothing);
    },
  );

  testWidgets('relaxing an active blocklist requires confirmation', (
    tester,
  ) async {
    final controller = FakeBlockerController()..active = true;
    controller.settings = BlockerSettings(
      enabled: true,
      apps: controller.settings.apps,
      domains: controller.settings.domains,
      bypassSessionId: null,
    );
    await openEditor(tester, controller);
    await tapVisible(
      tester,
      find.byKey(const Key('blocker-remove-app-com.example.chat')),
    );
    await tester.tap(find.byKey(const Key('blocker-save')));
    await tester.pumpAndSettle();
    expect(find.text('Change your active blocklist?'), findsOneWidget);
    await tester.tap(find.text('Keep blocking'));
    await tester.pumpAndSettle();
    expect(controller.saves, 0);
    expect(controller.settings.apps, hasLength(1));

    await tester.tap(find.byKey(const Key('blocker-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(controller.saves, 1);
    expect(controller.settings.apps, isEmpty);
  });

  testWidgets(
    'timer updates preserve the draft and a failed save keeps it open',
    (tester) async {
      final controller = FakeBlockerController()..failSave = true;
      await openEditor(tester, controller);
      await tapVisible(
        tester,
        find.byKey(const Key('blocker-remove-app-com.example.chat')),
      );
      controller.statusLabel = 'Paused';
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('No apps selected.'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.byKey(const Key('blocker-save')));
      await tester.pumpAndSettle();
      expect(find.byType(BlockerSettingsDialog), findsOneWidget);
      expect(
        find.textContaining('Your blocklist could not be saved'),
        findsOneWidget,
      );
      expect(controller.settings.apps, hasLength(1));
      expect(find.text('No apps selected.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('early unblock cannot apply to a different focus session', (
    tester,
  ) async {
    final controller = FakeBlockerController()..active = true;
    await openEditor(tester, controller);
    await tester.tap(find.byKey(const Key('blocker-unblock')));
    await tester.pumpAndSettle();
    controller.sessionId = 'session-2';
    controller.notifyListeners();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock this stint'));
    await tester.pumpAndSettle();
    expect(controller.unblockedSessions, isEmpty);
    expect(
      find.text('The focus stint has changed. No blocking was released.'),
      findsOneWidget,
    );
  });

  testWidgets('early unblock confirms and leaves saved blocklist intact', (
    tester,
  ) async {
    final controller = FakeBlockerController()..active = true;
    await openEditor(tester, controller);
    await tester.tap(find.byKey(const Key('blocker-unblock')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock this stint'));
    await tester.pumpAndSettle();
    expect(controller.unblockedSessions, ['session-1']);
    expect(controller.saves, 0);
    expect(
      find.text('Blocking returns for your next focus stint.'),
      findsOneWidget,
    );
  });

  testWidgets('reopening blocker keeps its unblock confirmation reachable', (
    tester,
  ) async {
    final controller = FakeBlockerController()..active = true;
    await openEditor(tester, controller);
    final sourceContext = tester.element(
      find.text('Open blocker', skipOffstage: false),
    );
    await tester.tap(find.byKey(const Key('blocker-unblock')));
    await tester.pumpAndSettle();

    unawaited(showBlockerSettings(sourceContext, controller));
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(
        tester.element(find.text('Unblock this stint?')),
      )!.isCurrent,
      isTrue,
      reason: 'Reopening must not hide a confirmation behind its busy editor.',
    );
    expect(controller.unblockedSessions, isEmpty);
    await tester.tap(find.text('Keep blocking'));
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(
        tester.element(find.byType(BlockerSettingsDialog)),
      )!.isCurrent,
      isTrue,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('blocker-cancel')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('blocker-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byType(BlockerSettingsDialog, skipOffstage: false),
      findsNothing,
    );
    expect(controller.unblockedSessions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter setup is explicit and does not save the blocklist', (
    tester,
  ) async {
    final controller = FakeBlockerController();
    await openEditor(tester, controller);
    expect(controller.setupRequests, 0);
    expect(find.text('Website blocker'), findsOneWidget);
    expect(find.text('Allow access'), findsNothing);
    await tapVisible(tester, find.byKey(const Key('blocker-refresh-filter')));
    expect(controller.refreshes, 1);
    expect(controller.setupRequests, 0);
    await tapVisible(tester, find.byKey(const Key('blocker-enable-filter')));
    expect(controller.setupRequests, 1);
    expect(find.text('Finish helper setup'), findsOneWidget);
    expect(find.textContaining('Open the setup command in Finder'), findsOneWidget);
    expect(find.text('Helper ready'), findsNothing);
    expect(controller.saves, 0);
    controller.filter = const WebsiteFilterStatus(
      WebsiteFilterState.configured,
      'Helper is ready.',
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Helper ready'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('blocker-remove-helper')));
    expect(controller.removals, 1);
    expect(controller.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing helper is honest and retains unsaved draft edits', (
    tester,
  ) async {
    final controller = FakeBlockerController();
    await openEditor(tester, controller);
    await tapVisible(
      tester,
      find.byKey(const Key('blocker-remove-app-com.example.chat')),
    );
    controller.filter = const WebsiteFilterStatus(
      WebsiteFilterState.notInstalled,
      'Set up the free helper first.',
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('No apps selected.'), findsOneWidget);
    expect(find.text('Setup needed'), findsOneWidget);
    expect(find.byKey(const Key('blocker-enable-filter')), findsOneWidget);
    expect(find.text('Helper ready'), findsNothing);
    expect(find.textContaining('Browsers stay open'), findsOneWidget);
    expect(controller.setupRequests, 0);
  });

  testWidgets('loading state prevents saving and reports controller failures', (
    tester,
  ) async {
    final controller = FakeBlockerController()
      ..ready = false
      ..error = 'Your saved blocklist could not be loaded.';
    await openEditor(tester, controller);
    expect(find.text('Loading your blocklist…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('blocker-save')))
          .onPressed,
      isNull,
    );
    expect(find.text(controller.error!), findsOneWidget);
    controller.ready = true;
    controller.error = null;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Loading your blocklist…'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('blocker-save')))
          .onPressed,
      isNotNull,
    );
  });
}
