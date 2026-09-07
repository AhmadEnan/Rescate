// Consent preview shown before any patient data leaves the device. Shows
// exactly what will be sent; sending requires an explicit tap. Only
// reachable from a badge-verified session (the state layer refuses
// otherwise).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/case_payload.dart';

class CasePayloadSheetResult {
  const CasePayloadSheetResult(this.payload);
  final CasePayload payload;
}

/// [availableVitals] lines are pre-formatted "Heart rate: 88 bpm" strings.
Future<CasePayloadSheetResult?> showCasePayloadSheet(
  BuildContext context, {
  required String responderName,
  required List<String> availableVitals,
}) {
  return showModalBottomSheet<CasePayloadSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CasePayloadSheet(
      responderName: responderName,
      availableVitals: availableVitals,
    ),
  );
}

class _CasePayloadSheet extends StatefulWidget {
  const _CasePayloadSheet({
    required this.responderName,
    required this.availableVitals,
  });

  final String responderName;
  final List<String> availableVitals;

  @override
  State<_CasePayloadSheet> createState() => _CasePayloadSheetState();
}

class _CasePayloadSheetState extends State<_CasePayloadSheet> {
  final TextEditingController _noteController = TextEditingController();
  late final List<bool> _vitalSelected;
  bool _includeLocation = false;
  static const List<String> _symptomOptions = [
    'Unconscious',
    'Not breathing',
    'Heavy bleeding',
    'Burn',
    'Fracture',
    'Chest pain',
    'Difficulty breathing',
    'Poisoning',
    'Seizure',
    'Choking',
  ];
  final Set<String> _symptoms = {};

  @override
  void initState() {
    super.initState();
    _vitalSelected = List.filled(widget.availableVitals.length, true);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.shieldCheck,
                      color: Color(0xFF34C759), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Send consult to ${widget.responderName}',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'This is everything that will be sent — encrypted, only to '
                'this verified responder.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textDark.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 18),

              // ── Symptoms ─────────────────────────────────
              Text('SYMPTOMS',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark.withValues(alpha: 0.5))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _symptomOptions.map((s) {
                  final selected = _symptoms.contains(s);
                  return GestureDetector(
                    onTap: () => setState(() =>
                        selected ? _symptoms.remove(s) : _symptoms.add(s)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryRed
                            : AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        s,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // ── Note ─────────────────────────────────────
              TextField(
                controller: _noteController,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Describe the situation (optional)…',
                  filled: true,
                  fillColor: AppColors.cardBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Vitals ───────────────────────────────────
              if (widget.availableVitals.isNotEmpty) ...[
                Text('RECENT VITALS',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark.withValues(alpha: 0.5))),
                const SizedBox(height: 6),
                ...List.generate(widget.availableVitals.length, (i) {
                  return CheckboxListTile(
                    value: _vitalSelected[i],
                    onChanged: (v) =>
                        setState(() => _vitalSelected[i] = v ?? false),
                    title: Text(
                      widget.availableVitals[i],
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primaryRed,
                  );
                }),
                const SizedBox(height: 8),
              ],

              // ── Location ─────────────────────────────────
              SwitchListTile(
                value: _includeLocation,
                onChanged: (v) => setState(() => _includeLocation = v),
                title: Text(
                  'Include my location',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primaryRed,
              ),

              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _send,
                child: Text(
                  'Send consult request',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _send() {
    Navigator.of(context).pop(
      CasePayloadSheetResult(
        CasePayload(
          note: _noteController.text.trim(),
          symptoms: _symptoms.toList(),
          vitals: <String>[
            for (var i = 0; i < widget.availableVitals.length; i++)
              if (_vitalSelected[i]) widget.availableVitals[i],
          ],
          includeLocation: _includeLocation,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }
}
