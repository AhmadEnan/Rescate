import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  String _language = 'English';
  bool _notificationsEnabled = true;

  String get language => _language;
  bool get notificationsEnabled => _notificationsEnabled;

  AppState() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('language') ?? 'English';
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    notifyListeners();
  }

  void setLanguage(String lang) async {
    if (_language != lang) {
      _language = lang;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', lang);
    }
  }

  void setNotificationsEnabled(bool val) async {
    if (_notificationsEnabled != val) {
      _notificationsEnabled = val;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notificationsEnabled', val);
    }
  }

  bool get isArabic => _language == 'العربية';
  bool get isFrench => _language == 'Français';
  bool get isSpanish => _language == 'Español';
}

class AppStateProvider extends InheritedNotifier<AppState> {
  const AppStateProvider({
    super.key,
    required AppState notifier,
    required super.child,
  }) : super(notifier: notifier);

  static AppState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppStateProvider>()!.notifier!;
  }
}
