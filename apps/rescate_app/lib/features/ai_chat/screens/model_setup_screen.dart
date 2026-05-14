// apps/rescate_app/lib/features/ai_chat/screens/model_setup_screen.dart

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ai_inference/ai_inference.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

/// Screen shown when no GGUF model is loaded.
///
/// Supports two loading modes:
/// 1. **Type path directly** — fastest, no file copy. User types the full
///    filesystem path to the .gguf file (e.g. /sdcard/Download/model.gguf).
/// 2. **Browse with file picker** — convenient, but Android's Storage Access
///    Framework may cache the file to a temp dir for large files.
class ModelSetupScreen extends StatefulWidget {
  const ModelSetupScreen({super.key});

  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pathController = TextEditingController();
  String? _pickedPath;        // set by file browser
  String? _errorMessage;
  bool _isLoading = false;
  late final TabController _tabController;

  LlmStatus get _status => LlmService.instance.status;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    LlmService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    LlmService.instance.removeListener(_onServiceChanged);
    _pathController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (_status == LlmStatus.ready && _isLoading) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop();
    }
  }

  // ── Effective path: prefer manual entry over picker ──────────────────────────

  String? get _effectivePath {
    final typed = _pathController.text.trim();
    if (typed.isNotEmpty) return typed;
    return _pickedPath;
  }

  // ── Browse via file picker ────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      // Do NOT set withData:true — avoids reading bytes into memory.
      // allowCompression:false tells the picker not to try to compress the file.
      allowCompression: false,
      dialogTitle: 'Select a GGUF model file',
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) {
      setState(() => _errorMessage =
          'Could not resolve a filesystem path from the picker.\n'
          'Use the "Type Path" tab and enter the path manually instead.');
      return;
    }

    if (!path.toLowerCase().endsWith('.gguf')) {
      setState(() => _errorMessage = 'Please select a .gguf file.');
      return;
    }

    setState(() {
      _pickedPath = path;
      _pathController.clear(); // clear manual entry if any
    });
  }

  // ── Load ─────────────────────────────────────────────────────────────────────

  Future<void> _loadModel() async {
    final path = _effectivePath;
    if (path == null || path.isEmpty) return;

    if (!path.toLowerCase().endsWith('.gguf')) {
      setState(() => _errorMessage = 'Path must end with .gguf');
      return;
    }

    // On Android 11+, we need MANAGE_EXTERNAL_STORAGE to read files outside our app dir via POSIX
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isDenied ||
          await Permission.manageExternalStorage.isPermanentlyDenied) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          setState(() => _errorMessage =
              'Storage permission denied.\n\n'
              'Rescate requires "All Files Access" to read the GGUF model directly from storage without copying it. '
              'Please grant this permission in Android Settings.');
          return;
        }
      }
    }

    if (!File(path).existsSync()) {
      setState(() => _errorMessage =
          'File not found:\n$path\n\nCheck that the path is correct and storage permission has been granted.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await LlmService.instance.loadModel(path);
      // _onServiceChanged pops on success.
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppColors.primaryRed),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Load AI Model',
          style: GoogleFonts.inter(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryRed,
          unselectedLabelColor: AppColors.textDark.withOpacity(0.45),
          indicatorColor: AppColors.primaryRed,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(LucideIcons.keyboard, size: 16), text: 'Type Path'),
            Tab(icon: Icon(LucideIcons.folderOpen, size: 16), text: 'Browse'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTypePathTab(),
                  _buildBrowseTab(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Type path directly (no copy) ──────────────────────────────────────

  Widget _buildTypePathTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCard(
            icon: LucideIcons.zap,
            title: 'Load in-place — no copy',
            body: 'Enter the full path to your .gguf file.\n'
                'The model is loaded directly from disk — '
                'nothing is copied or moved.\n\n'
                'Typical locations on Android:\n'
                '  /storage/emulated/0/Download/model.gguf\n'
                '  /sdcard/Download/model.gguf',
          ),
          const SizedBox(height: 20),
          Text(
            'Model file path',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pathController,
            enabled: !_isLoading,
            onChanged: (_) => setState(() {
              _pickedPath = null;
              _errorMessage = null;
            }),
            onSubmitted: (_) => _loadModel(),
            style: GoogleFonts.robotoMono(
              fontSize: 13,
              color: AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: '/storage/emulated/0/Download/model.gguf',
              hintStyle: GoogleFonts.robotoMono(
                fontSize: 12,
                color: AppColors.textDark.withOpacity(0.3),
              ),
              filled: true,
              fillColor: AppColors.cardBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.cardBackgroundLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryRed, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: _pathController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () => setState(() {
                        _pathController.clear();
                        _errorMessage = null;
                      }),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          _RecommendedModelsCard(),
        ],
      ),
    );
  }

  // ── Tab 2: Browse with file picker ───────────────────────────────────────────

  Widget _buildBrowseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCard(
            icon: LucideIcons.alertTriangle,
            title: 'Note: may copy large files',
            body: 'Android\'s file picker uses the Storage Access Framework '
                'which can copy large GGUF files to a temp cache.\n\n'
                'For models over 500 MB, use the "Type Path" tab instead '
                'to load in-place.',
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _isLoading ? null : _pickFile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              decoration: BoxDecoration(
                color: _pickedPath != null
                    ? AppColors.aiAccentPink.withOpacity(0.2)
                    : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pickedPath != null
                      ? AppColors.primaryRed
                      : AppColors.cardBackgroundLight,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _pickedPath != null ? LucideIcons.fileCheck : LucideIcons.folderOpen,
                    color: _pickedPath != null
                        ? AppColors.primaryRed
                        : AppColors.textDark.withOpacity(0.4),
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pickedPath != null
                              ? _basename(_pickedPath!)
                              : 'Tap to browse for a .gguf file',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: _pickedPath != null ? FontWeight.w600 : FontWeight.w400,
                            color: _pickedPath != null
                                ? AppColors.textDark
                                : AppColors.textDark.withOpacity(0.45),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_pickedPath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _pickedPath!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textDark.withOpacity(0.4),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_pickedPath != null)
                    GestureDetector(
                      onTap: _isLoading ? null : () => setState(() => _pickedPath = null),
                      child: const Icon(LucideIcons.x, size: 18, color: AppColors.primaryRed),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared bottom bar (error + load button) ───────────────────────────────────

  Widget _buildBottomBar() {
    final canLoad = _effectivePath != null && _effectivePath!.isNotEmpty && !_isLoading;

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEAEA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.alertCircle, color: AppColors.primaryRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.primaryRed),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: canLoad ? _loadModel : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                disabledBackgroundColor: AppColors.primaryRed.withOpacity(0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      'Load Model',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Loading model into memory… this may take a few seconds.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textDark.withOpacity(0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _basename(String path) {
    final sep = path.lastIndexOf(RegExp(r'[/\\]'));
    return sep < 0 ? path : path.substring(sep + 1);
  }
}

// ── Info card ──────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primaryRed),
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            ],
          ),
          const SizedBox(height: 10),
          Text(body,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textDark.withOpacity(0.65), height: 1.5)),
        ],
      ),
    );
  }
}

// ── Recommended models card ────────────────────────────────────────────────────

class _RecommendedModelsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      icon: LucideIcons.sparkles,
      title: 'Recommended Models',
      body: 'Any instruction-tuned GGUF works. Smaller quantisations '
          '(Q4_K_M, ~700 MB) run on most phones.\n\n'
          '• Gemma 3 1B  — medical-friendly, fast\n'
          '• Llama 3.2 1B  — English / Arabic\n'
          '• Mistral 7B Q4_K_M  — higher quality\n\n'
          'Download from Hugging Face, copy to /sdcard/Download/, '
          'then paste the path above.',
    );
  }
}
