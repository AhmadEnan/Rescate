import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_llama_method_channel.dart';

abstract class FlutterLlamaPlatform extends PlatformInterface {
  /// Constructs a FlutterLlamaPlatform.
  FlutterLlamaPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterLlamaPlatform _instance = MethodChannelFlutterLlama();

  /// The default instance of [FlutterLlamaPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterLlama].
  static FlutterLlamaPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterLlamaPlatform] when
  /// they register themselves.
  static set instance(FlutterLlamaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
