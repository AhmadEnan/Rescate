// Consent preview shown before any patient data leaves the device. Shows
// exactly what will be sent; sending requires an explicit tap. Only
// reachable from a badge-verified session (the state layer refuses
// otherwise).
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/case_payload.dart';

class CasePayloadSheetResult {
  const CasePayloadSheetResult(this.payload);
  final CasePayload payload;
}

/// Outcome of trying to read the patient's position after they consented.
/// [reason] is null on success and a UI-ready sentence otherwise.
class LocationReadResult {
  const LocationReadResult.success(this.latitude, this.longitude)
      : reason = null;
  const LocationReadResult.failure(this.reason)
      : latitude = null,
        longitude = null;

  final double? latitude;
  final double? longitude;
  final String? reason;

  bool get ok => latitude != null && longitude != null;
}

/// Injected in tests; on device this is [readDeviceLocation].
typedef LocationReader = Future<LocationReadResult> Function();

/// Requests permission and reads one position. Every failure path returns a
/// reason instead of throwing, because a consult must never be blocked by
/// location trouble — the payload just goes out without coordinates.
Future<LocationReadResult> readDeviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationReadResult.failure(
          'Location is turned off on this device.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationReadResult.failure('Location permission denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationReadResult.failure(
          'Location permission is permanently denied — enable it in Settings.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return LocationReadResult.success(position.latitude, position.longitude);
  } catch (e) {
    return const LocationReadResult.failure(
        'Could not get a location fix right now.');
  }
}

/// [availableVitals] lines are pre-formatted "Heart rate: 88 bpm" strings.
Future<CasePayloadSheetResult?> showCasePayloadSheet(
  BuildContext context, {
  required String responderName,
  required List<String> availableVitals,
  LocationReader locationReader = readDeviceLocation,
}) {
  return showModalBottomSheet<CasePayloadSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CasePayloadSheet(
      responderName: responderName,
      availableVitals: availableVitals,
      locationReader: locationReader,
    ),
  );
}

class _CasePayloadSheet extends StatefulWidget {
  const _CasePayloadSheet({
    required this.responderName,
    required this.availableVitals,
    required this.locationReader,
  });

  final String responderName;
  final List<String> availableVitals;
  final LocationReader locationReader;

  @override
  State<_CasePayloadSheet> createState() => _CasePayloadSheetState();
}

class _CasePayloadSheetState extends State<_CasePayloadSheet> {
  final TextEditingController _noteController = TextEditingController();
  late final List<bool> _vitalSelected;
  bool _includeLocation = false;
  bool _locatingNow = false;

  /// Set only from a successful read while consent was on. Cleared the moment
  /// consent goes off, so the payload can never carry a stale position.
  double? _latitude;
  double? _longitude;
  String? _locationError;

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
                onChanged: _locatingNow ? null : _onLocationConsentChanged,
                title: Text(
                  'Include my location',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: _locationSubtitle(),
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primaryRed,
              ),

              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _locatingNow ? null : _send,
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

  /// Tells the patient exactly what the switch achieved: a real fix, a
  /// failure with its reason, or work in progress. Without this the toggle
  /// looks on while no coordinates exist.
  Widget? _locationSubtitle() {
    if (_locatingNow) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Getting your location…',
              style: GoogleFonts.inter(fontSize: 11.5)),
        ],
      );
    }
    if (_locationError != null) {
      return Text(
        '$_locationError Your consult will be sent without a location.',
        style: GoogleFonts.inter(
            fontSize: 11.5, color: Colors.orange.shade900, height: 1.3),
      );
    }
    if (_latitude != null && _longitude != null) {
      return Text(
        '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
        style: GoogleFonts.inter(
            fontSize: 11.5, color: AppColors.textDark.withValues(alpha: 0.6)),
      );
    }
    return null;
  }

  /// Consent is not a location. Turning the switch on asks for permission and
  /// reads a position; only a successful read arms the coordinates, and a
  /// denial puts the switch back off with the reason shown (issue #17
  /// review).
  Future<void> _onLocationConsentChanged(bool wanted) async {
    if (!wanted) {
      setState(() {
        _includeLocation = false;
        _latitude = null;
        _longitude = null;
        _locationError = null;
      });
      return;
    }
    setState(() {
      _includeLocation = true;
      _locatingNow = true;
      _locationError = null;
    });
    final result = await widget.locationReader();
    if (!mounted) return;
    setState(() {
      _locatingNow = false;
      if (result.ok) {
        _latitude = result.latitude;
        _longitude = result.longitude;
      } else {
        // No position, so no consent to act on — the switch must not sit on
        // implying a location is attached.
        _includeLocation = false;
        _latitude = null;
        _longitude = null;
        _locationError = result.reason;
      }
    });
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
          // Both or neither: CasePayload.includeLocation is derived from
          // these, so there is no way to claim a location without one.
          latitude: _includeLocation ? _latitude : null,
          longitude: _includeLocation ? _longitude : null,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }
}
