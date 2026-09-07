// Data models for the authenticated consult feature (issue #17).
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The only message type allowed to carry patient data. Sent exclusively
/// over a badge-verified encrypted session after explicit user consent.
@immutable
class CasePayload {
  const CasePayload({
    required this.note,
    this.symptoms = const <String>[],
    this.vitals = const <String>[],
    this.includeLocation = false,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  final String note;
  final List<String> symptoms;
  final List<String> vitals; // pre-formatted "Heart rate: 88 bpm" lines
  final bool includeLocation;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'note': note,
        'symptoms': symptoms,
        'vitals': vitals,
        'include_location': includeLocation,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static CasePayload fromJson(Map<String, dynamic> json) => CasePayload(
        note: json['note'] as String? ?? '',
        symptoms:
            (json['symptoms'] as List<dynamic>?)?.cast<String>() ?? const [],
        vitals: (json['vitals'] as List<dynamic>?)?.cast<String>() ?? const [],
        includeLocation: json['include_location'] as bool? ?? false,
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now().toUtc(),
      );

  static CasePayload decode(String raw) =>
      CasePayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// A consult request in the responder's inbox.
enum ConsultRequestStatus { pending, accepted, declined }

@immutable
class ConsultRequest {
  const ConsultRequest({
    required this.endpointId,
    required this.payload,
    required this.receivedAt,
    this.status = ConsultRequestStatus.pending,
  });

  final String endpointId;
  final CasePayload payload;
  final DateTime receivedAt;
  final ConsultRequestStatus status;

  ConsultRequest withStatus(ConsultRequestStatus status) => ConsultRequest(
        endpointId: endpointId,
        payload: payload,
        receivedAt: receivedAt,
        status: status,
      );
}

/// One chat line shown in the secure (verified) portion of a consult chat.
@immutable
class ConsultChatEntry {
  const ConsultChatEntry({
    required this.text,
    required this.isSent,
    this.isSystem = false,
    required this.timestamp,
  });

  final String text;
  final bool isSent;
  final bool isSystem;
  final DateTime timestamp;
}
