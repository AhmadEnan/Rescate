// Main App Entry Point
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/home/screens/main_screen.dart';
import 'core/providers/app_state.dart';
import 'package:p2p_mesh/p2p_mesh.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool isFirstLaunch = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;
  } catch (e) {
    print('Error loading SharedPreferences: $e');
  }

  final meshProvider = MeshProvider();
  await meshProvider.init();

  runApp(
    AppStateProvider(
      notifier: AppState(),
      child: ListenableBuilder(
        listenable: meshProvider,
        builder: (context, child) {
          return MeshInheritedProvider(
            notifier: meshProvider,
            child: RescateApp(showOnboarding: isFirstLaunch),
          );
        },
      ),
    ),
  );
}

class MeshInheritedProvider extends InheritedNotifier<MeshProvider> {
  const MeshInheritedProvider({
    super.key,
    required MeshProvider notifier,
    required super.child,
  }) : super(notifier: notifier);

  static MeshProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MeshInheritedProvider>()!.notifier!;
  }
}

class RescateApp extends StatelessWidget {
  final bool showOnboarding;
  const RescateApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rescate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: showOnboarding ? const OnboardingScreen() : MainScreen(key: mainScreenKey),
    );
  }
}
