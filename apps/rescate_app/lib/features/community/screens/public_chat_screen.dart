import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:p2p_mesh/p2p_mesh.dart';
import '../../../main.dart';

class PublicChatScreen extends StatefulWidget {
  const PublicChatScreen({super.key});

  @override
  State<PublicChatScreen> createState() => _PublicChatScreenState();
}

class _PublicChatScreenState extends State<PublicChatScreen> {
  final TextEditingController _msgController = TextEditingController();

  void _sendMsg() {
    final text = _msgController.text.trim();
    if (text.isNotEmpty) {
      MeshInheritedProvider.of(context).sendPublicMessage(text);
      _msgController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    final mesh = MeshInheritedProvider.of(context);
    final messages = mesh.publicMessages;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(isArabic ? 'القناة العامة' : 'Public Broadcast', style: const TextStyle(color: AppColors.textDark)),
          backgroundColor: AppColors.background,
          elevation: 1,
          iconTheme: const IconThemeData(color: AppColors.textDark),
        ),
        body: Column(
          children: [
            if (!mesh.isMeshEnabled)
              Container(
                color: Colors.orange.withOpacity(0.2),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    const Icon(LucideIcons.alertTriangle, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isArabic ? 'الشبكة غير مفعلة. سيتم إرسال الرسائل عند التفعيل.' : 'Mesh is offline. Messages will queue until enabled.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg.isOutgoing;
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.primaryRed : AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                          bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(msg.senderName, style: TextStyle(fontSize: 10, color: AppColors.textDark.withOpacity(0.6))),
                          Text(
                            msg.payloadText,
                            style: TextStyle(color: isMe ? AppColors.textLight : AppColors.textDark),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${DateTime.fromMillisecondsSinceEpoch(msg.timestamp).hour}:${DateTime.fromMillisecondsSinceEpoch(msg.timestamp).minute}',
                                style: TextStyle(fontSize: 10, color: (isMe ? AppColors.textLight : AppColors.textDark).withOpacity(0.6)),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  msg.status == 'sent' || msg.status == 'delivered' ? LucideIcons.checkCheck : LucideIcons.clock,
                                  size: 10,
                                  color: AppColors.textLight.withOpacity(0.6),
                                )
                              ]
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        decoration: InputDecoration(
                          hintText: isArabic ? 'اكتب رسالة...' : 'Type a message...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onSubmitted: (_) => _sendMsg(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: AppColors.primaryRed,
                      child: IconButton(
                        icon: const Icon(LucideIcons.send, color: AppColors.textLight, size: 20),
                        onPressed: _sendMsg,
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
