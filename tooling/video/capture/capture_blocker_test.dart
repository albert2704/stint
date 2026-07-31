// Regenerate from the repository root:
// bash scripts/flutter.sh test tooling/video/capture/capture_blocker_test.dart
//
// This media fixture renders the real app widget with synthetic controller data.
// It never starts Stint's native helper, changes network settings, or reads a
// personal workspace. The active status illustrates a configured focus session;
// it is not evidence of a live browser-blocking verification.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/blocker.dart';
import 'package:stint/ui/blocker_settings.dart';
import 'package:stint/ui/theme.dart';

class DemoBlockerController extends ChangeNotifier
    implements BlockerController {
  @override
  final settings = BlockerSettings(
    enabled: true,
    apps: [BlockedApp(bundleId: 'com.example.chat', name: 'Chat')],
    domains: ['youtube.com'],
    bypassSessionId: null,
  );

  @override
  bool get ready => true;
  @override
  bool get active => true;
  @override
  bool get bypassed => false;
  @override
  bool get checkingFilter => false;
  @override
  bool get enablingFilter => false;
  @override
  String? get error => null;
  @override
  String get sessionId => 'synthetic-video-session';
  @override
  String get statusLabel => 'Focus guard on';

  // Message matches the installed helper's active state in
  // macos/HostsBlocker/StintHostsHelper.m.
  @override
  WebsiteFilterStatus get filter => const WebsiteFilterStatus(
    WebsiteFilterState.configured,
    'Website proxy is active for browsers using macOS network settings. '
    'Browsers stay open; HTTPS stays encrypted.',
    active: true,
  );

  @override
  Future<void> refreshFilter() async {}

  // Any accidental interaction with native actions fails inside this fixture.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Read-only demo fixture: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final family in ['HankenGrotesk', 'MartianMono']) {
      final loader = FontLoader(family);
      final fonts =
          Directory('assets/fonts/$family')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.ttf'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final font in fonts) {
        loader.addFont(
          Future.value(ByteData.sublistView(font.readAsBytesSync())),
        );
      }
      await loader.load();
    }
  });

  testWidgets('capture actual blocker UI with synthetic focus data', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = DemoBlockerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('demo-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: stintTheme(Brightness.dark),
          home: BlockerSettingsDialog(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Focus guard on'), findsOneWidget);
    expect(find.text('youtube.com'), findsOneWidget);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('demo-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = png!.buffer.asUint8List();
      for (final path in [
        'tooling/video/assets/stint-blocker.png',
        'docs/media/stint-blocker.png',
      ]) {
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      image.dispose();
    });
  });
}
