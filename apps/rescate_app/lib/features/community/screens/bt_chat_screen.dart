import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:offline_data/offline_data.dart';
import 'package:biometric_estimators/biometric_estimators.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import 'package:bluetooth_mesh/bluetooth_mesh.dart';

class BtChatScreen extends StatefulWidget {
  final String endpointId;
  final String endpointName;

  const BtChatScreen({
    super.key,
    required this.endpointId,
    required this.endpointName,
  });

  @override
  State<BtChatScreen> createState() => _BtChatScreenState();
}

class _BtChatScreenState extends State<BtChatScreen> {
  final NearbyService _nearby = NearbyService();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<BtChatMessage> _messages = [];
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _nearby.onMessageReceived = _handleIncoming;
    _nearby.onConnectionChanged = _handleConnectionChange;
  }

  void _handleIncoming(String endpointId, String text) {
    if (endpointId == widget.endpointId && mounted) {
      setState(() => _messages.add(BtChatMessage(text: text, isSent: false)));
      _scrollToBottom();
    }
  }

  void _handleConnectionChange(String id, String name, bool connected) {
    if (id == widget.endpointId && mounted) {
      setState(() => _isConnected = connected);
    }
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty || !_isConnected) return;
    _nearby.sendMessage(widget.endpointId, text);
    setState(() => _messages.add(BtChatMessage(text: text, isSent: true)));
    _msgController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _shareVitals() async {
    try {
      final store = await MeasurementStore.open();
      final recent = await store.recentAll(limit: 5);
      await store.close();
      if (recent.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No vitals to share. Run a test first.'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
      final buf = StringBuffer('📊 My Recent Vitals:\n');
      for (final m in recent) {
        final val = m.primary?.value.toStringAsFixed(1) ?? '--';
        final unit = m.primary?.unit ?? '';
        buf.writeln('• ${m.displayName}: $val $unit');
      }
      final text = buf.toString().trim();
      if (!_isConnected) return;
      _nearby.sendMessage(widget.endpointId, text);
      setState(() => _messages.add(BtChatMessage(text: text, isSent: true)));
      _scrollToBottom();
    } catch (e) {
      debugPrint('Share vitals failed: $e');
    }
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    _nearby.onMessageReceived = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          backgroundColor: AppColors.background,
          elevation: 1,
          iconTheme: const IconThemeData(color: AppColors.textDark),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryRed,
                ),
                child: Center(
                  child: Text(
                    widget.endpointName.isNotEmpty
                        ? widget.endpointName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.endpointName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isConnected
                              ? Colors.green.shade600
                              : Colors.red.shade600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isConnected
                            ? (isArabic ? 'متصل' : 'Connected')
                            : (isArabic ? 'غير متصل' : 'Disconnected'),
                        style: TextStyle(
                          fontSize: 11,
                          color: _isConnected
                              ? Colors.green.shade600
                              : Colors.red.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.unlink, size: 20),
              tooltip: isArabic ? 'قطع الاتصال' : 'Disconnect',
              onPressed: () {
                _nearby.disconnect(widget.endpointId);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Disconnected banner
            if (!_isConnected)
              Container(
                color: Colors.orange.withValues(alpha: 0.2),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isArabic
                            ? 'تم قطع الاتصال. لا يمكن إرسال الرسائل.'
                            : 'Disconnected. Cannot send messages.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.messageCircle,
                            size: 64,
                            color: AppColors.primaryRed.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isArabic ? 'لا توجد رسائل بعد' : 'No messages yet',
                            style: TextStyle(
                              color: AppColors.textDark.withValues(alpha: 0.5),
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            isArabic ? 'قل مرحباً! 👋' : 'Say hello! 👋',
                            style: TextStyle(
                              color: AppColors.textDark.withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _buildBubble(_messages[i]),
                    ),
            ),
            _buildInputBar(isArabic),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(BtChatMessage msg) {
    final isSent = msg.isSent;
    final time =
        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSent ? AppColors.primaryRed : AppColors.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isSent ? 18 : 4),
            bottomRight: Radius.circular(isSent ? 4 : 18),
          ),
          boxShadow: isSent
              ? [
                  BoxShadow(
                    color: AppColors.primaryRed.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: isSent
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: isSent ? Colors.white : AppColors.textDark,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                color: isSent
                    ? Colors.white.withValues(alpha: 0.5)
                    : AppColors.textDark.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isArabic) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withValues(alpha: 0.8),
          border: Border(
            top: BorderSide(color: AppColors.primaryRed.withValues(alpha: 0.1)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: isArabic ? 'اكتب رسالة…' : 'Type a message…',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                enabled: _isConnected,
              ),
            ),
            const SizedBox(width: 6),
            // Share vitals button
            GestureDetector(
              onTap: _isConnected ? _shareVitals : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isConnected
                      ? AppColors.primaryRed.withOpacity(0.1)
                      : AppColors.cardBackgroundLight.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.heartPulse,
                  color: _isConnected
                      ? AppColors.primaryRed
                      : AppColors.cardBackgroundLight,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _isConnected
                      ? AppColors.primaryRed
                      : AppColors.cardBackgroundLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.send,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
