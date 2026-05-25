class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.isRead = false,
  });

  final String messageId;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isRead;

  bool get isSystem => senderId == ChatServiceIds.systemSenderId;
}

/// Ready for Firestore — single shared store keyed by [conversationId].
class ChatConversation {
  const ChatConversation({
    required this.conversationId,
    required this.patientId,
    required this.doctorId,
    required this.patientName,
    required this.doctorName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.appointmentAccepted,
    this.appointmentId,
    this.unreadCountPatient = 0,
    this.unreadCountDoctor = 0,
  });

  final String conversationId;
  final String patientId;
  final String doctorId;
  final String patientName;
  final String doctorName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final bool appointmentAccepted;
  final String? appointmentId;
  final int unreadCountPatient;
  final int unreadCountDoctor;

  ChatConversation copyWith({
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCountPatient,
    int? unreadCountDoctor,
    bool? appointmentAccepted,
  }) {
    return ChatConversation(
      conversationId: conversationId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: patientName,
      doctorName: doctorName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      appointmentAccepted: appointmentAccepted ?? this.appointmentAccepted,
      appointmentId: appointmentId,
      unreadCountPatient: unreadCountPatient ?? this.unreadCountPatient,
      unreadCountDoctor: unreadCountDoctor ?? this.unreadCountDoctor,
    );
  }
}

/// Avoid circular import in model — mirrored in [ChatService].
abstract class ChatServiceIds {
  static const systemSenderId = '__system__';
}
