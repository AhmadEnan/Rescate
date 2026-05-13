class AmbientLightSource {
  AmbientLightSource() : _lux = null;

  AmbientLightSource.forTesting(Stream<double> lux) : _lux = lux;

  final Stream<double>? _lux;

  Stream<double> lux() {
    final Stream<double>? injected = _lux;
    if (injected != null) {
      return injected;
    }
    return Stream<double>.error(
      UnsupportedError(
        'Ambient light capture is not supported on this platform.',
      ),
    );
  }
}
