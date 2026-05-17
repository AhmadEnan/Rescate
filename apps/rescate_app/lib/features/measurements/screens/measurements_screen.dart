import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:offline_data/offline_data.dart';
import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:sensor_availability/sensor_availability.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/widgets/top_bar.dart';

class MeasurementsScreen extends StatefulWidget {
  const MeasurementsScreen({super.key});

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen>
    with SingleTickerProviderStateMixin {
  final SensorAvailabilityService _sensorService =
      SensorAvailabilityService.instance;

  List<BiometricMeasurement> _measurements = [];
  bool _isLoadingHistory = true;
  bool _isDetecting = false;
  TabController? _tabController;

  TabController get _tabs {
    _tabController ??= TabController(length: 3, vsync: this);
    return _tabController!;
  }

  @override
  void initState() {
    super.initState();
    _loadMeasurements();
    if (!_sensorService.isReady) {
      _detectSensors();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _detectSensors() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);
    try {
      await _sensorService.detectAll().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Sensor detection failed: $e');
    }
    if (mounted) setState(() => _isDetecting = false);
  }

  Future<void> _loadMeasurements() async {
    try {
      final store = await MeasurementStore.open();
      final recent = await store.recentAll(limit: 50);
      await store.close();
      if (mounted) {
        setState(() {
          _measurements = recent;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const TopBar(),
            // Title row
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Vitals & Diagnostics',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  _PillButton(
                    icon: LucideIcons.refreshCw,
                    spinning: _isDetecting,
                    onTap: () {
                      _detectSensors();
                      setState(() => _isLoadingHistory = true);
                      _loadMeasurements();
                    },
                  ),
                ],
              ),
            ),
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: AppColors.primaryRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textDark.withOpacity(0.6),
                labelStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                labelPadding: EdgeInsets.zero,
                tabs: const [
                  Tab(text: 'Sensors'),
                  Tab(text: 'Tests'),
                  Tab(text: 'History'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _SensorsTab(
                    service: _sensorService,
                    isDetecting: _isDetecting,
                  ),
                  _TestsTab(
                    service: _sensorService,
                    isDetecting: _isDetecting,
                  ),
                  _HistoryTab(
                    measurements: _measurements,
                    isLoading: _isLoadingHistory,
                    onRefresh: () {
                      setState(() => _isLoadingHistory = true);
                      _loadMeasurements();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Refresh pill button ─────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.onTap,
    this.spinning = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: spinning ? null : onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          shape: BoxShape.circle,
        ),
        child: spinning
            ? const Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryRed,
                ),
              )
            : Icon(icon, size: 18, color: AppColors.textDark),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — SENSORS
// ═══════════════════════════════════════════════════════════════════════════════

class _SensorsTab extends StatelessWidget {
  const _SensorsTab({required this.service, required this.isDetecting});

  final SensorAvailabilityService service;
  final bool isDetecting;

  @override
  Widget build(BuildContext context) {
    if (!service.isReady) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primaryRed),
            const SizedBox(height: 16),
            Text(
              'Probing device sensors…',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textDark.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    final grouped = service.grouped;
    final reports = service.reports;
    final available =
        reports.where((r) => r.status == SensorStatus.available).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // Summary card
        _GlassCard(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.cpu,
                    color: AppColors.primaryRed, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$available / ${reports.length} sensors detected',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (service.lastDetectionDuration != null)
                      Text(
                        'Probed in ${service.lastDetectionDuration!.inMilliseconds} ms',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textDark.withOpacity(0.45),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Grouped sensors
        for (final cat in SensorCategory.values)
          if (grouped[cat] != null && grouped[cat]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
              child: Text(
                cat.displayName.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.primaryRed.withOpacity(0.7),
                ),
              ),
            ),
            ...grouped[cat]!.map((r) {
              final d = descriptorFor(r.id);
              return _SensorRow(descriptor: d, report: r);
            }),
          ],
      ],
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({required this.descriptor, required this.report});

  final SensorDescriptor descriptor;
  final SensorReport report;

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    switch (report.status) {
      case SensorStatus.available:
        statusColor = const Color(0xFF34C759);
        statusIcon = LucideIcons.checkCircle;
        statusLabel = 'Available';
      case SensorStatus.unavailable:
        statusColor = Colors.grey;
        statusIcon = LucideIcons.xCircle;
        statusLabel = 'Unavailable';
      case SensorStatus.unknown:
        statusColor = Colors.orange;
        statusIcon = LucideIcons.helpCircle;
        statusLabel = 'Unknown';
      case SensorStatus.needsPermission:
        statusColor = Colors.amber;
        statusIcon = LucideIcons.lock;
        statusLabel = 'Needs Permission';
    }

    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descriptor.displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  descriptor.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textDark.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — TESTS (Available Biometrics)
// ═══════════════════════════════════════════════════════════════════════════════

class _TestsTab extends StatelessWidget {
  const _TestsTab({required this.service, required this.isDetecting});

  final SensorAvailabilityService service;
  final bool isDetecting;

  @override
  Widget build(BuildContext context) {
    if (!service.isReady) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primaryRed),
            const SizedBox(height: 16),
            Text(
              'Detecting available tests…',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textDark.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    final biometrics = service.biometrics;
    final availableTests =
        biometrics.where((b) => b.status == BiometricStatus.available).toList();
    final potentialTests = biometrics
        .where((b) => b.status == BiometricStatus.potentiallyAvailable)
        .toList();
    final unavailableTests = biometrics
        .where((b) => b.status == BiometricStatus.unavailable)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        // Summary card
        _GlassCard(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.heartPulse,
                    color: Color(0xFF34C759), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${availableTests.length} tests ready',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      '${potentialTests.length} potential · ${unavailableTests.length} unavailable',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textDark.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Available tests
        if (availableTests.isNotEmpty) ...[
          _SectionLabel(
              label: 'READY TO MEASURE',
              color: const Color(0xFF34C759)),
          ...availableTests.map(
            (r) => _TestCard(
              report: r,
              descriptor: biometricDescriptorFor(r.id),
              onTap: () => _openTest(context, r.id),
            ),
          ),
        ],
        // Potential tests
        if (potentialTests.isNotEmpty) ...[
          _SectionLabel(label: 'MAY BE AVAILABLE', color: Colors.orange),
          ...potentialTests.map(
            (r) => _TestCard(
              report: r,
              descriptor: biometricDescriptorFor(r.id),
              onTap: () => _openTest(context, r.id),
            ),
          ),
        ],
        // Unavailable tests
        if (unavailableTests.isNotEmpty) ...[
          _SectionLabel(label: 'NOT AVAILABLE', color: Colors.grey),
          ...unavailableTests.map(
            (r) => _TestCard(
              report: r,
              descriptor: biometricDescriptorFor(r.id),
              onTap: null,
            ),
          ),
        ],
      ],
    );
  }

  void _openTest(BuildContext context, BiometricId id) async {
    final store = await MeasurementStore.open();
    if (!context.mounted) {
      await store.close();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BiometricDetailScreen(
          id: id,
          measurementStore: store,
        ),
      ),
    );
    await store.close();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: color.withOpacity(0.8),
        ),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.report,
    required this.descriptor,
    required this.onTap,
  });

  final BiometricReport report;
  final BiometricDescriptor descriptor;
  final VoidCallback? onTap;

  IconData get _categoryIcon {
    final sensors = descriptor.sourceSensors;
    if (sensors.contains(SensorId.accelerometer)) return LucideIcons.activity;
    if (sensors.contains(SensorId.gyroscope)) return LucideIcons.rotateCw;
    if (sensors.contains(SensorId.memsMicrophone)) return LucideIcons.mic;
    if (sensors.contains(SensorId.barometer)) return LucideIcons.wind;
    if (sensors.contains(SensorId.heartRatePpg)) return LucideIcons.heart;
    if (sensors.contains(SensorId.cmosImageSensor)) return LucideIcons.camera;
    if (sensors.contains(SensorId.ambientLight)) return LucideIcons.eye;
    if (sensors.contains(SensorId.pulseOximeter)) return LucideIcons.droplet;
    return LucideIcons.thermometer;
  }

  Color get _statusAccent {
    switch (report.status) {
      case BiometricStatus.available:
        return const Color(0xFF34C759);
      case BiometricStatus.potentiallyAvailable:
        return Colors.orange;
      case BiometricStatus.unavailable:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = report.status != BiometricStatus.unavailable;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: onTap,
        child: _GlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _statusAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_categoryIcon, color: _statusAccent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descriptor.displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      descriptor.biomarker,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textDark.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: descriptor.sourceSensors.map((s) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.name,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark.withOpacity(0.5),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.play,
                    color: AppColors.primaryRed,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.measurements,
    required this.isLoading,
    required this.onRefresh,
  });

  final List<BiometricMeasurement> measurements;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryRed),
      );
    }
    if (measurements.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.clipboardList,
                size: 56, color: AppColors.textDark.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(
              'No measurements yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Run a test from the Tests tab to see results here.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textDark.withOpacity(0.35),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      itemCount: measurements.length,
      itemBuilder: (context, index) =>
          _HistoryCard(measurement: measurements[index]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.measurement});

  final BiometricMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    final date = measurement.capturedAt.toLocal();
    final timeStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} "
        "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";

    IconData icon;
    Color color;
    String title = measurement.displayName;

    if (measurement.id == BiometricId.seismocardiography ||
        measurement.id == BiometricId.gyrocardiography ||
        measurement.id == BiometricId.ppgCardiovascular) {
      icon = LucideIcons.heart;
      color = Colors.red;
    } else if (measurement.id == BiometricId.acousticRespiration ||
        measurement.id == BiometricId.spirometry ||
        measurement.id == BiometricId.radarCardiopulmonary) {
      icon = LucideIcons.wind;
      color = Colors.blue;
    } else if (measurement.id == BiometricId.pulseOximetry) {
      icon = LucideIcons.droplet;
      color = Colors.lightBlue;
    } else {
      icon = LucideIcons.activity;
      color = AppColors.primaryRed;
    }

    return _GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textDark.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    measurement.primary?.value.toStringAsFixed(1) ?? '--',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    measurement.primary?.unit ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark.withOpacity(0.45),
                    ),
                  ),
                ],
              ),
              if (measurement.confidence > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: measurement.confidence > 0.8
                        ? const Color(0xFF34C759).withOpacity(0.12)
                        : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${(measurement.confidence * 100).toInt()}% conf.',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: measurement.confidence > 0.8
                          ? const Color(0xFF34C759)
                          : Colors.orange,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED GLASS CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 0),
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
