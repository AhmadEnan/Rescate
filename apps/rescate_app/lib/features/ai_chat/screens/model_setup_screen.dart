// apps/rescate_app/lib/features/ai_chat/screens/model_setup_screen.dart

import 'dart:io';

import 'package:ai_inference/ai_inference.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';

const String _kPrefsModelPathKey = 'ai_chat.model_path';
const String _kPrefsBrowserDirKey = 'ai_chat.browser_last_dir';

class ModelSetupScreen extends StatefulWidget {
  const ModelSetupScreen({super.key});

  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen> {
  String? _pickedPath;
  String? _errorMessage;
  bool _isLoading = false;
  bool _useGpu = LlmDefaults.useGpu;

  LlmStatus get _status => LlmService.instance.status;

  @override
  void initState() {
    super.initState();
    LlmService.instance.addListener(_onServiceChanged);
    _restoreLastPath();
    _restoreGpuSetting();
  }

  @override
  void dispose() {
    LlmService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _restoreGpuSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _useGpu = prefs.getBool('ai_chat.use_gpu') ?? LlmDefaults.useGpu;
    });
  }

  Future<void> _restoreLastPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefsModelPathKey);
    if (saved == null || saved.isEmpty) return;
    if (!File(saved).existsSync()) return;
    if (!mounted) return;
    setState(() => _pickedPath = saved);
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (_status == LlmStatus.ready && _isLoading) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop();
    }
  }

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    setState(() => _errorMessage =
        'Storage permission denied.\n\n'
        'Rescate needs "All Files Access" to read the GGUF model in place. '
        'Please grant it in Android Settings.');
    return false;
  }

  Future<void> _openBrowser() async {
    setState(() => _errorMessage = null);
    if (!await _ensureStoragePermission()) return;

    final prefs = await SharedPreferences.getInstance();
    final startDir = prefs.getString(_kPrefsBrowserDirKey) ??
        '/storage/emulated/0/Download';

    if (!mounted) return;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _GgufBrowserScreen(initialDirectory: startDir),
      ),
    );
    if (picked == null) return;

    await prefs.setString(_kPrefsBrowserDirKey, File(picked).parent.path);
    if (!mounted) return;
    setState(() {
      _pickedPath = picked;
      _errorMessage = null;
    });
  }

  Future<void> _loadModel() async {
    final path = _pickedPath;
    if (path == null || path.isEmpty) return;

    if (!path.toLowerCase().endsWith('.gguf')) {
      setState(() => _errorMessage = 'Selected file must end with .gguf');
      return;
    }

    if (!await _ensureStoragePermission()) return;

    if (!File(path).existsSync()) {
      setState(() => _errorMessage =
          'File not found:\n$path\n\nPick a new model.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await LlmService.instance.loadModel(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsModelPathKey, path);
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

  @override
  Widget build(BuildContext context) {
    final hasPath = _pickedPath != null && _pickedPath!.isNotEmpty;
    final canLoad = hasPath && !_isLoading;

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
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _InfoCard(
                      icon: LucideIcons.zap,
                      title: 'Load in-place — no copy',
                      body:
                          'Browse and pick your .gguf file. The model is read '
                          'directly from disk; nothing is copied.\n\n'
                          'Your last choice is remembered, so you only need to '
                          'browse again to switch models.',
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _isLoading ? null : _openBrowser,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 22),
                        decoration: BoxDecoration(
                          color: hasPath
                              ? AppColors.aiAccentPink.withOpacity(0.2)
                              : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasPath
                                ? AppColors.primaryRed
                                : AppColors.cardBackgroundLight,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasPath
                                  ? LucideIcons.fileCheck
                                  : LucideIcons.folderOpen,
                              color: hasPath
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
                                    hasPath
                                        ? _basename(_pickedPath!)
                                        : 'Tap to browse for a .gguf file',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: hasPath
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: hasPath
                                          ? AppColors.textDark
                                          : AppColors.textDark.withOpacity(0.45),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (hasPath)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _pickedPath!,
                                        style: GoogleFonts.robotoMono(
                                          fontSize: 11,
                                          color: AppColors.textDark
                                              .withOpacity(0.4),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (hasPath)
                              IconButton(
                                tooltip: 'Pick a different model',
                                onPressed: _isLoading ? null : _openBrowser,
                                icon: const Icon(
                                  LucideIcons.refreshCw,
                                  size: 18,
                                  color: AppColors.primaryRed,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // GPU Acceleration Toggle Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.cardBackgroundLight,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.zap,
                            color: AppColors.primaryRed,
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GPU Acceleration (Vulkan)',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Disable if model fails to load or the app crashes.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textDark.withOpacity(0.5),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: _useGpu,
                            activeColor: AppColors.primaryRed,
                            onChanged: _isLoading
                                ? null
                                : (val) async {
                                    setState(() => _useGpu = val);
                                    LlmDefaults.useGpu = val;
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool('ai_chat.use_gpu', val);
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _RecommendedModelsCard(),
                  ],
                ),
              ),
            ),
            _buildBottomBar(canLoad),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool canLoad) {
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
                  const Icon(LucideIcons.alertCircle,
                      color: AppColors.primaryRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.primaryRed),
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
                disabledBackgroundColor:
                    AppColors.primaryRed.withOpacity(0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
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

// ── Custom GGUF file browser ─────────────────────────────────────────────────
//
// Returns the real POSIX path of the selected .gguf file. Uses dart:io
// directory listing — requires MANAGE_EXTERNAL_STORAGE permission on Android.

class _GgufBrowserScreen extends StatefulWidget {
  const _GgufBrowserScreen({required this.initialDirectory});
  final String initialDirectory;

  @override
  State<_GgufBrowserScreen> createState() => _GgufBrowserScreenState();
}

class _GgufBrowserScreenState extends State<_GgufBrowserScreen> {
  late Directory _currentDir;
  List<FileSystemEntity> _entries = const [];
  String? _error;
  bool _loading = true;

  static const String _androidRoot = '/storage/emulated/0';

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(widget.initialDirectory);
    if (!_currentDir.existsSync()) {
      _currentDir = Directory(_androidRoot);
    }
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _currentDir.list(followLinks: false).toList();
      final filtered = all.where((e) {
        final name = _basename(e.path);
        if (name.startsWith('.')) return false;
        if (e is Directory) return true;
        if (e is File) return name.toLowerCase().endsWith('.gguf');
        return false;
      }).toList()
        ..sort((a, b) {
          final aDir = a is Directory;
          final bDir = b is Directory;
          if (aDir != bDir) return aDir ? -1 : 1;
          return _basename(a.path)
              .toLowerCase()
              .compareTo(_basename(b.path).toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _entries = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = 'Cannot read this folder:\n$e';
        _loading = false;
      });
    }
  }

  void _enter(Directory dir) {
    _currentDir = dir;
    _refresh();
  }

  void _goUp() {
    final parent = _currentDir.parent;
    if (parent.path == _currentDir.path) return;
    _currentDir = parent;
    _refresh();
  }

  String _basename(String path) {
    final sep = path.lastIndexOf(RegExp(r'[/\\]'));
    return sep < 0 ? path : path.substring(sep + 1);
  }

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
          'Select GGUF model',
          style: GoogleFonts.inter(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Up one folder',
            icon: const Icon(LucideIcons.arrowUp, color: AppColors.primaryRed),
            onPressed: _goUp,
          ),
          IconButton(
            tooltip: 'Storage root',
            icon: const Icon(LucideIcons.home, color: AppColors.primaryRed),
            onPressed: () => _enter(Directory(_androidRoot)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.cardBackground,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _currentDir.path,
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  color: AppColors.textDark.withOpacity(0.7),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.primaryRed,
                            ),
                          ),
                        )
                      : _entries.isEmpty
                          ? Center(
                              child: Text(
                                'No folders or .gguf files here.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textDark.withOpacity(0.5),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _entries.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: AppColors.cardBackgroundLight,
                              ),
                              itemBuilder: (_, i) {
                                final entry = _entries[i];
                                final isDir = entry is Directory;
                                return ListTile(
                                  leading: Icon(
                                    isDir
                                        ? LucideIcons.folder
                                        : LucideIcons.fileText,
                                    color: isDir
                                        ? AppColors.primaryRed
                                        : AppColors.textDark.withOpacity(0.7),
                                  ),
                                  title: Text(
                                    _basename(entry.path),
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  subtitle: isDir
                                      ? null
                                      : Text(
                                          _formatBytes(
                                              (entry as File).lengthSync()),
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppColors.textDark
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                  onTap: () {
                                    if (isDir) {
                                      _enter(entry);
                                    } else {
                                      Navigator.of(context).pop(entry.path);
                                    }
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark)),
            ],
          ),
          const SizedBox(height: 10),
          Text(body,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textDark.withOpacity(0.65),
                  height: 1.5)),
        ],
      ),
    );
  }
}

// ── Recommended models card ────────────────────────────────────────────────────

class _RecommendedModelsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _InfoCard(
      icon: LucideIcons.sparkles,
      title: 'Recommended Models',
      body: 'Any instruction-tuned GGUF works. Smaller quantisations '
          '(Q4_K_M, ~700 MB) run on most phones.\n\n'
          '• Gemma 3 1B  — medical-friendly, fast\n'
          '• Llama 3.2 1B  — English / Arabic\n'
          '• Mistral 7B Q4_K_M  — higher quality\n\n'
          'Place the .gguf file anywhere in your storage (typically '
          '/storage/emulated/0/Download/), then tap Browse.',
    );
  }
}
