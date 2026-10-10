import 'dart:io';
import 'package:flutter/material.dart';
import 'data/controller.dart';
import 'data/store.dart';
import 'native_files.dart';
import 'native_timer.dart';
import 'music.dart';
import 'timer_music.dart';
import 'ui/routines.dart';
import 'ui/pomodoro.dart';
import 'ui/progress.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  StintController? controller;
  FileWorkspaceStore? store;
  String? error;
  NativeTimerBridge? timerBridge;
  FocusMusic? music;
  TimerMusicCoordinator? timerMusic;
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool restore = false}) async {
    setState(() {
      error = null;
    });
    try {
      store ??= FileWorkspaceStore(
        Directory(await NativeFiles.dataDirectory()),
      );
      if (restore) {
        store!.restorePrevious();
      }
      final loaded = StintController(store!);
      final loadedMusic = FocusMusic();
      await loadedMusic.load();
      if (!mounted) {
        loadedMusic.dispose();
        loaded.dispose();
        return;
      }
      setState(() {
        controller = loaded;
        music = loadedMusic;
      });
      timerMusic = TimerMusicCoordinator(loaded, loadedMusic);
      timerBridge = NativeTimerBridge(
        loaded,
        music: loadedMusic,
        onSettings: () async {
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            await showStintSettings(context, loaded);
          }
        },
        onProgress: () async {
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            await showStintProgress(context, loaded);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Stint could not load your timer. Your saved files have been kept. Retry, or recover the previous save.';
        });
      }
    }
  }

  @override
  void dispose() {
    timerBridge?.dispose();
    timerMusic?.dispose();
    music?.dispose();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return StintApp(
        controller: controller!,
        navigatorKey: navigatorKey,
        music: music,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: stintTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 24),
                        Text('Opening your timer…'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_off_outlined, size: 40),
                        const SizedBox(height: 24),
                        Text(error!),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: _load,
                              child: const Text('Try again'),
                            ),
                            if (store?.backup.existsSync() ?? false)
                              OutlinedButton(
                                onPressed: () => _load(restore: true),
                                child: const Text('Recover previous save'),
                              ),
                          ],
                        ),
                        if (store != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: SelectableText(store!.location),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class StintApp extends StatelessWidget {
  const StintApp({
    super.key,
    required this.controller,
    this.navigatorKey,
    this.music,
  });
  final StintController controller;
  final GlobalKey<NavigatorState>? navigatorKey;
  final FocusMusic? music;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Stint',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: stintTheme(Brightness.light),
      darkTheme: stintTheme(Brightness.dark),
      themeMode: switch (controller.workspace.settings.appearance) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      home: PomodoroScreen(controller: controller, music: music),
    ),
  );
}
