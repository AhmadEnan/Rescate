import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_llama_platform_interface.dart';

/// An implementation of [FlutterLlamaPlatform] that uses method channels.
class MethodChannelFlutterLlama extends FlutterLlamaPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_llama');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
