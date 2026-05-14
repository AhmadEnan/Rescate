import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../home/widgets/top_bar.dart';
import '../services/nearby_service.dart';
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
  bool _permissionsGranted = false;
  bool _isActive = false; // advertising + discovering
  late AnimationController _pulseController;

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
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    final allGranted =
        statuses.values.every((s) => s.isGranted || s.isLimited);
    setState(() => _permissionsGranted = allGranted);

    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Some permissions were denied. Bluetooth features may not work.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
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
      String endpointId, String name, bool connected) {
    if (!mounted) return;
    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $name'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        pageBuilder: (_, __, ___) => BtChatScreen(
          endpointId: endpointId,
          endpointName: name,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
        pageBuilder: (_, __, ___) => BtChatScreen(
          endpointId: endpointId,
          endpointName: name,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
          child: Stack(
            children: [
              Column(
                children: [
                  const TopBar(),

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
                          prefixIcon: const Icon(LucideIcons.user,
                              color: AppColors.primaryRed),
                          suffixIcon: _isActive
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 12),
                                  child: Icon(LucideIcons.lock,
                                      size: 18,
                                      color: AppColors.cardBackgroundLight),
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
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

              // ── Status banner ────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isActive
                      ? AppColors.primaryRed
                      : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primaryRed.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    if (_isActive)
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (_, child) {
                          return Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.greenAccent,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(
                                      _pulseController.value * 0.7),
                                  blurRadius:
                                      8 + _pulseController.value * 8,
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    else
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.textDark.withOpacity(0.3),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isActive
                            ? (isArabic
                                ? 'جاري البحث عن مستخدمين قريبين…'
                                : 'Scanning for nearby users…')
                            : (isArabic
                                ? 'اضغط الزر للاتصال'
                                : 'Tap the button to go online'),
                        style: TextStyle(
                          color: _isActive
                              ? Colors.white
                              : AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${discovered.length + connected.length}',
                      style: TextStyle(
                        color: _isActive
                            ? Colors.white
                            : AppColors.textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.users,
                      color: _isActive
                          ? Colors.white70
                          : AppColors.textDark.withOpacity(0.5),
                      size: 20,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // ── Device lists ─────────────────────────────
              Expanded(
                child: (discovered.isEmpty && connected.isEmpty)
                    ? _buildEmptyState(isArabic)
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          // Connected devices
                          if (connected.isNotEmpty) ...[
                            _sectionHeader(
                                isArabic ? 'متصل' : 'Connected',
                                connected.length),
                            ...connected.entries.map((e) => _deviceTile(
                                  e.key,
                                  e.value,
                                  isConnected: true,
                                  isArabic: isArabic,
                                )),
                            const SizedBox(height: 16),
                          ],
                          // Discovered (not yet connected)
                          if (discovered.isNotEmpty) ...[
                            _sectionHeader(
                                isArabic ? 'قريب' : 'Nearby',
                                discovered.length),
                            ...discovered.entries.map((e) => _deviceTile(
                                  e.key,
                                  e.value,
                                  isConnected: false,
                                  isArabic: isArabic,
                                )),
                          ],
                        ],
                      ),
              ),
                ],
              ),

              // ── FAB — always visible, clears the 100 px bottom nav ──
              Positioned(
                bottom: 112,
                right: 16,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: FloatingActionButton(
                    onPressed: _toggleActive,
                    backgroundColor: AppColors.primaryRed,
                    shape: const CircleBorder(),
                    elevation: 8,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: _isActive
                          ? const Icon(Icons.bluetooth_disabled,
                              key: ValueKey('off'),
                              size: 28,
                              color: Colors.white)
                          : const Icon(Icons.bluetooth_searching,
                              key: ValueKey('on'),
                              size: 28,
                              color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────
  Widget _buildEmptyState(bool isArabic) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryRed.withOpacity(
                          0.15 + _pulseController.value * 0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Icon(
                  _isActive
                      ? Icons.bluetooth_searching
                      : Icons.bluetooth,
                  size: 52,
                  color: AppColors.primaryRed.withOpacity(0.6),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _isActive
                ? (isArabic
                    ? 'جاري البحث عن مستخدمين قريبين…'
                    : 'Looking for nearby users…')
                : (isArabic
                    ? 'اتصل بالإنترنت للعثور على أشخاص قريبين'
                    : 'Go online to find people nearby'),
            style: TextStyle(
                color: AppColors.textDark.withOpacity(0.5), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textDark.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                  color: AppColors.primaryRed,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(String id, String name,
      {required bool isConnected, required bool isArabic}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () =>
              isConnected ? _openChat(id, name) : _connectAndChat(id, name),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isConnected
                    ? Colors.green.withOpacity(0.3)
                    : AppColors.primaryRed.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? Colors.green.shade700
                        : AppColors.primaryRed,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Name + status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isConnected
                            ? (isArabic
                                ? 'متصل — اضغط للدردشة'
                                : 'Connected — tap to chat')
                            : (isArabic
                                ? 'اضغط للاتصال'
                                : 'Tap to connect'),
                        style: TextStyle(
                          color: isConnected
                              ? Colors.green.shade700
                              : AppColors.textDark.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isConnected
                      ? LucideIcons.messageCircle
                      : LucideIcons.link,
                  color:
                      isConnected ? Colors.green.shade700 : AppColors.primaryRed,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
