import 'package:flutter/services.dart';

class NativeFiles {
  static const channel = MethodChannel('focus_desk/files');
  static Future<String> dataDirectory() async =>
      (await channel.invokeMethod<String>('dataDirectory'))!;
}
