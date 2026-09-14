import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showLanguageSelector(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final languages = ['English', 'Español', 'Français', 'Deutsch', 'Português', 'العربية', 'हिन्दी'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: languages.map((lang) {
              return ListTile(
                title: Text(lang, style: const TextStyle(color: AppColors.textDark)),
                trailing: appState.language == lang ? const Icon(LucideIcons.check, color: AppColors.primaryRed) : null,
                onTap: () {
                  appState.setLanguage(lang);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showEmergencyNumberEditor(BuildContext context, AppState appState) {
    final controller =
        TextEditingController(text: appState.emergencyNumber);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isArabic = appState.isArabic;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'رقم الطوارئ' : 'Emergency number',
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isArabic
                    ? 'يُستخدم في زر الاتصال بالطوارئ في الشاشة الرئيسية'
                    : 'Used by the Home SOS dial button',
                style: TextStyle(
                  color: AppColors.textDark.withOpacity(0.55),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9+*#]'))],
                decoration: const InputDecoration(
                  hintText: '112',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    appState.setEmergencyNumber(controller.text);
                    Navigator.pop(context);
                  },
                  child: Text(isArabic ? 'حفظ' : 'Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final isArabic = appState.isArabic;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textDark),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isArabic ? 'الإعدادات' : 'Settings',
            style: const TextStyle(color: AppColors.textDark),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(LucideIcons.globe, color: AppColors.primaryRed),
              title: Text(isArabic ? 'اللغة' : 'Language'),
              subtitle: Text(appState.language),
              trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textDark),
              onTap: () => _showLanguageSelector(context, appState),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.bell, color: AppColors.primaryRed),
              title: Text(isArabic ? 'الإشعارات' : 'Notifications'),
              trailing: Switch(
                value: appState.notificationsEnabled,
                onChanged: (val) {
                  appState.setNotificationsEnabled(val);
                },
                activeColor: AppColors.primaryRed,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.phone,
                  color: AppColors.primaryRed),
              title: Text(isArabic ? 'رقم الطوارئ' : 'Emergency number'),
              subtitle: Text(appState.emergencyNumber),
              trailing: const Icon(LucideIcons.chevronRight,
                  color: AppColors.textDark),
              onTap: () => _showEmergencyNumberEditor(context, appState),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.info, color: AppColors.primaryRed),
              title: Text(isArabic ? 'حول التطبيق' : 'About'),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Rescate',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© 2026 Rescate',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

