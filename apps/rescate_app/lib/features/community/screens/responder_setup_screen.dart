// Responder mode setup: create a badge request for the medical authority,
// import a signed badge, and see the verified identity. Also the entry
// point to the responder inbox.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:security_crypto/security_crypto.dart'
    show ResponderCredential;
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../services/consult_state.dart';
import 'responder_inbox_screen.dart';

class ResponderSetupScreen extends StatefulWidget {
  const ResponderSetupScreen({super.key});

  @override
  State<ResponderSetupScreen> createState() => _ResponderSetupScreenState();
}

class _ResponderSetupScreenState extends State<ResponderSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _requestPath;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createRequest() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _message = 'Enter your name first.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await ConsultState.instance
          .createBadgeRequest(displayName: name);
      setState(() {
        _requestPath = path;
        _message = 'Request saved to:\n$path\n\n'
            'Send it to the Rescate medical authority (share button below, '
            'WhatsApp/email/USB) to be signed.';
      });
    } catch (e) {
      setState(() => _message = 'Failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _importBadge() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select your signed badge file',
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final error = await ConsultState.instance.importBadge(path);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Verified: ${ConsultState.instance.credential!.name} — '
                'responder mode enabled'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.of(context).pop();
      } else {
        setState(() => _message = 'Badge rejected: $error');
      }
    } catch (e) {
      setState(() => _message = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableResponderMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave responder mode?'),
        content: const Text(
            'Your badge and keys will be removed from this device. You will '
            'need a newly signed badge to become a responder again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ConsultState.instance.disableResponderMode();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final consult = ConsultState.instance;
    final badge = consult.credential;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        title: Text(
          'Medical Responder',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (badge != null) ...[
            _BadgeCard(credential: badge),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(LucideIcons.inbox),
              label: const Text('Open consult inbox'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ResponderInboxScreen()),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(LucideIcons.logOut, size: 18),
              label: const Text('Leave responder mode'),
              onPressed: _busy ? null : _disableResponderMode,
            ),
          ] else ...[
            _SectionCard(
              title: '1. Create a badge request',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: AppColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'Your full name (as on your license)',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                    ),
                    onPressed: _busy ? null : _createRequest,
                    child: const Text('Generate request file'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: '2. Import your signed badge',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Once the medical authority has signed your request file, '
                    'copy the badge file to this device and import it.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                    ),
                    onPressed: _busy ? null : _importBadge,
                    child: const Text('Choose badge file…'),
                  ),
                ],
              ),
            ),
          ],
          if (_requestPath != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.share2, size: 16),
              label: const Text('Share request file…'),
              onPressed: _busy
                  ? null
                  : () => Share.shareXFiles(
                        [XFile(_requestPath!)],
                        text:
                            'Rescate responder badge request — please sign and '
                            'return a badge file.',
                      ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _message!,
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.credential});
  final ResponderCredential credential;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF34C759), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF34C759),
            ),
            child: const Icon(LucideIcons.shieldCheck,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credential.name,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Verified ${credential.role.title}'
                  '${credential.specialty.isEmpty ? '' : ' — ${credential.specialty}'}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'License ${credential.licenseRef.isEmpty ? '—' : credential.licenseRef}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textDark.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
