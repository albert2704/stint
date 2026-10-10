import 'package:flutter/services.dart';

enum StintShortcutAction {
  toggle('Start/Pause'),
  reset('Reset'),
  skip('Skip'),
  panel('Show timer panel');

  const StintShortcutAction(this.label);
  final String label;
}

class ShortcutBinding {
  const ShortcutBinding({
    required this.keyCode,
    required this.modifiers,
    required this.label,
  });

  final int keyCode;
  final int modifiers;
  final String label;

  factory ShortcutBinding.fromNative(Object? value) {
    if (value is! Map ||
        value['keyCode'] is! int ||
        value['modifiers'] is! int ||
        value['label'] is! String) {
      throw const FormatException('Invalid keyboard shortcut.');
    }
    final keyCode = value['keyCode'] as int;
    final modifiers = value['modifiers'] as int;
    final label = value['label'] as String;
    if (keyCode < 0 ||
        keyCode > 127 ||
        modifiers < 1 ||
        modifiers > 15 ||
        (modifiers & 9) == 0 ||
        label.trim().isEmpty) {
      throw const FormatException('Invalid keyboard shortcut.');
    }
    return ShortcutBinding(
      keyCode: keyCode,
      modifiers: modifiers,
      label: label,
    );
  }

  Map<String, Object> toNative() => {
    'keyCode': keyCode,
    'modifiers': modifiers,
    'label': label,
  };
}

class ShortcutConfiguration {
  ShortcutConfiguration({required this.global, required this.bindings});

  final bool global;
  final Map<StintShortcutAction, ShortcutBinding?> bindings;

  factory ShortcutConfiguration.fromNative(Object? value) {
    if (value is! Map ||
        value['global'] is! bool ||
        value['bindings'] is! Map) {
      throw const FormatException('Invalid keyboard shortcut settings.');
    }
    final entries = value['bindings'] as Map;
    if (entries.length != StintShortcutAction.values.length ||
        StintShortcutAction.values.any(
          (action) => !entries.containsKey(action.name),
        )) {
      throw const FormatException('Missing keyboard shortcut actions.');
    }
    return ShortcutConfiguration(
      global: value['global'] as bool,
      bindings: Map.unmodifiable({
        for (final action in StintShortcutAction.values)
          action: entries[action.name] == null
              ? null
              : ShortcutBinding.fromNative(entries[action.name]),
      }),
    );
  }

  Map<String, Object> toNative() => {
    'global': global,
    'bindings': {
      for (final action in StintShortcutAction.values)
        action.name: bindings[action]?.toNative(),
    },
  };
}

class ShortcutSettings {
  const ShortcutSettings({
    required this.configuration,
    required this.defaults,
    this.error,
  });

  final ShortcutConfiguration configuration;
  final ShortcutConfiguration defaults;
  final String? error;

  factory ShortcutSettings.fromNative(Object? value) {
    if (value is! Map ||
        (value['error'] != null && value['error'] is! String)) {
      throw const FormatException('Invalid keyboard shortcut settings.');
    }
    return ShortcutSettings(
      configuration: ShortcutConfiguration.fromNative(value),
      defaults: ShortcutConfiguration.fromNative(value['defaults']),
      error: value['error'] as String?,
    );
  }
}

/// Shares the timer channel without replacing its event handler.
class StintKeymap {
  const StintKeymap({this.channel = const MethodChannel('focus_desk/timer')});

  final MethodChannel channel;

  Future<ShortcutSettings> load() async => ShortcutSettings.fromNative(
    await channel.invokeMethod<Object?>('getShortcutSettings'),
  );

  Future<ShortcutSettings> save(ShortcutConfiguration configuration) async =>
      ShortcutSettings.fromNative(
        await channel.invokeMethod<Object?>(
          'setShortcutSettings',
          configuration.toNative(),
        ),
      );

  Future<ShortcutBinding?> record() async {
    final value = await channel.invokeMethod<Object?>('recordShortcut');
    return value == null ? null : ShortcutBinding.fromNative(value);
  }

  Future<void> cancelRecording() =>
      channel.invokeMethod<void>('cancelShortcutRecording');
}
