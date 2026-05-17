import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../home/widgets/top_bar.dart';
import 'package:bluetooth_mesh/bluetooth_mesh.dart';
import 'bt_chat_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with TickerProviderStateMixin {
  final NearbyService _nearby = NearbyService();
  final TextEditingController _nameController = TextEditingController();
  bool _isActive = false; // advertising + discovering
  late AnimationController _pulseController;

  // Doctor specialization dropdown (pure frontend placeholder)
  String _selectedSpecialty = 'All';
  static const List<String> _specialties = [
    'All',
    'General Practitioner',
    'Emergency Medicine',
    'Cardiologist',
    'Pulmonologist',
    'Neurologist',
    'Orthopedic Surgeon',
    'Pediatrician',
    'Dermatologist',
    'Psychiatrist',
    'Anesthesiologist',
    'Radiologist',
    'Oncologist',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _nearby.addListener(_onNearbyChanged);
    _nearby.onConnectionChanged = _handleConnectionChanged;
    _init();
  }

  Future<void> _init() async {
    await _nearby.init();
    _nameController.text = _nearby.userName;
    await _requestPermissions();
  }

  void _onNearbyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _requestPermissions() async {
    final permissions = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ];
    if (await _supportsNearbyWifiDevicesPermission()) {
      permissions.add(Permission.nearbyWifiDevices);
    }

    final statuses = await permissions.request();

    final allGranted = statuses.values.every((s) => s.isGranted || s.isLimited);

    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Some permissions were denied. Bluetooth features may not work.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<bool> _supportsNearbyWifiDevicesPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt >= 33;
    } on Object {
      return false;
    }
  }

  Future<void> _toggleActive() async {
    if (_isActive) {
      await _nearby.stopAll();
    } else {
      if (_nameController.text.trim().isNotEmpty) {
        _nearby.setUserName(_nameController.text.trim());
      }
      await _nearby.startAdvertising();
      await _nearby.startDiscovery();
    }
    setState(() => _isActive = !_isActive);
  }

  void _handleConnectionChanged(
    String endpointId,
    String name,
    bool connected,
  ) {
    if (!mounted) return;
    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $name'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _connectAndChat(String endpointId, String name) async {
    await _nearby.requestConnection(endpointId);
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) =>
            BtChatScreen(endpointId: endpointId, endpointName: name),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                ),
            child: child,
          );
        },
      ),
    );
  }

  void _openChat(String endpointId, String name) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) =>
            BtChatScreen(endpointId: endpointId, endpointName: name),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _nearby.removeListener(_onNearbyChanged);
    _pulseController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    final discovered = _nearby.discoveredDevices;
    final connected = _nearby.connectedDevices;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
              children: [
                  const TopBar(),

                  // ── Page title ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        isArabic ? 'استشر طبيب' : 'Consult a Doctor',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),

                  // ── Doctor Specialization Dropdown ────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.primaryRed.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.stethoscope,
                              size: 18, color: AppColors.primaryRed),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedSpecialty,
                                isExpanded: true,
                                icon: const Icon(LucideIcons.chevronDown,
                                    size: 16, color: AppColors.primaryRed),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                                dropdownColor: AppColors.background,
                                borderRadius: BorderRadius.circular(14),
                                items: _specialties.map((s) {
                                  return DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedSpecialty = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Username field ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            style: const TextStyle(color: AppColors.textDark),
                            decoration: InputDecoration(
                              hintText: isArabic
                                  ? 'اسم العرض الخاص بك'
                                  : 'Your display name',
                              prefixIcon: const Icon(
                                LucideIcons.user,
                                color: AppColors.primaryRed,
                              ),
                              suffixIcon: _isActive
                                  ? const Padding(
                                      padding: EdgeInsets.only(right: 12),
                                      child: Icon(
                                        LucideIcons.lock,
                                        size: 18,
                                        color: AppColors.cardBackgroundLight,
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.cardBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            enabled: !_isActive,
                            onSubmitted: (v) {
                              if (v.trim().isNotEmpty) {
                                _nearby.setUserName(v.trim());
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Go online / scanning state ────────────────
                  if (!_isActive)
                    // Big clear CTA when offline
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GestureDetector(
                        onTap: _toggleActive,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryRed.withOpacity(0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.bluetooth_searching,
                                  color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                isArabic ? 'ابدأ البحث عن أطباء' : 'Go Online — Find Doctors',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    // Scanning banner with stop button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, child) {
                                return Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF34C759),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF34C759).withOpacity(
                                          _pulseController.value * 0.7,
                                        ),
                                        blurRadius: 8 + _pulseController.value * 8,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isArabic ? 'جاري البحث…' : 'Scanning nearby…',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  Text(
                                    '${discovered.length + connected.length} ${isArabic ? "مستخدم" : "users found"}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppColors.textDark.withOpacity(0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _toggleActive,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryRed.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isArabic ? 'إيقاف' : 'Stop',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryRed,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // ── Device lists ─────────────────────────────
                  Expanded(
                    child: !_isActive
                        ? _buildEmptyState(isArabic)
                        : (discovered.isEmpty && connected.isEmpty)
                            ? _buildEmptyState(isArabic)
                            : ListView(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                children: [
                                  if (connected.isNotEmpty) ...[
                                    _sectionHeader(
                                      isArabic ? 'متصل' : 'Connected',
                                      connected.length,
                                    ),
                                    ...connected.entries.map(
                                      (e) => _deviceTile(
                                        e.key,
                                        e.value,
                                        isConnected: true,
                                        isArabic: isArabic,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (discovered.isNotEmpty) ...[
                                    _sectionHeader(
                                      isArabic ? 'قريب' : 'Nearby',
                                      discovered.length,
                                    ),
                                    ...discovered.entries.map(
                                      (e) => _deviceTile(
                                        e.key,
                                        e.value,
                                        isConnected: false,
                                        isArabic: isArabic,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 120),
                                ],
                              ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryRed.withOpacity(
                        0.04 + _pulseController.value * 0.04,
                      ),
                    ),
                  ),
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryRed.withOpacity(
                        0.08 + _pulseController.value * 0.06,
                      ),
                    ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryRed.withOpacity(0.12),
                    ),
                    child: Icon(
                      _isActive ? Icons.bluetooth_searching : Icons.bluetooth,
                      size: 28,
                      color: AppColors.primaryRed.withOpacity(0.7),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            _isActive
                ? (isArabic ? 'جاري البحث عن مستخدمين قريبين…' : 'Looking for nearby users…')
                : (isArabic ? 'اتصل بالإنترنت للعثور على أشخاص قريبين' : 'Go online to find people nearby'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: AppColors.textDark.withOpacity(0.5),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic ? 'اضغط الزر الأحمر للبدء' : 'Tap the red button to start',
            style: GoogleFonts.inter(
              color: AppColors.textDark.withOpacity(0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              color: AppColors.primaryRed.withOpacity(0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                color: AppColors.primaryRed,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(
    String id,
    String name, {
    required bool isConnected,
    required bool isArabic,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => isConnected ? _openChat(id, name) : _connectAndChat(id, name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isConnected
                        ? [const Color(0xFF34C759), const Color(0xFF30D158)]
                        : [AppColors.primaryRed, AppColors.primaryRed.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isConnected ? const Color(0xFF34C759) : AppColors.primaryRed)
                          .withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnected
                          ? (isArabic ? 'متصل — اضغط للدردشة' : 'Connected — tap to chat')
                          : (isArabic ? 'اضغط للاتصال' : 'Tap to connect'),
                      style: GoogleFonts.inter(
                        color: isConnected
                            ? const Color(0xFF34C759)
                            : AppColors.textDark.withOpacity(0.45),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFF34C759).withOpacity(0.1)
                      : AppColors.primaryRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isConnected ? LucideIcons.messageCircle : LucideIcons.link,
                  color: isConnected ? const Color(0xFF34C759) : AppColors.primaryRed,
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
