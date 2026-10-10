import 'package:flutter/services.dart';

class NativeFiles {
  static const channel = MethodChannel('stint/files');
  static Future<String> dataDirectory() async =>
      (await channel.invokeMethod<String>('dataDirectory'))!;
}
