import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/app_state.dart';
import '../services/offline_route_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum _ReportType { danger, aid }

class _DownloadedMapArea {
  final LatLng center;
  final double radiusKm;
  final int downloadedAt;

  const _DownloadedMapArea({
    required this.center,
    required this.radiusKm,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'lat': center.latitude,
      'lng': center.longitude,
      'radiusKm': radiusKm,
      'downloadedAt': downloadedAt,
    };
  }

  factory _DownloadedMapArea.fromJson(Map<String, dynamic> json) {
    return _DownloadedMapArea(
      center: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      radiusKm: (json['radiusKm'] as num).toDouble(),
      downloadedAt: json['downloadedAt'] as int,
    );
  }
}

class _DownloadOptionData {
  final double radiusKm;
  final int tileCount;

  const _DownloadOptionData({required this.radiusKm, required this.tileCount});

  double get estimatedSizeMb => (tileCount * 18) / 1024;
}

class _MapReport {
  final String id;
  final _ReportType type;
  final LatLng point;
  final double radius;
  final String label;
  final String detail;
  final int createdAt;

  const _MapReport({
    required this.id,
    required this.type,
    required this.point,
    required this.radius,
    required this.label,
    required this.detail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'lat': point.latitude,
      'lng': point.longitude,
      'radius': radius,
      'label': label,
      'detail': detail,
      'createdAt': createdAt,
    };
  }

  factory _MapReport.fromJson(Map<String, dynamic> json) {
    return _MapReport(
      id: json['id'] as String,
      type: json['type'] == 'aid' ? _ReportType.aid : _ReportType.danger,
      point: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      radius: (json['radius'] as num).toDouble(),
      label: json['label'] as String,
      detail: json['detail'] as String,
      createdAt: json['createdAt'] as int,
    );
  }
}

class _DangerZone {
  final LatLng point;
  final double radius;
  final String label;

  const _DangerZone({
    required this.point,
    required this.radius,
    required this.label,
  });
}

