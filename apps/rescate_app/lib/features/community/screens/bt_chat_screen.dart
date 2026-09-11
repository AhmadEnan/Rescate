import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:offline_data/offline_data.dart';
import 'package:security_crypto/security_crypto.dart'
    show ResponderCredential;
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../../core/providers/demo_state.dart';
import 'package:bluetooth_mesh/bluetooth_mesh.dart';
import '../models/case_payload.dart';
import '../services/consult_state.dart';
import '../widgets/case_payload_sheet.dart';

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
  final List<ConsultChatEntry> _secureMessages = [];
  bool _isConnected = true;

  bool get _effectiveConnected =>
      DemoState.instance.isDemoMode || _isConnected;

  bool get _verified =>
      !DemoState.instance.isDemoMode &&
      ConsultState.instance.isVerified(widget.endpointId);

  ResponderCredential? get _peerCredential => ConsultState.instance
      .verifiedPeers[widget.endpointId];

  @override
  void initState() {
    super.initState();
    _nearby.onMessageReceived = _handleIncoming;
    _nearby.onConnectionChanged = _handleConnectionChange;
    ConsultState.instance.addListener(_onConsultChanged);

    // Kick off badge verification for real consultations (issue #17). A
    // responder device never initiates — its sessions form when a patient
    // contacts it.
    if (!DemoState.instance.isDemoMode &&
        !ConsultState.instance.isResponderMode &&
        !ConsultState.instance.isVerified(widget.endpointId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ConsultState.instance.beginHandshake(widget.endpointId);
      });
    }
  }

  void _onConsultChanged() {
    if (!mounted) return;
    setState(() {
      _secureMessages
        ..clear()
        ..addAll(ConsultState.instance.historyFor(widget.endpointId));
    });
    _scrollToBottom();
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
    if (text.isEmpty || !_effectiveConnected) return;

    if (DemoState.instance.isDemoMode) {
      setState(() => _messages.add(BtChatMessage(text: text, isSent: true)));
      _msgController.clear();
      _scrollToBottom();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        final replies = [
          'Thank you for sharing your vitals. Let me review them.',
          'I can see your readings. Your heart rate looks normal.',
          'Based on what you\'ve described, I\'d recommend monitoring your blood pressure.',
          'I\'ve received your information. Can you tell me more about your symptoms?',
          'Everything looks stable. Keep taking measurements at the same time each day.',
        ];
        final reply = replies[DateTime.now().second % replies.length];
        setState(() => _messages.add(BtChatMessage(text: reply, isSent: false)));
        _scrollToBottom();
      });
      return;
    }

    if (_verified) {
      // Encrypted, authenticated channel.
      ConsultState.instance.sendSecureText(widget.endpointId, text);
    } else {
      // Unverified peer — plain legacy chat, no patient data allowed.
      _nearby.sendMessage(widget.endpointId, text);
      setState(() => _messages.add(BtChatMessage(text: text, isSent: true)));
    }
    _msgController.clear();
    _scrollToBottom();
  }

  Future<void> _sendConsultRequest() async {
    if (!_verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'This device is not a verified medical responder — patient '
              'data cannot be shared.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    final store = await MeasurementStore.open();
    final recent = await store.recentAll(limit: 5);
    await store.close();
    final vitals = <String>[
      for (final m in recent)
        '${m.displayName}: '
        '${m.primary?.value.toStringAsFixed(1) ?? '--'} ${m.primary?.unit ?? ''}',
    ];

    final result = await showCasePayloadSheet(
      context,
      responderName: _peerCredential?.name ?? widget.endpointName,
      availableVitals: vitals,
    );
    if (result == null || !mounted) return;
    final sent =
        await ConsultState.instance.sendCasePayload(widget.endpointId, result.payload);
    if (mounted && !sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not send — session closed.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    _nearby.onMessageReceived = null;
    ConsultState.instance.removeListener(_onConsultChanged);
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
            // ── Trust banner (issue #17) ─────────────────────────
            if (!DemoState.instance.isDemoMode) _buildTrustBanner(isArabic),
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
              child: (_messages.isEmpty && _secureMessages.isEmpty)
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
                      itemCount: _messages.length + _secureMessages.length,
                      itemBuilder: (_, i) {
                        if (i < _messages.length) {
                          return _buildBubble(_messages[i]);
                        }
                        return _buildConsultEntry(
                            _secureMessages[i - _messages.length]);
                      },
                    ),
            ),
            _buildInputBar(isArabic),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustBanner(bool isArabic) {
    final credential = _peerCredential;
    if (_verified && credential != null) {
      // Patient side: talking to a badge-verified responder.
      return Container(
        color: const Color(0xFF34C759).withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Icon(LucideIcons.shieldCheck,
                color: Color(0xFF34C759), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Verified ${credential.role.title}: ${credential.name} — end-to-end encrypted',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF248A3D),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_verified) {
      // Responder side: session is encrypted; the patient has no badge by
      // design (trust flows one way — responder → patient).
      return Container(
        color: const Color(0xFF34C759).withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Icon(LucideIcons.lock,
                color: Color(0xFF34C759), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Encrypted session — patient identity not claimed',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF248A3D),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final verifying = _isConnected && !ConsultState.instance.isResponderMode;
    return Container(
      color: Colors.orange.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            verifying ? LucideIcons.loader : LucideIcons.shieldAlert,
            color: Colors.orange.shade800,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              verifying
                  ? 'Verifying medical responder…'
                  : 'Unverified device — patient data sharing disabled.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
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

  Widget _buildConsultEntry(ConsultChatEntry entry) {
    if (entry.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textDark.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      );
    }
    return _buildBubble(BtChatMessage(
      text: entry.text,
      isSent: entry.isSent,
      timestamp: entry.timestamp,
    ));
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
            // Consult request (case payload) — verified peers only
            GestureDetector(
              onTap: _isConnected ? _sendConsultRequest : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _verified
                      ? AppColors.primaryRed.withValues(alpha: 0.1)
                      : AppColors.cardBackgroundLight.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _verified ? LucideIcons.heartPulse : LucideIcons.lock,
                  color: _verified
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
