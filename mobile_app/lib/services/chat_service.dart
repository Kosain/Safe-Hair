import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'firebase_service.dart';

/// In-memory chat store (Firestore-ready). Shared across patient & doctor on this device.
class ChatService extends ChangeNotifier {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const systemSenderId = ChatServiceIds.systemSenderId;

  final List<ChatConversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};

  List<ChatConversation> conversationsForUser({
    required String userId,
    required String role,
  }) {
    final list = _conversations.where((c) {
      if (!c.appointmentAccepted) return false;
      if (role == 'doctor') return c.doctorId == userId;
      return c.patientId == userId;
    }).toList();
    list.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return list;
  }

  ChatConversation? conversationById(String conversationId) {
    try {
      return _conversations.firstWhere((c) => c.conversationId == conversationId);
    } catch (_) {
      return null;
    }
  }

  String otherParticipantName(ChatConversation c, {required String role}) {
    return role == 'doctor' ? c.patientName : c.doctorName;
  }

  int unreadForUser(ChatConversation c, {required String role}) {
    return role == 'doctor' ? c.unreadCountDoctor : c.unreadCountPatient;
  }

  List<ChatMessage> messagesFor(String conversationId) {
    final list = List<ChatMessage>.from(_messages[conversationId] ?? const []);
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  /// Idempotent — call when doctor confirms an appointment.
  ChatConversation ensureConversationAfterAccept({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String patientName,
    required String doctorName,
    String? date,
    String? timeSlot,
  }) {
    final convId = _conversationIdFor(patientId, doctorId, appointmentId);
    final existing = conversationById(convId);
    if (existing != null) {
      if (!existing.appointmentAccepted) {
        final i = _conversations.indexWhere((c) => c.conversationId == convId);
        _conversations[i] = existing.copyWith(appointmentAccepted: true);
        notifyListeners();
      }
      return conversationById(convId)!;
    }

    final dt = [date, timeSlot].where((e) => e != null && e.trim().isNotEmpty).join(' at ').trim();
    final systemText = dt.isEmpty
        ? 'Appointment confirmed. You can now message each other.'
        : 'Appointment confirmed on $dt. You can now message each other.';

    final now = DateTime.now();
    final conv = ChatConversation(
      conversationId: convId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: patientName.trim().isEmpty ? 'Patient' : patientName.trim(),
      doctorName: doctorName.trim().isEmpty ? 'Doctor' : doctorName.trim(),
      lastMessage: systemText,
      lastMessageTime: now,
      appointmentAccepted: true,
      appointmentId: appointmentId,
    );
    _conversations.add(conv);
    _messages[convId] = [
      ChatMessage(
        messageId: 'sys_${now.microsecondsSinceEpoch}',
        conversationId: convId,
        senderId: systemSenderId,
        text: systemText,
        timestamp: now,
        isRead: false,
      ),
    ];
    notifyListeners();
    return conv;
  }

  void sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final conv = conversationById(conversationId);
    if (conv == null || !conv.appointmentAccepted) return;

    final now = DateTime.now();
    final msg = ChatMessage(
      messageId: 'm_${now.microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: senderId,
      text: trimmed,
      timestamp: now,
    );
    _messages.putIfAbsent(conversationId, () => []).add(msg);

    final i = _conversations.indexWhere((c) => c.conversationId == conversationId);
    final isPatient = senderId == conv.patientId;
    _conversations[i] = conv.copyWith(
      lastMessage: trimmed,
      lastMessageTime: now,
      unreadCountPatient: isPatient ? conv.unreadCountPatient : conv.unreadCountPatient + 1,
      unreadCountDoctor: isPatient ? conv.unreadCountDoctor + 1 : conv.unreadCountDoctor,
    );
    notifyListeners();
  }

  void markRead({
    required String conversationId,
    required String userId,
    required String role,
  }) {
    final conv = conversationById(conversationId);
    if (conv == null) return;

    final msgs = _messages[conversationId];
    if (msgs != null) {
      for (var i = 0; i < msgs.length; i++) {
        if (msgs[i].senderId != userId && !msgs[i].isRead) {
          msgs[i] = ChatMessage(
            messageId: msgs[i].messageId,
            conversationId: msgs[i].conversationId,
            senderId: msgs[i].senderId,
            text: msgs[i].text,
            timestamp: msgs[i].timestamp,
            isRead: true,
          );
        }
      }
    }

    final i = _conversations.indexWhere((c) => c.conversationId == conversationId);
    _conversations[i] = conv.copyWith(
      unreadCountPatient: role == 'patient' ? 0 : conv.unreadCountPatient,
      unreadCountDoctor: role == 'doctor' ? 0 : conv.unreadCountDoctor,
    );
    notifyListeners();
  }

  /// Pull confirmed appointments from Firestore and ensure a chat exists for each.
  Future<void> syncAcceptedAppointmentsFromFirestore({
    required String userId,
    required String role,
  }) async {
    if (!FirebaseService.isInitialized || userId.isEmpty) return;
    try {
      if (role == 'doctor') {
        final docs = await FirebaseService.getAppointmentsForDoctor(userId).first;
        for (final d in docs) {
          _ensureFromAppointmentDoc(d.id, d.data());
        }
      } else {
        final snap = await FirebaseService.getAppointments(userId).first;
        for (final d in snap.docs) {
          _ensureFromAppointmentDoc(d.id, d.data());
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('ChatService.syncAcceptedAppointmentsFromFirestore: $e');
    }
  }

  void _ensureFromAppointmentDoc(String appointmentId, Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (status != 'confirmed' && status != 'accepted') return;

    final patientId = (data['userId'] ?? '').toString();
    final doctorId = (data['doctorId'] ?? data['doctorID'] ?? '').toString();
    if (patientId.isEmpty || doctorId.isEmpty) return;

    ensureConversationAfterAccept(
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: (data['patientName'] ?? 'Patient').toString(),
      doctorName: (data['doctorName'] ?? 'Doctor').toString(),
      date: data['date']?.toString(),
      timeSlot: (data['timeSlot'] ?? data['time'])?.toString(),
    );
  }

  static String _conversationIdFor(String patientId, String doctorId, String appointmentId) {
    return 'appt_${appointmentId}_${patientId}_$doctorId';
  }

  /// Demo threads when no Firestore-backed chats exist yet (local only).
  void seedDemoConversationsIfEmpty({
    required String userId,
    required String role,
  }) {
    if (userId.isEmpty) return;
    if (conversationsForUser(userId: userId, role: role).isNotEmpty) return;

    if (role == 'doctor') {
      _seedOne(
        appointmentId: 'demo_appt_1',
        patientId: 'demo_patient_1',
        doctorId: userId,
        patientName: 'Sarah Khan',
        doctorName: 'You',
        patientMessage: 'Hello Doctor, I have a question about my scan results.',
        doctorReply: 'Hi Sarah, I reviewed your report — we can discuss at your appointment.',
      );
      _seedOne(
        appointmentId: 'demo_appt_2',
        patientId: 'demo_patient_2',
        doctorId: userId,
        patientName: 'Ali Ahmed',
        doctorName: 'You',
        patientMessage: 'Can I reschedule to next week?',
        doctorReply: null,
      );
    } else {
      _seedOne(
        appointmentId: 'demo_appt_1',
        patientId: userId,
        doctorId: 'demo_doctor_1',
        patientName: 'You',
        doctorName: 'Dr. Hassan Malik',
        patientMessage: 'Thank you for accepting my appointment.',
        doctorReply: 'You are welcome. Message me if you have any questions before the visit.',
      );
      _seedOne(
        appointmentId: 'demo_appt_2',
        patientId: userId,
        doctorId: 'demo_doctor_2',
        patientName: 'You',
        doctorName: 'Dr. Ayesha Noor',
        patientMessage: 'Is the clinic open on Saturday?',
        doctorReply: 'Yes, Saturday hours are 10 AM – 2 PM.',
      );
    }
    notifyListeners();
  }

  void _seedOne({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String patientName,
    required String doctorName,
    required String patientMessage,
    String? doctorReply,
  }) {
    final conv = ensureConversationAfterAccept(
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: patientName,
      doctorName: doctorName,
      date: '2026-05-22',
      timeSlot: '10:00 AM',
    );
    sendMessage(
      conversationId: conv.conversationId,
      senderId: patientId,
      text: patientMessage,
    );
    if (doctorReply != null && doctorReply.trim().isNotEmpty) {
      sendMessage(
        conversationId: conv.conversationId,
        senderId: doctorId,
        text: doctorReply,
      );
    }
  }
}
