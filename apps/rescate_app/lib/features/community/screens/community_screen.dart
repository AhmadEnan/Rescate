import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../home/widgets/top_bar.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:p2p_mesh/p2p_mesh.dart';
import '../../../main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'public_chat_screen.dart';
import 'private_chat_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mesh = MeshInheritedProvider.of(context);
      _nameController.text = mesh.myDisplayName;
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    final mesh = MeshInheritedProvider.of(context);

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            children: [
              const TopBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic ? 'الدردشة القريبة (بدون إنترنت)' : 'Nearby Chat (Offline)',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 16),
                      // Settings Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(LucideIcons.radio, color: AppColors.primaryRed),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    isArabic ? 'تفعيل الشبكة المحلية' : 'Enable Mesh Network',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
                                  ),
                                ),
                                Switch(
                                  value: mesh.isMeshEnabled,
                                  onChanged: (val) async {
                                    if (val) {
                                      await _requestPermissions();
                                    }
                                    mesh.toggleMesh(val);
                                  },
                                  activeColor: AppColors.primaryRed,
                                ),
                              ],
                            ),
                            const Divider(),
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: isArabic ? 'اسم العرض الخاص بك' : 'Your Display Name',
                                suffixIcon: IconButton(
                                  icon: const Icon(LucideIcons.save),
                                  onPressed: () {
                                    mesh.setDisplayName(_nameController.text);
                                  },
                                ),
                              ),
                              onSubmitted: (val) => mesh.setDisplayName(val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Public Channel
                      GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const PublicChatScreen()));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primaryRed.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.globe, color: AppColors.primaryRed),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  isArabic ? 'القناة العامة' : 'Public Broadcast Channel',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryRed),
                                ),
                              ),
                              const Icon(LucideIcons.chevronRight, color: AppColors.primaryRed),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Peers List
                      Text(
                        isArabic ? 'الأجهزة القريبة' : 'Nearby Devices',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: !mesh.isMeshEnabled 
                        ? Center(child: Text(isArabic ? 'الرجاء تفعيل الشبكة لرؤية الأجهزة' : 'Enable mesh to see nearby devices.'))
                        : mesh.peers.isEmpty
                          ? Center(child: Text(isArabic ? 'جاري البحث عن أجهزة...' : 'Scanning for devices...'))
                          : ListView.builder(
                              itemCount: mesh.peers.length,
                              itemBuilder: (context, index) {
                                final peer = mesh.peers[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: peer.inRange ? Colors.green : Colors.grey,
                                    radius: 6,
                                  ),
                                  title: Text(peer.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(peer.inRange ? (isArabic ? 'متصل' : 'In Range') : (isArabic ? 'غير متصل' : 'Offline / Queued')),
                                  trailing: const Icon(LucideIcons.messageCircle),
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateChatScreen(peer: peer)));
                                  },
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
