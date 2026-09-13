// ChatGPT-style slide-over sidebar listing saved conversations. Lives inside
// the AI chat tab as a Stack overlay: scrim + physical-left panel that slides
// in (240ms). Selecting a conversation switches the active chat; per-row
// trash deletes.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../state/llm_state.dart';

class ChatHistorySidebar extends StatelessWidget {
  const ChatHistorySidebar({
    super.key,
    required this.open,
    required this.isArabic,
    required this.onClose,
    required this.onNewChat,
    required this.onSelect,
    required this.onDelete,
  });

  final bool open;
  final bool isArabic;
  final VoidCallback onClose;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  String _relativeTime(int millis) {
    final diff = DateTime.now().millisecondsSinceEpoch - millis;
    final minutes = diff ~/ 60000;
    if (minutes < 1) return 'now';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // Closed panel + scrim must never eat touches.
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: onClose,
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: open ? 0 : -280,
              top: 0,
              bottom: 0,
              width: 272,
              child: GestureDetector(
                // Swipe left anywhere on the open panel (or scrim) to close.
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (open && v < -250) onClose();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 18,
                      offset: Offset(4, 0),
                    ),
                  ],
                ),
                child: ListenableBuilder(
                  listenable: LlmState.instance,
                  builder: (context, _) {
                    final llm = LlmState.instance;
                    final conversations = llm.conversations;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                          child: Row(
                            children: [
                              Text(
                                isArabic ? 'المحادثات' : 'Chats',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: onNewChat,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.primaryRed.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(LucideIcons.plus,
                                      size: 18, color: AppColors.primaryRed),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: onClose,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.cardBackground.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(LucideIcons.x,
                                      size: 18, color: AppColors.textDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: conversations.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    isArabic
                                        ? 'لا توجد محادثات محفوظة بعد.'
                                        : 'No saved chats yet.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color:
                                          AppColors.textDark.withOpacity(0.55),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  itemCount: conversations.length,
                                  itemBuilder: (context, index) {
                                    final convo = conversations[index];
                                    final active =
                                        convo.id == llm.activeConversation.id;
                                    final title = convo.title
                                        .replaceAll(
                                            _vitalsContextPattern, '')
                                        .trim();
                                    return Material(
                                      color: active
                                          ? AppColors.primaryRed.withOpacity(0.1)
                                          : Colors.transparent,
                                      child: InkWell(
                                        onTap: () => onSelect(convo.id),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 10),
                                          child: Row(
                                            children: [
                                              Icon(
                                                LucideIcons.messageSquare,
                                                size: 15,
                                                color: active
                                                    ? AppColors.primaryRed
                                                    : AppColors.textDark
                                                        .withOpacity(0.45),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      title.isEmpty
                                                          ? 'New chat'
                                                          : title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        fontWeight: active
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color:
                                                            AppColors.textDark,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${convo.messages.length} msgs · ${_relativeTime(convo.updatedAt)}',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 10.5,
                                                        color: AppColors.textDark
                                                            .withOpacity(0.5),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () => onDelete(convo.id),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  child: Icon(
                                                    LucideIcons.trash2,
                                                    size: 15,
                                                    color: AppColors.textDark
                                                        .withOpacity(0.4),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

final RegExp _vitalsContextPattern =
    RegExp(r'\n\n\[SYSTEM_VITALS_CONTEXT:.*?\]');
