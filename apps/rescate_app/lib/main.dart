// Main App Entry Point
import 'package:flutter/material.dart';

void main() {
  runApp(const RescateApp());
}

class RescateApp extends StatelessWidget {
  const RescateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rescate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Rescate Application Initialized'),
        ),
      ),
    );
  }
}
