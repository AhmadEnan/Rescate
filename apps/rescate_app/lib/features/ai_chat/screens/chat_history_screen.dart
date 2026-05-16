// apps/rescate_app/lib/features/ai_chat/screens/chat_history_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../state/llm_state.dart';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  final LlmState _state = LlmState.instance;

  @override
  void initState() {
    super.initState();
    _state.addListener(_rebuild);
  }

  @override
  void dispose() {
    _state.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _open(String id) async {
    await _state.selectConversation(id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) await _state.deleteConversation(id);
  }

  Future<void> _newChat() async {
    await _state.startNewConversation();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = [..._state.conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final activeId = _state.conversations.isEmpty ? null : _state.activeConversation.id;

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
          'Chat history',
          style: GoogleFonts.inter(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(LucideIcons.plus, color: AppColors.primaryRed),
            onPressed: _newChat,
          ),
        ],
      ),
      body: SafeArea(
        child: conversations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No conversations yet.\nStart chatting to see history here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textDark.withOpacity(0.5),
                    ),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: conversations.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: AppColors.cardBackgroundLight,
                ),
                itemBuilder: (_, i) {
                  final c = conversations[i];
                  final isActive = c.id == activeId;
                  final preview = c.messages.isEmpty
                      ? 'Empty conversation'
                      : c.messages.last.text;
                  return ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primaryRed
                            : AppColors.aiAccentPink.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.messageSquare,
                        size: 18,
                        color: isActive
                            ? Colors.white
                            : AppColors.primaryRed,
                      ),
                    ),
                    title: Text(
                      c.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textDark.withOpacity(0.55),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTimestamp(c.updatedAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textDark.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(LucideIcons.trash2,
                          size: 18, color: AppColors.primaryRed),
                      onPressed: () => _delete(c.id),
                    ),
                    onTap: () => _open(c.id),
                  );
                },
              ),
      ),
    );
  }

  String _formatTimestamp(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
