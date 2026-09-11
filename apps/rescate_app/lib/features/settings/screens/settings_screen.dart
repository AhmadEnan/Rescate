import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../community/models/case_payload.dart' show ConsultRequestStatus;
import '../../community/screens/responder_setup_screen.dart';
import '../../community/services/consult_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _onConsultChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ConsultState.instance.addListener(_onConsultChanged);
  }

  @override
  void dispose() {
    ConsultState.instance.removeListener(_onConsultChanged);
    super.dispose();
  }


  Widget _responderSubtitle(bool isArabic) {
    final consult = ConsultState.instance;
    final badge = consult.credential;
    if (badge == null) {
      return Text(
        isArabic
            ? 'تحقق من هويتك لتلقي طلبات الاستشارة'
            : 'Verify your identity to receive consult requests',
        style: const TextStyle(fontSize: 12),
      );
    }
    final pending = consult.inbox
        .where((r) => r.status == ConsultRequestStatus.pending)
        .length;
    return Text(
      pending > 0
          ? '${badge.name} — $pending pending consult request(s)'
          : 'Verified — ${badge.name}',
      style: TextStyle(
        fontSize: 12,
        color: pending > 0 ? AppColors.primaryRed : Colors.green.shade700,
        fontWeight: FontWeight.w600,
      ),
    );
  }

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
                activeThumbColor: AppColors.primaryRed,
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                ConsultState.instance.isResponderMode
                    ? LucideIcons.shieldCheck
                    : LucideIcons.stethoscope,
                color: ConsultState.instance.isResponderMode
                    ? const Color(0xFF34C759)
                    : AppColors.primaryRed,
              ),
              title: Text(isArabic ? 'مقدم الرعاية الطبية' : 'Medical Responder'),
              subtitle: _responderSubtitle(isArabic),
              trailing: const Icon(LucideIcons.chevronRight,
                  color: AppColors.textDark),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const ResponderSetupScreen()),
                );
              },
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

