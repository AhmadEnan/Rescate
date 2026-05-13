// Main App Entry Point
import 'dart:async';
import 'dart:convert';

import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:offline_data/offline_data.dart';
import 'package:sensor_availability/sensor_availability.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_detectSensorsAtStartup());
  runApp(_BootstrapApp(measurementStore: MeasurementStore.open()));
}

Future<void> _detectSensorsAtStartup() async {
  try {
    await SensorAvailabilityService.instance.detectAll().timeout(
      const Duration(seconds: 6),
    );
  } on Object catch (e) {
    debugPrint('Startup sensor detection skipped: $e');
  }
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({required this.measurementStore});

  final Future<MeasurementStore> measurementStore;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MeasurementStore>(
      future: measurementStore,
      builder:
          (BuildContext context, AsyncSnapshot<MeasurementStore> snapshot) {
            final MeasurementStore? store = snapshot.data;
            if (store != null) {
              return RescateApp(measurementStore: store);
            }
            return MaterialApp(
              title: 'Rescate',
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
                useMaterial3: true,
              ),
              home: Scaffold(
                body: Center(
                  child: snapshot.hasError
                      ? Text('Startup failed: ${snapshot.error}')
                      : const CircularProgressIndicator(),
                ),
              ),
            );
          },
    );
  }
}

class RescateApp extends StatelessWidget {
  const RescateApp({required this.measurementStore, super.key});

  final MeasurementStore measurementStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rescate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      routes: <String, WidgetBuilder>{
        '/sensors': (BuildContext _) => const SensorAvailabilityScreen(),
        '/biometrics': (BuildContext context) => BiometricAvailabilityScreen(
          onTileTap: (BiometricId id) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => BiometricDetailScreen(
                  id: id,
                  measurementStore: measurementStore,
                ),
              ),
            );
          },
        ),
      },
      home: _HomeScreen(measurementStore: measurementStore),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.measurementStore});

  final MeasurementStore measurementStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Rescate Application Initialized'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/sensors'),
              icon: const Icon(Icons.sensors),
              label: const Text('View Device Sensors'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/biometrics'),
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('View Available Biometrics'),
            ),
            if (kDebugMode) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(_exportBundle(context)),
                icon: const Icon(Icons.data_object),
                label: const Text('Export bundle'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _exportBundle(BuildContext context) async {
    final List<Map<String, dynamic>> bundle = await measurementStore
        .exportLLMBundle();
    debugPrint(const JsonEncoder.withIndent('  ').convert(bundle));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${bundle.length} measurements to debug log.'),
      ),
    );
  }
}
