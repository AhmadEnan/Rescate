import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/providers/app_state.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _myLocation = const LatLng(33.515, 36.295);
  bool _showRoute = false;

  @override
  void initState() {
    super.initState();
    _determinePosition();
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
      setState(() {
        _myLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_myLocation, 14.5);
    } catch (e) {
      print('Error getting location: $e');
    }
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
    _mapController.move(_myLocation, 14.5);
  }

  void _toggleRoute() {
    setState(() {
      _showRoute = !_showRoute;
    });
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
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              // Danger zone circles
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: const LatLng(33.525, 36.31),
                    radius: 900,
                    color: Colors.red.withOpacity(0.25),
                    borderColor: Colors.red.withOpacity(0.7),
                    borderStrokeWidth: 2,
                  ),
                  CircleMarker(
                    point: const LatLng(33.502, 36.27),
                    radius: 600,
                    color: Colors.red.withOpacity(0.2),
                    borderColor: Colors.red.withOpacity(0.6),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              // Zone labels
              MarkerLayer(
                markers: [
                  Marker(
                    point: const LatLng(33.525, 36.31),
                    width: 200,
                    height: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isArabic ? 'كورتا شرق: نشط' : 'KORTA EAST: ACTIVE',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF8B1A1A))),
                        Text(isArabic ? 'منطقة قصف (تجنبها)' : 'BOMBING ZONE (AVOID)',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF8B1A1A))),
                        Text(isArabic ? 'مخاطرة عالية - تجنب المنطقة' : 'HIGH RISK - AVOID AREA',
                            style: GoogleFonts.poppins(
                                fontSize: 9, color: const Color(0xFF8B1A1A))),
                      ],
                    ),
                  ),
                  Marker(
                    point: const LatLng(33.502, 36.27),
                    width: 180,
                    height: 50,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isArabic ? 'كورتا شمال:' : 'KORTA NORTH:',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF8B1A1A))),
                        Text(isArabic ? 'منطقة ضربات جزئية' : 'PARTIAL STRIKE AREA',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF8B1A1A))),
                        Text(isArabic ? 'مخاطرة عالية - تجنب المنطقة' : 'HIGH RISK - AVOID AREA',
                            style: GoogleFonts.poppins(
                                fontSize: 8, color: const Color(0xFF8B1A1A))),
                      ],
                    ),
                  ),
                  // Red Crescent pin
                  Marker(
                    point: const LatLng(33.513, 36.285),
                    width: 160,
                    height: 70,
                    child: Column(
                      children: [
                        Icon(LucideIcons.mapPin,
                            color: AppColors.primaryRed, size: 28),
                        Text(isArabic ? 'الهلال الأحمر' : 'RED CRESCENT',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryRed)),
                        Text(isArabic ? 'النقطة 3' : 'POINT 3',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryRed)),
                      ],
                    ),
                  ),
                ],
              ),
              if (_showRoute)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        _myLocation,
                        const LatLng(33.513, 36.285), // Red Crescent point
                      ],
                      strokeWidth: 4.0,
                      color: AppColors.primaryRed,
                    ),
                  ],
                ),
              // User mock location pin
              MarkerLayer(
                markers: [
                  Marker(
                    point: _myLocation,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
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
              child: const Icon(LucideIcons.chevronLeft,
                  color: AppColors.textDark, size: 20),
              onTap: () => Navigator.maybePop(context),
            ),
          ),

          // ── Zoom Controls ────────────────────────────────────
          Positioned(
            top: 48,
            right: 16,
            child: Column(
              children: [
                _MapButton(
                  child: const Icon(LucideIcons.plus,
                      color: AppColors.textDark, size: 18),
                  onTap: _zoomIn,
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: const Icon(LucideIcons.minus,
                      color: AppColors.textDark, size: 18),
                  onTap: _zoomOut,
                ),
              ],
            ),
          ),

          // ── Bottom Controls ──────────────────────────────────
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              children: [
                _MapButton(
                  child: const Icon(LucideIcons.crosshair,
                      color: AppColors.textDark, size: 18),
                  onTap: _centerMap,
                ),
                const SizedBox(height: 8),
                _MapButton(
                  child: Icon(LucideIcons.navigation,
                      color: _showRoute ? AppColors.primaryRed : AppColors.textDark, size: 18),
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