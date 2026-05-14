/// Represents a single chat message.
class BtChatMessage {
  final String text;
  final bool isSent; // true = sent by me, false = received
  final DateTime timestamp;

  BtChatMessage({
    required this.text,
    required this.isSent,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
