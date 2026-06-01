import 'package:flutter/services.dart';

class AlertSoundSettings {
  const AlertSoundSettings({required this.selectedSound, required this.sounds});
  final String selectedSound;
  final List<String> sounds;

  factory AlertSoundSettings.fromNative(Object? value) {
    if (value is! Map ||
        value['selectedSound'] is! String ||
        value['sounds'] is! List) {
      throw const FormatException('Invalid alert sound settings.');
    }
    final entries = value['sounds'] as List;
    if (entries.isEmpty ||
        entries.any((sound) => sound is! String || sound.trim().isEmpty)) {
      throw const FormatException('Invalid alert sound choices.');
    }
    final sounds = entries.cast<String>();
    final selected = value['selectedSound'] as String;
    if (sounds.toSet().length != sounds.length || !sounds.contains(selected)) {
      throw const FormatException('Invalid selected alert sound.');
    }
    return AlertSoundSettings(
      selectedSound: selected,
      sounds: List.unmodifiable(sounds),
    );
  }
}

/// Uses the timer channel without replacing its native-to-Dart event handler.
class AlertSounds {
  const AlertSounds({this.channel = const MethodChannel('focus_desk/timer')});
  final MethodChannel channel;

  Future<AlertSoundSettings> load() async => AlertSoundSettings.fromNative(
    await channel.invokeMethod<Object?>('getAlertSoundSettings'),
  );

  Future<AlertSoundSettings> save(String sound) async =>
      AlertSoundSettings.fromNative(
        await channel.invokeMethod<Object?>('setAlertSound', sound),
      );

  Future<Duration> preview(String sound) async {
    final result = await channel.invokeMethod<Object?>(
      'previewAlertSound',
      sound,
    );
    final milliseconds = result is Map ? result['durationMilliseconds'] : null;
    return Duration(
      milliseconds: milliseconds is num && milliseconds.isFinite
          ? milliseconds.round().clamp(250, 30000)
          : 4000,
    );
  }
}
