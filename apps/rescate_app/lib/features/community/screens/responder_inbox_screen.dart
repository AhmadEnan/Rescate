// Inbox of consult requests for a verified medical responder (issue #17).
// Requests arrive only over badge-verified encrypted sessions, contain the
// consented case payload, and can be accepted or declined with a reply.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../models/case_payload.dart';
import '../services/consult_state.dart';

class ResponderInboxScreen extends StatefulWidget {
  const ResponderInboxScreen({super.key});

  @override
  State<ResponderInboxScreen> createState() => _ResponderInboxScreenState();
}

class _ResponderInboxScreenState extends State<ResponderInboxScreen> {
  late List<ConsultRequest> _inbox;

  @override
  void initState() {
    super.initState();
    _inbox = List.from(ConsultState.instance.inbox);
    ConsultState.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() => _inbox = List.from(ConsultState.instance.inbox));
  }

  @override
  void dispose() {
    ConsultState.instance.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _answer(ConsultRequest request, bool accept) async {
    final controller = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(accept ? 'Accept consult' : 'Decline consult'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          autofocus: true,
          decoration: InputDecoration(
            hintText: accept
                ? 'Message to the patient (optional)…'
                : 'Reason (optional)…',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  accept ? const Color(0xFF34C759) : Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(accept ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );
    if (reply == null) return;
    await ConsultState.instance.answerRequest(
      request,
      accept,
      replyText: accept ? reply : '',
    );
  }

  String _peerName(String endpointId) =>
      ConsultState.instance.serviceName(endpointId) ?? endpointId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        title: Text(
          'Consult Inbox',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: _inbox.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.inbox,
                      size: 56,
                      color: AppColors.primaryRed.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No consult requests yet.\nNearby patients will appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textDark.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _inbox.length,
              itemBuilder: (_, i) {
                final request = _inbox[i];
                final payload = request.payload;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: request.status == ConsultRequestStatus.pending
                        ? Border.all(
                            color: AppColors.primaryRed.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.user,
                              size: 16, color: AppColors.primaryRed),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _peerName(request.endpointId),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          _statusChip(request.status),
                        ],
                      ),
                      if (payload.symptoms.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: payload.symptoms
                              .map((s) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryRed
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      s,
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryRed),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                      if (payload.urgency.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(LucideIcons.triangleAlert,
                                size: 13, color: Colors.orange.shade800),
                            const SizedBox(width: 5),
                            Text(
                              'Urgency: ${payload.urgency}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (payload.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(payload.note,
                            style: const TextStyle(
                                fontSize: 13, height: 1.4)),
                      ],
                      if (payload.vitals.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: payload.vitals
                                .map((v) => Text('• $v',
                                    style: const TextStyle(fontSize: 12.5)))
                                .toList(),
                          ),
                        ),
                      ],
                      if (payload.includeLocation &&
                          payload.latitude != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '📍 ${payload.latitude!.toStringAsFixed(5)}, '
                          '${payload.longitude!.toStringAsFixed(5)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade700),
                        ),
                      ],
                      if (request.status == ConsultRequestStatus.pending) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(LucideIcons.x, size: 16),
                                label: const Text('Decline'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                ),
                                onPressed: () => _answer(request, false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(LucideIcons.check, size: 16),
                                label: const Text('Accept'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF34C759),
                                ),
                                onPressed: () => _answer(request, true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _statusChip(ConsultRequestStatus status) {
    final (label, color) = switch (status) {
      ConsultRequestStatus.pending => ('Pending', AppColors.primaryRed),
      ConsultRequestStatus.accepted => ('Accepted', const Color(0xFF34C759)),
      ConsultRequestStatus.declined => ('Declined', Colors.red.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
