// apps/rescate_app/lib/features/ai_chat/screens/model_setup_screen.dart

import 'dart:io';

import 'package:ai_inference/ai_inference.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../state/model_store.dart';

const String _kPrefsModelPathKey = 'ai_chat.model_path';

class ModelSetupScreen extends StatefulWidget {
  const ModelSetupScreen({super.key});

  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen> {
  ImportedModel? _importedModel;
  List<ImportedModel> _storedModels = const [];
  String? _migratablePath;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isImporting = false;
  double? _importProgress;
  bool _safeMode = false;
  LoadAttempt? _previousAttempt;
  String? _logFilePath;

  LlmStatus get _status => LlmService.instance.status;

  @override
  void initState() {
    super.initState();
    LlmService.instance.addListener(_onServiceChanged);
    _loadStoredState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    final previous = await LlmLoadDiagnostics.readAttempt();
    final logPath = await LlmLoadDiagnostics.logFilePath();
    if (!mounted) return;
    setState(() {
      _previousAttempt = previous;
      _logFilePath = logPath;
    });
  }

  @override
  void dispose() {
    LlmService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  /// Auto-detects valid sandboxed models at startup and restores the last
  /// used one. A previously-picked external path (pre-#9 flow) is offered
  /// for migration instead of being used in place.
  Future<void> _loadStoredState() async {
    final prefs = await SharedPreferences.getInstance();
    final models = await ModelStore.instance.detectModels();
    final saved = prefs.getString(_kPrefsModelPathKey);

    ImportedModel? selected;
    for (final model in models) {
      if (model.path == saved) selected = model;
    }

    String? migratable;
    if (selected == null && saved != null && saved.isNotEmpty) {
      // Legacy path from the old Downloads-browser flow. Offer migration
      // while the file still exists; otherwise it is simply stale.
      if (File(saved).existsSync() && !saved.startsWith(_sandboxRoot(models))) {
        migratable = saved;
      }
    }

    if (!mounted) return;
    setState(() {
      _storedModels = models;
      _importedModel = selected;
      _migratablePath = migratable;
    });
  }

  String _sandboxRoot(List<ImportedModel> models) {
    if (models.isEmpty) return '/data/';
    // Any stored model lives under `<support>/models/`; derive the root.
    final sample = models.first.path;
    final idx = sample.lastIndexOf('/models/');
    return idx < 0 ? '/data/' : sample.substring(0, idx);
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (_status == LlmStatus.ready && _isLoading) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop();
    }
  }

  /// Opens the system file picker (SAF — no storage permission involved) and
  /// imports the picked file into the sandbox with streaming copy + hashing.
  Future<void> _pickAndImportModel() async {
    setState(() {
      _errorMessage = null;
      _isImporting = true;
      _importProgress = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        // compression must stay off: the bytes are hashed during import and
        // must match the original file.
        compressionQuality: 0,
        dialogTitle: 'Select a .gguf model',
      );
      final pickedPath = result?.files.single.path;
      final pickedName = result?.files.single.name;
      if (pickedPath == null) {
        // User cancelled the picker.
        return;
      }

      final model = await ModelStore.instance.importFromTemp(
        pickedPath,
        originalName: pickedName,
        onProgress: (copied, total) {
          if (!mounted) return true;
          setState(() => _importProgress = copied / total);
          return true;
        },
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsModelPathKey, model.path);

      final models = await ModelStore.instance.detectModels();
      if (!mounted) return;
      setState(() {
        _importedModel = model;
        _storedModels = models;
        _migratablePath = null;
        _errorMessage = null;
      });
    } on ModelImportException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.message != 'cancelled') _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Import failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importProgress = null;
        });
      }
    }
  }

  /// Issue #9 migration: copy a previously-picked external model into the
  /// sandbox. The original file is left untouched.
  Future<void> _migrateExternalModel() async {
    final path = _migratablePath;
    if (path == null) return;
    setState(() {
      _errorMessage = null;
      _isImporting = true;
      _importProgress = null;
    });
    try {
      final model = await ModelStore.instance.importFromPath(
        path,
        onProgress: (copied, total) {
          if (!mounted) return true;
          setState(() => _importProgress = copied / total);
          return true;
        },
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsModelPathKey, model.path);
      final models = await ModelStore.instance.detectModels();
      if (!mounted) return;
      setState(() {
        _importedModel = model;
        _storedModels = models;
        _migratablePath = null;
      });
    } on ModelImportException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Migration failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importProgress = null;
        });
      }
    }
  }

  Future<void> _removeModel(ImportedModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await ModelStore.instance.deleteModel(model.path);
    if (prefs.getString(_kPrefsModelPathKey) == model.path) {
      await prefs.remove(_kPrefsModelPathKey);
    }
    final models = await ModelStore.instance.detectModels();
    if (!mounted) return;
    setState(() {
      _storedModels = models;
      if (_importedModel?.path == model.path) _importedModel = null;
    });
  }

  Future<void> _loadModel() async {
    final model = _importedModel;
    if (model == null) return;
    final path = model.path;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Safe mode forces the loader to start at the CPU-only rung by
      // pre-writing a sticky marker just past the GPU rungs. The loader
      // reads this on entry and skips ahead.
      if (_safeMode) {
        await LlmLoadDiagnostics.writeAttempt(LoadAttempt(
          rung: safeModeRungIndex - 1,
          modelPath: path,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          note: 'user-selected safe mode',
        ));
      } else if (_previousAttempt != null &&
          _previousAttempt!.modelPath != path) {
        // Picking a different model voids the marker — different file,
        // different memory profile.
        await LlmLoadDiagnostics.clearAttempt();
      }

      await LlmService.instance.loadModel(path);
      // _onServiceChanged pops on success.
    } on LlmException catch (e) {
      if (!mounted) return;
      final refreshed = await LlmLoadDiagnostics.readAttempt();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
        _previousAttempt = refreshed;
      });
    } catch (e) {
      if (!mounted) return;
      final refreshed = await LlmLoadDiagnostics.readAttempt();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
        _previousAttempt = refreshed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasModel = _importedModel != null;
    final canLoad = hasModel && !_isLoading && !_isImporting;

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
                      icon: LucideIcons.shieldCheck,
                      title: 'Stored safely in-app',
                      body:
                          'Pick a .gguf file once — it is copied into Rescate\'s '
                          'private storage, verified, and checked against your '
                          'free space. No storage permission is ever requested, '
                          'and the model stays available offline.',
                    ),
                    const SizedBox(height: 20),
                    _buildModelCard(hasModel),
                    if (_isImporting) ...[
                      const SizedBox(height: 16),
                      _buildImportProgress(),
                    ],
                    if (_migratablePath != null) ...[
                      const SizedBox(height: 16),
                      _buildMigrationCard(),
                    ],
                    if (_storedModels.length > 1) ...[
                      const SizedBox(height: 16),
                      _buildStoredModelsList(),
                    ],
                    const SizedBox(height: 16),
                    if (_previousAttempt != null) _buildPreviousAttemptBanner(),
                    _buildSafeModeToggle(),
                    if (_logFilePath != null) _buildLogPathRow(),
                    const SizedBox(height: 8),
                    const _RecommendedModelsCard(),
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

  Widget _buildModelCard(bool hasModel) {
    return GestureDetector(
      onTap: _isLoading || _isImporting ? null : _pickAndImportModel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: hasModel
              ? AppColors.aiAccentPink.withOpacity(0.2)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasModel
                ? AppColors.primaryRed
                : AppColors.cardBackgroundLight,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasModel ? LucideIcons.fileCheck : LucideIcons.folderOpen,
              color: hasModel
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
                    hasModel
                        ? _importedModel!.fileName
                        : 'Tap to pick a .gguf model file',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight:
                          hasModel ? FontWeight.w600 : FontWeight.w400,
                      color: hasModel
                          ? AppColors.textDark
                          : AppColors.textDark.withOpacity(0.45),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasModel)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${(_importedModel!.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB · '
                        'stored in app storage',
                        style: GoogleFonts.robotoMono(
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
            if (hasModel)
              IconButton(
                tooltip: 'Pick a different model',
                onPressed: _isLoading || _isImporting
                    ? null
                    : _pickAndImportModel,
                icon: const Icon(
                  LucideIcons.refreshCw,
                  size: 18,
                  color: AppColors.primaryRed,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportProgress() {
    final progress = _importProgress ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress <= 0 ? null : progress,
            minHeight: 6,
            backgroundColor: AppColors.cardBackgroundLight,
            color: AppColors.primaryRed,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          progress > 0
              ? 'Importing and verifying model… ${(progress * 100).toStringAsFixed(0)}%'
              : 'Importing and verifying model…',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppColors.textDark.withOpacity(0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildMigrationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF9DB4E8), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.arrowDownToLine,
              color: Color(0xFF3A5BC7), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move your previous model into app storage',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2A4390),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The model picked before this update still lives in shared '
                  'storage ($_migratablePath). Copy it into Rescate\'s private '
                  'storage so it works without any storage permission. The '
                  'original file is not deleted.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF2A4390),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF3A5BC7),
                  ),
                  onPressed: _isImporting ? null : _migrateExternalModel,
                  child: const Text('Copy into app storage'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoredModelsList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stored models',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          ..._storedModels.map((model) {
            final isSelected = model.path == _importedModel?.path;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                isSelected
                    ? LucideIcons.fileCheck
                    : LucideIcons.file,
                size: 18,
                color:
                    isSelected ? AppColors.primaryRed : AppColors.textDark,
              ),
              title: Text(
                model.fileName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isSelected)
                    TextButton(
                      onPressed:
                          _isLoading || _isImporting
                              ? null
                              : () => setState(() {
                                    _importedModel = model;
                                  }),
                      child: const Text('Use'),
                    ),
                  IconButton(
                    tooltip: 'Delete stored model',
                    icon: Icon(
                      LucideIcons.trash2,
                      size: 16,
                      color: AppColors.textDark.withOpacity(0.45),
                    ),
                    onPressed:
                        _isLoading || _isImporting
                            ? null
                            : () => _removeModel(model),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPreviousAttemptBanner() {
    final attempt = _previousAttempt!;
    final bool exhausted = attempt.nextRungAfterCrash >= 5;
    final String body = exhausted
        ? 'The model exceeded what this device can load even at the safest '
            'configuration. Try a smaller quantisation.'
        : 'The previous load attempt for this model did not finish (rung '
            '${attempt.rung}). The next try will start from a safer '
            'configuration (rung ${attempt.nextRungAfterCrash}).';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0B900), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.alertTriangle,
              color: Color(0xFF9A7A00), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exhausted
                      ? 'Model exceeds this device'
                      : 'Last load attempt did not finish',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF7A5C00),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF7A5C00),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF7A5C00),
                  ),
                  onPressed: () async {
                    await LlmLoadDiagnostics.clearAttempt();
                    if (!mounted) return;
                    setState(() => _previousAttempt = null);
                  },
                  child: const Text('Reset and try again from rung 0'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeModeToggle() {
    return InkWell(
      onTap: _isLoading ? null : () => setState(() => _safeMode = !_safeMode),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: _safeMode,
              onChanged: _isLoading
                  ? null
                  : (v) => setState(() => _safeMode = v ?? false),
              activeColor: AppColors.primaryRed,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safe mode (CPU only)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    'Skip GPU offload. Slower but avoids Vulkan-driver crashes '
                    'on some Android devices.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textDark.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPathRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.fileText,
              size: 14, color: AppColors.textDark.withOpacity(0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Diagnostic log: $_logFilePath',
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                color: AppColors.textDark.withOpacity(0.5),
              ),
            ),
          ),
        ],
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
}

// ── Info card ─────────────────────────────────────────────────────────────────

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
  const _RecommendedModelsCard();

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
          'Download the .gguf on your phone, then tap above and pick it — '
          'it will be copied into Rescate\'s private storage.',
    );
  }
}