class _MapScreenState extends State<MapScreen> {
  static const String _reportsStorageKey = 'offline_map_reports';
  static const String _downloadedAreasStorageKey =
      'offline_map_downloaded_areas';
  static const String _mapStoreName = 'rescate_offline_map';
  static const LatLng _redCrescentPoint = LatLng(33.513, 36.285);
  static const List<_DangerZone> _baseDangerZones = [];

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();
  final OfflineRouteService _routeService = OfflineRouteService();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  List<double>? _accelerometerValues;
  List<double>? _magnetometerValues;
  LatLng _myLocation = const LatLng(33.515, 36.295);
  bool _showRoute = false;
  _ReportType? _pendingReportType;
  double _pendingDangerRadius = 150;
  bool _isPickingRouteDestination = false;
  LatLng? _routeDestination;
  List<_MapReport> _reports = [];
  List<LatLng> _safeRoute = [];
  bool _isLoadingRoute = false;
  bool _isDownloadingMap = false;
  bool _hasPromptedForCurrentArea = false;
  bool _followHeading = false;
  bool _showCoordinateDetails = false;
  double? _headingDegrees;
  double _mapDownloadProgress = 0;
  String _mapDownloadStatus = '';
  List<_DownloadedMapArea> _downloadedAreas = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
    _loadDownloadedAreas();
    _startOrientationUpdates();
    _determinePosition();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    super.dispose();
  }

  List<_DangerZone> get _dangerZones {
    return [
      ..._baseDangerZones,
      ..._reports
          .where((report) => report.type == _ReportType.danger)
          .map(
            (report) => _DangerZone(
              point: report.point,
              radius: report.radius,
              label: report.label,
            ),
          ),
    ];
  }

  List<_MapReport> get _aidReports {
    return _reports.where((report) => report.type == _ReportType.aid).toList();
  }

  Future<void> _loadReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawReports = prefs.getString(_reportsStorageKey);
      if (rawReports == null) return;

      final decoded = jsonDecode(rawReports) as List<dynamic>;
      final reports = decoded
          .map((item) => _MapReport.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _reports = reports;
      });
    } catch (e) {
      debugPrint('Error loading offline map reports: $e');
    }
  }

  Future<void> _saveReports() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _reports.map((report) => report.toJson()).toList(),
    );
    await prefs.setString(_reportsStorageKey, encoded);
  }

  Future<void> _loadDownloadedAreas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawAreas = prefs.getString(_downloadedAreasStorageKey);
      if (rawAreas == null) return;

      final decoded = jsonDecode(rawAreas) as List<dynamic>;
      final areas = decoded
          .map(
            (item) => _DownloadedMapArea.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _downloadedAreas = areas;
      });
    } catch (e) {
      debugPrint('Error loading offline map areas: $e');
    }
  }

  Future<void> _saveDownloadedAreas() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _downloadedAreas.map((area) => area.toJson()).toList(),
    );
    await prefs.setString(_downloadedAreasStorageKey, encoded);
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      Position position = await Geolocator.getCurrentPosition();
      _applyPosition(position);
      _startPositionUpdates();
      _centerMap();
      await _maybePromptForAreaDownload();
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _applyPosition(Position position) {
    final nextLocation = LatLng(position.latitude, position.longitude);
    final nextHeading = position.heading.isFinite && position.heading >= 0
        ? position.heading
        : _headingDegrees;

    if (!mounted) return;
    setState(() {
      _myLocation = nextLocation;
      _headingDegrees = nextHeading;
    });
    if (_followHeading && nextHeading != null) {
      _mapController.moveAndRotate(
        nextLocation,
        _mapController.camera.zoom,
        nextHeading,
      );
    }
  }

  void _startPositionUpdates() {
    _positionSubscription ??=
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((position) {
          _applyPosition(position);
          if (_showRoute && _routeDestination != null) {
            _setSafeRouteTo(_routeDestination!);
          }
          _maybePromptForAreaDownload();
        });
  }

  void _startOrientationUpdates() {
    const interval = Duration(milliseconds: 250);
    _accelerometerSubscription ??=
        accelerometerEventStream(samplingPeriod: interval).listen((event) {
          _accelerometerValues = [event.x, event.y, event.z];
          _updateCompassHeading();
        });
    _magnetometerSubscription ??=
        magnetometerEventStream(samplingPeriod: interval).listen((event) {
          _magnetometerValues = [event.x, event.y, event.z];
          _updateCompassHeading();
        });
  }

  void _updateCompassHeading() {
    final gravity = _accelerometerValues;
    final magnetic = _magnetometerValues;
    if (gravity == null || magnetic == null) return;

    final ax = gravity[0];
    final ay = gravity[1];
    final az = gravity[2];
    final ex = magnetic[0];
    final ey = magnetic[1];
    final ez = magnetic[2];

    var hx = ey * az - ez * ay;
    var hy = ez * ax - ex * az;
    var hz = ex * ay - ey * ax;
    final hNorm = math.sqrt(hx * hx + hy * hy + hz * hz);
    final gNorm = math.sqrt(ax * ax + ay * ay + az * az);
    if (hNorm < 0.1 || gNorm < 0.1) return;

    hx /= hNorm;
    hy /= hNorm;
    hz /= hNorm;
    final gx = ax / gNorm;
    final gz = az / gNorm;

    final my = gz * hx - gx * hz;
    final azimuthRadians = math.atan2(hy, my);
    final heading = (azimuthRadians * 180 / math.pi + 360) % 360;
    final previous = _headingDegrees;
    if (previous != null &&
        ((heading - previous + 540) % 360 - 180).abs() < 2) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _headingDegrees = heading;
    });
    if (_followHeading) {
      _mapController.moveAndRotate(
        _myLocation,
        _mapController.camera.zoom,
        heading,
      );
    }
  }

  Future<void> _maybePromptForAreaDownload() async {
    if (_hasPromptedForCurrentArea || _hasOfflineDataFor(_myLocation)) return;
    final hasConnection = await _hasInternetConnection();
    if (!mounted || !hasConnection || _hasOfflineDataFor(_myLocation)) return;

    _hasPromptedForCurrentArea = true;
    _showOfflineMapDownloadSheet(AppStateProvider.of(context).isArabic);
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final response = await http
          .get(Uri.parse('https://tile.openstreetmap.org/0/0/0.png'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  bool _hasOfflineDataFor(LatLng point) {
    return _downloadedAreas.any((area) {
      final distanceKm = _distance.as(LengthUnit.Kilometer, area.center, point);
      return distanceKm <= area.radiusKm;
    });
  }

  void _toggleHeadingFollow() {
    final nextValue = !_followHeading;
    setState(() {
      _followHeading = nextValue;
    });
    if (nextValue && _headingDegrees != null) {
      _mapController.moveAndRotate(
        _myLocation,
        _mapController.camera.zoom,
        _headingDegrees!,
      );
    } else if (!nextValue) {
      _mapController.rotate(0);
    }
  }

  String _formatHeading() {
    final heading = _headingDegrees;
    if (heading == null) return '---';
    return '${heading.round()}°';
  }

  String _approximateAreaLabel() {
    final damascusDistanceKm = _distance.as(
      LengthUnit.Kilometer,
      _myLocation,
      _redCrescentPoint,
    );
    if (damascusDistanceKm < 25) return 'Approx. Damascus area';
    return 'Approx. current map area';
  }

  Future<List<_DownloadOptionData>> _loadDownloadOptions() async {
    final options = <_DownloadOptionData>[];
    for (final radiusKm in const [1.0, 3.0, 5.0]) {
      final region = _downloadRegionFor(radiusKm);
      final tileCount = await FMTCStore(_mapStoreName).download.check(region);
      options.add(
        _DownloadOptionData(radiusKm: radiusKm, tileCount: tileCount),
      );
    }
    return options;
  }

  DownloadableRegion _downloadRegionFor(double radiusKm) {
    return CircleRegion(_myLocation, radiusKm).toDownloadable(
      minZoom: 12,
      maxZoom: 16,
      options: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.rescate_app',
      ),
    );
  }

  String _formatDownloadSize(double sizeMb) {
    if (sizeMb < 1) return '${(sizeMb * 1024).round()} KB';
    return '${sizeMb.toStringAsFixed(sizeMb >= 10 ? 0 : 1)} MB';
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _centerMap() {
    if (_followHeading && _headingDegrees != null) {
      _mapController.moveAndRotate(_myLocation, 14.5, _headingDegrees!);
    } else {
      _mapController.move(_myLocation, 14.5);
    }
  }

  void _toggleRoute() {
    final wasShowingRoute = _showRoute;
    setState(() {
      if (wasShowingRoute) {
        _showRoute = false;
        _safeRoute = [];
        _routeDestination = null;
      } else {
        _isPickingRouteDestination = true;
        _pendingReportType = null;
      }
    });
    if (!wasShowingRoute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to choose your destination')),
      );
    }
  }

  LatLng _nearestAidPoint() {
    if (_aidReports.isEmpty) return _redCrescentPoint;

    return _aidReports.reduce((current, next) {
      final currentDistance = _distance(_myLocation, current.point);
      final nextDistance = _distance(_myLocation, next.point);
      return nextDistance < currentDistance ? next : current;
    }).point;
  }

  List<LatLng> _dangerZonePolygon(_DangerZone zone) {
    const earthRadiusMeters = 6371000.0;
    const segments = 72;
    final lat = zone.point.latitude * math.pi / 180;
    final lng = zone.point.longitude * math.pi / 180;
    final angularDistance = zone.radius / earthRadiusMeters;

    return List.generate(segments, (index) {
      final bearing = 2 * math.pi * index / segments;
      final pointLat = math.asin(
        math.sin(lat) * math.cos(angularDistance) +
            math.cos(lat) * math.sin(angularDistance) * math.cos(bearing),
      );
      final pointLng =
          lng +
          math.atan2(
            math.sin(bearing) * math.sin(angularDistance) * math.cos(lat),
            math.cos(angularDistance) - math.sin(lat) * math.sin(pointLat),
          );

      return LatLng(pointLat * 180 / math.pi, pointLng * 180 / math.pi);
    });
  }

  Future<void> _setSafeRouteTo(LatLng destination) async {
    setState(() {
      _routeDestination = destination;
      _showRoute = true;
      _isPickingRouteDestination = false;
      _isLoadingRoute = true;
    });

    final result = await _routeService.findRoute(
      start: _myLocation,
      destination: destination,
      dangerZones: _dangerZones
          .map(
            (zone) =>
                OfflineDangerZone(center: zone.point, radius: zone.radius),
          )
          .toList(),
    );
    if (!mounted) return;

    setState(() {
      _safeRoute = result.points;
      _showRoute = result.isAvailable;
      _isLoadingRoute = false;
    });

    if (!result.isAvailable && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No safe offline road route is available for this destination.',
          ),
        ),
      );
    }
  }

  void _showOfflineMapDownloadSheet(bool isArabic) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<List<_DownloadOptionData>>(
              future: _loadDownloadOptions(),
              builder: (context, snapshot) {
                final options = snapshot.data;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic
                          ? 'تحميل خريطة بدون إنترنت'
                          : 'Download offline map',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isArabic
                          ? 'سيتم تحميل المنطقة حول موقعك الحالي. يستخدم التطبيق هذه البيانات تلقائياً عند تحديد وجهة.'
                          : 'Downloads this area around your current location and uses it automatically when you pick a destination.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textDark.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (options == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ...options.map((option) {
                        final radius = option.radiusKm.round();
                        final label = radius == 1
                            ? (isArabic ? 'منطقة صغيرة' : 'Small area')
                            : radius == 3
                            ? (isArabic ? 'منطقة متوسطة' : 'Medium area')
                            : (isArabic ? 'منطقة كبيرة' : 'Large area');

                        return _ReportOption(
                          icon: Icons.download_rounded,
                          color: Colors.blue,
                          title:
                              '$label - $radius km • ${_formatDownloadSize(option.estimatedSizeMb)}',
                          onTap: () => _downloadOfflineMapArea(
                            radiusKm: option.radiusKm,
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadOfflineMapArea({required double radiusKm}) async {
    Navigator.pop(context);
    if (_isDownloadingMap) return;

    setState(() {
      _isDownloadingMap = true;
      _mapDownloadProgress = 0;
      _mapDownloadStatus = 'Preparing ${radiusKm.round()} km download...';
    });

    try {
      final downloadCenter = _myLocation;
      final region = _downloadRegionFor(radiusKm);

      final progressStream = FMTCStore(_mapStoreName).download.startForeground(
        region: region,
        parallelThreads: 2,
        skipExistingTiles: true,
        skipSeaTiles: false,
      );

      await for (final progress in progressStream) {
        if (!mounted) return;
        final percent = progress.maxTiles == 0
            ? 100.0
            : (progress.attemptedTiles / progress.maxTiles) * 100;
        setState(() {
          _mapDownloadProgress = (percent / 100).clamp(0.0, 1.0);
          _mapDownloadStatus =
              '${progress.attemptedTiles}/${progress.maxTiles} tiles • ${percent.toStringAsFixed(0)}%';
        });
      }

      if (!mounted) return;
      setState(() {
        _mapDownloadProgress = 0;
        _mapDownloadStatus = 'Preparing offline road routing data...';
      });
      final roadGraphReady = await _routeService.prepareRoadGraph(
        center: downloadCenter,
        radiusKm: radiusKm,
      );
      if (!mounted) return;
      if (!roadGraphReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Map tiles downloaded, but offline road routing data failed to prepare.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _downloadedAreas.removeWhere((area) {
          final distanceKm = _distance.as(
            LengthUnit.Kilometer,
            area.center,
            downloadCenter,
          );
          return distanceKm <= math.max(area.radiusKm, radiusKm);
        });
        _downloadedAreas.add(
          _DownloadedMapArea(
            center: downloadCenter,
            radiusKm: radiusKm,
            downloadedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      });
      await _saveDownloadedAreas();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Offline map and routing data downloaded (${radiusKm.round()} km).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offline map download failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingMap = false;
          _mapDownloadProgress = 0;
          _mapDownloadStatus = '';
        });
      }
    }
  }

  Future<void> _addReport(
    _ReportType type,
    LatLng point, {
    double? dangerRadius,
  }) async {
    final reportNumber =
        _reports.where((report) => report.type == type).length + 1;
    final isDanger = type == _ReportType.danger;
    final radius = isDanger ? (dangerRadius ?? _pendingDangerRadius) : 80.0;
    final shouldRecalculateRoute = _showRoute;
    final destination = _routeDestination ?? _nearestAidPoint();
    final report = _MapReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      point: point,
      radius: radius,
      label: isDanger
          ? 'Danger report $reportNumber'
          : 'Aid place $reportNumber',
      detail: isDanger
          ? 'Reported danger zone (${radius.round()}m)'
          : 'Reported aid place',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _reports.add(report);
      _pendingReportType = null;
      _pendingDangerRadius = 150;
    });
    await _saveReports();
    if (shouldRecalculateRoute) {
      await _setSafeRouteTo(destination);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isDanger ? 'Danger zone reported' : 'Aid place reported'),
      ),
    );
  }

  void _startMapPick(_ReportType type, {double dangerRadius = 150}) {
    setState(() {
      _pendingReportType = type;
      _isPickingRouteDestination = false;
      _pendingDangerRadius = dangerRadius;
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          type == _ReportType.danger
              ? 'Tap the map to place the danger zone'
              : 'Tap the map to place the aid point',
        ),
      ),
    );
  }

  void _handleMapTap(LatLng point) {
    if (_isPickingRouteDestination) {
      _setSafeRouteTo(point);
      return;
    }

    final pendingType = _pendingReportType;
    if (pendingType == null) return;
    _addReport(
      pendingType,
      point,
      dangerRadius: pendingType == _ReportType.danger
          ? _pendingDangerRadius
          : null,
    );
  }

  void _showReportSheet(bool isArabic) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isArabic ? 'إضافة بلاغ' : 'Add offline report',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                _ReportOption(
                  icon: Icons.warning_rounded,
                  color: AppColors.primaryRed,
                  title: isArabic
                      ? 'خطر صغير 100 متر'
                      : 'Pick small danger zone - 100m',
                  onTap: () =>
                      _startMapPick(_ReportType.danger, dangerRadius: 100),
                ),
                _ReportOption(
                  icon: Icons.warning_rounded,
                  color: AppColors.primaryRed,
                  title: isArabic
                      ? 'خطر متوسط 200 متر'
                      : 'Pick medium danger zone - 200m',
                  onTap: () =>
                      _startMapPick(_ReportType.danger, dangerRadius: 200),
                ),
                _ReportOption(
                  icon: Icons.warning_rounded,
                  color: AppColors.primaryRed,
                  title: isArabic
                      ? 'خطر كبير 350 متر'
                      : 'Pick large danger zone - 350m',
                  onTap: () =>
                      _startMapPick(_ReportType.danger, dangerRadius: 350),
                ),
                _ReportOption(
                  icon: Icons.add_location_alt_rounded,
                  color: Colors.green,
                  title: isArabic
                      ? 'تحديد مركز مساعدة على الخريطة'
                      : 'Pick aid place on map',
                  onTap: () => _startMapPick(_ReportType.aid),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Marker _buildReportMarker(_MapReport report, bool isArabic) {
    final isDanger = report.type == _ReportType.danger;
    final color = isDanger ? AppColors.primaryRed : Colors.green.shade700;
    final icon = isDanger
        ? Icons.warning_rounded
        : Icons.local_hospital_rounded;

    return Marker(
      point: report.point,
      width: 130,
      height: 72,
      child: GestureDetector(
        onTap: () => _showReportDetails(report, isArabic),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isDanger
                    ? (isArabic ? 'خطر' : 'Danger')
                    : (isArabic ? 'مساعدة' : 'Aid'),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeReport(_MapReport report) async {
    final shouldRecalculateRoute = _showRoute;
    final destination = _routeDestination ?? _nearestAidPoint();
    setState(() {
      _reports.removeWhere((item) => item.id == report.id);
    });
    await _saveReports();
    if (shouldRecalculateRoute) {
      await _setSafeRouteTo(destination);
    }
  }

  void _showReportDetails(_MapReport report, bool isArabic) {
    final isDanger = report.type == _ReportType.danger;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isDanger
                          ? Icons.warning_rounded
                          : Icons.local_hospital_rounded,
                      color: isDanger ? AppColors.primaryRed : Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isDanger
                          ? (isArabic ? 'بلاغ خطر' : 'Danger report')
                          : (isArabic ? 'مركز مساعدة' : 'Aid place'),
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  report.detail,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 14),
                if (isDanger)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _removeReport(report);
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isArabic
                                  ? 'تم حذف منطقة الخطر'
                                  : 'Danger zone removed',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(
                        isArabic ? 'حذف منطقة الخطر' : 'Remove danger zone',
                      ),
                    ),
                  ),
                if (!isDanger)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _setSafeRouteTo(report.point);
                      },
                      icon: const Icon(Icons.route_rounded),
                      label: Text(
                        isArabic ? 'اعرض طريق آمن' : 'Show safe route',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(33.51, 36.29),
              initialZoom: 13.5,
              onTap: (_, point) => _handleMapTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.rescate_app',
                tileProvider: FMTCStore(_mapStoreName).getTileProvider(),
              ),
              // Danger zone areas are real geographic polygons, not pixel circles.
              PolygonLayer(
                polygons: _dangerZones
                    .map(
                      (zone) => Polygon(
                        points: _dangerZonePolygon(zone),
                        color: Colors.red.withOpacity(0.22),
                        borderColor: Colors.red.withOpacity(0.7),
                        borderStrokeWidth: 2,
                      ),
                    )
                    .toList(),
              ),
              // Zone labels
              MarkerLayer(
                markers: [
                  // Red Crescent pin
                  Marker(
                    point: _redCrescentPoint,
                    width: 160,
                    height: 70,
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.mapPin,
                          color: AppColors.primaryRed,
                          size: 28,
                        ),
                        Text(
                          isArabic ? 'الهلال الأحمر' : 'RED CRESCENT',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryRed,
                          ),
                        ),
                        Text(
                          isArabic ? 'النقطة 3' : 'POINT 3',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._reports.map(
                    (report) => _buildReportMarker(report, isArabic),
                  ),
                  if (_routeDestination != null)
                    Marker(
                      point: _routeDestination!,
                      width: 46,
                      height: 46,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
              if (_showRoute)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _safeRoute,
                      strokeWidth: 4.0,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
              if (_isLoadingRoute)
                const MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(33.51, 36.29),
                      width: 120,
                      height: 40,
                      child: Card(child: Center(child: Text('Routing...'))),
                    ),
                  ],
                ),
              // User mock location pin
              MarkerLayer(
                markers: [
                  Marker(
                    point: _myLocation,
                    width: 46,
                    height: 46,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Transform.rotate(
                          angle: ((_headingDegrees ?? 0) * math.pi) / 180,
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Back Button ──────────────────────────────────────
          Positioned(
            top: 48,
            left: 16,
            child: _MapButton(
              child: const Icon(
                LucideIcons.chevronLeft,
                color: AppColors.textDark,
                size: 20,
              ),
              onTap: () => Navigator.maybePop(context),
            ),
          ),

          if (_pendingReportType != null || _isPickingRouteDestination)
            Positioned(
              top: 48,
              left: 68,
              right: 68,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  _isPickingRouteDestination
                      ? (isArabic
                            ? 'اضغط على وجهتك على الخريطة'
                            : 'Tap your destination on the map')
                      : _pendingReportType == _ReportType.danger
                      ? (isArabic
                            ? 'اضغط على الخريطة لتحديد الخطر'
                            : 'Tap map to place danger')
                      : (isArabic
                            ? 'اضغط على الخريطة لتحديد المساعدة'
                            : 'Tap map to place aid'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),

          Positioned(
            left: 16,
            bottom: 116,
            child: _LocationInfoPanel(
              areaLabel: _approximateAreaLabel(),
              latitude: _myLocation.latitude,
              longitude: _myLocation.longitude,
              heading: _formatHeading(),
              isFollowingHeading: _followHeading,
              showCoordinates: _showCoordinateDetails,
              onTap: () {
                setState(() {
                  _showCoordinateDetails = !_showCoordinateDetails;
                });
              },
            ),
          ),

          if (_isDownloadingMap)
            Positioned(
              left: 16,
              right: 72,
              bottom: 200,
              child: _DownloadProgressPanel(
                progress: _mapDownloadProgress,
                status: _mapDownloadStatus,
              ),
            ),

          // ── Zoom Controls ────────────────────────────────────
          Positioned(
            top: 48,
            right: 16,
            child: Column(
              children: [
                _MapButton(
                  child: const Icon(
                    LucideIcons.plus,
                    color: AppColors.textDark,
                    size: 18,
                  ),
                  onTap: _zoomIn,
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: const Icon(
                    LucideIcons.minus,
                    color: AppColors.textDark,
                    size: 18,
                  ),
                  onTap: _zoomOut,
                ),
              ],
            ),
          ),

          // ── Bottom Controls ──────────────────────────────────
          Positioned(
            bottom: 116,
            right: 16,
            child: Column(
              children: [
                _MapButton(
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: _followHeading
                        ? AppColors.primaryRed
                        : AppColors.textDark,
                    size: 20,
                  ),
                  onTap: _toggleHeadingFollow,
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: Icon(
                    _isDownloadingMap
                        ? Icons.hourglass_top_rounded
                        : Icons.download_rounded,
                    color: _isDownloadingMap
                        ? AppColors.primaryRed
                        : AppColors.textDark,
                    size: 20,
                  ),
                  onTap: () => _showOfflineMapDownloadSheet(isArabic),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: const Icon(
                    Icons.add_location_alt_rounded,
                    color: AppColors.textDark,
                    size: 20,
                  ),
                  onTap: () => _showReportSheet(isArabic),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: const Icon(
                    LucideIcons.crosshair,
                    color: AppColors.textDark,
                    size: 18,
                  ),
                  onTap: _centerMap,
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: Icon(
                    LucideIcons.navigation,
                    color: _showRoute
                        ? AppColors.primaryRed
                        : AppColors.textDark,
                    size: 18,
                  ),
                  onTap: _toggleRoute,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _MapButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _LocationInfoPanel extends StatelessWidget {
  final String areaLabel;
  final double latitude;
  final double longitude;
  final String heading;
  final bool isFollowingHeading;
  final bool showCoordinates;
  final VoidCallback onTap;

  const _LocationInfoPanel({
    required this.areaLabel,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.isFollowingHeading,
    required this.showCoordinates,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.place_rounded,
                  color: AppColors.primaryRed,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    areaLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  showCoordinates
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  color: AppColors.textDark.withOpacity(0.65),
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Orientation $heading${isFollowingHeading ? ' • map up' : ''}',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                color: AppColors.textDark.withOpacity(0.75),
              ),
            ),
            if (showCoordinates) ...[
              const SizedBox(height: 3),
              Text(
                '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  color: AppColors.textDark.withOpacity(0.62),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadProgressPanel extends StatelessWidget {
  final double progress;
  final String status;

  const _DownloadProgressPanel({required this.progress, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Downloading map data',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress,
              minHeight: 8,
              backgroundColor: AppColors.textDark.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primaryRed,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textDark.withOpacity(0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const _ReportOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
