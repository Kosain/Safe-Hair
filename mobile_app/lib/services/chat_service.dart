import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'firebase_service.dart';

/// Chat backed by Firestore when available; both patient and doctor see the same thread in real time.
class ChatService extends ChangeNotifier {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const systemSenderId = ChatServiceIds.systemSenderId;

  final List<ChatConversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _conversationsSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _messageSubs = {};

  String? _listeningUserId;
  String? _listeningRole;

  List<ChatConversation> conversationsForUser({
    required String userId,
    required String role,
  }) {
    final list = _conversations.where((c) {
      if (!c.appointmentAccepted) return false;
      return c.patientId == userId || c.doctorId == userId;
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

  /// Subscribe to this user's conversation list (Firestore live updates).
  void startListeningConversations({
    required String userId,
    required String role,
    bool restart = false,
  }) {
    if (userId.isEmpty) return;
    if (!restart &&
        _listeningUserId == userId &&
        _listeningRole == role &&
        _conversationsSub != null) {
      return;
    }
    _conversationsSub?.cancel();
    _conversationsSub = null;
    _listeningUserId = userId;
    _listeningRole = role;

    if (!FirebaseService.isInitialized) {
      notifyListeners();
      return;
    }

    final stream = role == 'doctor'
        ? FirebaseService.chatConversationsForDoctorStream(userId)
        : FirebaseService.chatConversationsForPatientStream(userId);

    _conversationsSub = stream.listen(
      (snap) {
        final fromFirestore = snap.docs
            .map((d) => _conversationFromFirestore(d.id, d.data()))
            .where((c) => c.appointmentAccepted);
        final merged = <String, ChatConversation>{
          for (final c in _conversations)
            if (c.appointmentAccepted &&
                (_listeningUserId == null ||
                    c.patientId == _listeningUserId ||
                    c.doctorId == _listeningUserId))
              c.conversationId: c,
        };
        for (final c in fromFirestore) {
          merged[c.conversationId] = c;
        }
        _conversations
          ..clear()
          ..addAll(merged.values);
        notifyListeners();
      },
      onError: (e) {
        FirebaseService.lastChatSendError = FirebaseService.friendlyFirestoreError(e);
        debugPrint('ChatService conversations stream: $e');
      },
    );
  }

  /// Subscribe to messages in one thread (Firestore live updates).
  void startListeningMessages(String conversationId) {
    if (conversationId.isEmpty) return;
    _messageSubs[conversationId]?.cancel();
    _messageSubs.remove(conversationId);

    if (!FirebaseService.isInitialized) {
      notifyListeners();
      return;
    }

    unawaited(_hydrateMessagesFromFirestore(conversationId));

    _messageSubs[conversationId] = FirebaseService.chatMessagesStream(conversationId).listen(
      (snap) {
        _messages[conversationId] = snap.docs.map((d) => _messageFromFirestore(d.id, d.data())).toList();
        notifyListeners();
      },
      onError: (e) => debugPrint('ChatService messages stream: $e'),
    );
  }

  Future<void> _hydrateMessagesFromFirestore(String conversationId) async {
    final docs = await FirebaseService.getChatMessagesOnce(conversationId);
    if (docs.isEmpty) return;
    _messages[conversationId] = docs.map((d) => _messageFromFirestore(d.id, d.data())).toList();
    notifyListeners();
  }

  void stopListeningMessages(String conversationId) {
    _messageSubs.remove(conversationId)?.cancel();
  }

  /// Idempotent — call when doctor confirms an appointment.
  Future<ChatConversation> ensureConversationAfterAccept({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String patientName,
    required String doctorName,
    String? date,
    String? timeSlot,
  }) async {
    final convId = _conversationIdFor(patientId, doctorId, appointmentId);
    final dt = [date, timeSlot].where((e) => e != null && e.trim().isNotEmpty).join(' at ').trim();
    final systemText = dt.isEmpty
        ? 'Appointment confirmed. You can now message each other.'
        : 'Appointment confirmed on $dt. You can now message each other.';

    final pName = patientName.trim().isEmpty ? 'Patient' : patientName.trim();
    final dName = doctorName.trim().isEmpty ? 'Doctor' : doctorName.trim();

    if (FirebaseService.isInitialized) {
      var ok = await FirebaseService.ensureChatConversation(
        conversationId: convId,
        appointmentId: appointmentId,
        patientId: patientId,
        doctorId: doctorId,
        patientName: pName,
        doctorName: dName,
        systemMessageText: systemText,
      );
      if (!ok) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        ok = await FirebaseService.ensureChatConversation(
          conversationId: convId,
          appointmentId: appointmentId,
          patientId: patientId,
          doctorId: doctorId,
          patientName: pName,
          doctorName: dName,
          systemMessageText: systemText,
        );
      }
      if (!ok) {
        debugPrint('ensureConversationAfterAccept: Firestore chat create failed for $convId');
      }
      final verified = await FirebaseService.getChatConversationData(convId);
      if (verified != null) {
        final now = DateTime.now();
        final conv = _conversationFromFirestore(convId, verified).copyWith(appointmentAccepted: true);
        _upsertConversation(conv);
        _messages.putIfAbsent(convId, () => [
              ChatMessage(
                messageId: 'sys_local',
                conversationId: convId,
                senderId: systemSenderId,
                text: (verified['lastMessage'] ?? systemText).toString(),
                timestamp: FirebaseService.chatTimestampFromField(verified['lastMessageTime']) ?? now,
              ),
            ]);
        notifyListeners();
        return conv;
      }
      if (!ok) {
        return ChatConversation(
          conversationId: convId,
          patientId: patientId,
          doctorId: doctorId,
          patientName: pName,
          doctorName: dName,
          lastMessage: systemText,
          lastMessageTime: DateTime.now(),
          appointmentAccepted: false,
          appointmentId: appointmentId,
        );
      }
      final now = DateTime.now();
      final conv = ChatConversation(
        conversationId: convId,
        patientId: patientId,
        doctorId: doctorId,
        patientName: pName,
        doctorName: dName,
        lastMessage: systemText,
        lastMessageTime: now,
        appointmentAccepted: true,
        appointmentId: appointmentId,
      );
      final idx = _conversations.indexWhere((c) => c.conversationId == convId);
      if (idx >= 0) {
        _conversations[idx] = conv;
      } else {
        _conversations.add(conv);
      }
      _messages.putIfAbsent(convId, () => [
            ChatMessage(
              messageId: 'sys_local',
              conversationId: convId,
              senderId: systemSenderId,
              text: systemText,
              timestamp: now,
            ),
          ]);
      notifyListeners();
      return conv;
    }

    return _ensureConversationLocal(
      convId: convId,
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: pName,
      doctorName: dName,
      systemText: systemText,
    );
  }

  ChatConversation _ensureConversationLocal({
    required String convId,
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String patientName,
    required String doctorName,
    required String systemText,
  }) {
    final existing = conversationById(convId);
    if (existing != null) {
      if (!existing.appointmentAccepted) {
        final i = _conversations.indexWhere((c) => c.conversationId == convId);
        _conversations[i] = existing.copyWith(appointmentAccepted: true);
        notifyListeners();
      }
      return conversationById(convId)!;
    }

    final now = DateTime.now();
    final conv = ChatConversation(
      conversationId: convId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: patientName,
      doctorName: doctorName,
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
      ),
    ];
    notifyListeners();
    return conv;
  }

  /// Returns false if the message could not be sent (missing thread, Firestore error, etc.).
  Future<bool> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    var conv = conversationById(conversationId);
    if (FirebaseService.isInitialized && conv == null) {
      final data = await FirebaseService.getChatConversationData(conversationId);
      if (data != null) {
        conv = _conversationFromFirestore(conversationId, data);
        if (!_conversations.any((c) => c.conversationId == conversationId)) {
          _conversations.add(conv);
        }
      }
    }
    if (conv == null || !conv.appointmentAccepted) {
      conv = await _repairConversationForSend(conversationId, senderId: senderId) ?? conv;
    }
    if (conv == null || !conv.appointmentAccepted) {
      FirebaseService.lastChatSendError =
          'Messaging opens after the doctor confirms your appointment. Ask them to tap Accept, then open My Chats again.';
      debugPrint('ChatService.sendMessage: no accepted conversation for $conversationId');
      return false;
    }

    final now = DateTime.now();
    final localId = 'local_${now.microsecondsSinceEpoch}';
    final localMsg = ChatMessage(
      messageId: localId,
      conversationId: conversationId,
      senderId: senderId,
      text: trimmed,
      timestamp: now,
    );
    _applyLocalOutgoingMessage(conv: conv, conversationId: conversationId, msg: localMsg, trimmed: trimmed, now: now);

    if (FirebaseService.isInitialized) {
      var ready = await FirebaseService.getChatConversationData(conversationId) != null;
      if (!ready) {
        final apptId = conv.appointmentId ?? _parseConversationId(conversationId)?.appointmentId;
        if (apptId == null || apptId.isEmpty) {
          FirebaseService.lastChatSendError = 'Chat thread is not in the cloud yet. Open My Chats after the doctor confirms.';
        } else {
          ready = await FirebaseService.ensureChatConversation(
            conversationId: conversationId,
            appointmentId: apptId,
            patientId: conv.patientId,
            doctorId: conv.doctorId,
            patientName: conv.patientName,
            doctorName: conv.doctorName,
            systemMessageText: conv.lastMessage,
          );
        }
      }
      if (!ready) {
        _messages[conversationId]?.removeWhere((m) => m.messageId == localId);
        notifyListeners();
        return false;
      }
      final ok = await FirebaseService.sendChatMessage(
        conversationId: conversationId,
        senderId: senderId,
        text: trimmed,
        patientId: conv.patientId,
        doctorId: conv.doctorId,
        systemMessageFallback: conv.lastMessage,
        appointmentId: conv.appointmentId,
        patientDisplayName: conv.patientName,
        doctorDisplayName: conv.doctorName,
      );
      if (!ok) {
        debugPrint('ChatService.sendMessage: Firestore write failed');
        _messages[conversationId]?.removeWhere((m) => m.messageId == localId);
        notifyListeners();
        return false;
      }
      return true;
    }

    return true;
  }

  void _applyLocalOutgoingMessage({
    required ChatConversation conv,
    required String conversationId,
    required ChatMessage msg,
    required String trimmed,
    required DateTime now,
  }) {
    _messages.putIfAbsent(conversationId, () => []).add(msg);
    final i = _conversations.indexWhere((c) => c.conversationId == conversationId);
    final isPatient = msg.senderId == conv.patientId;
    if (i >= 0) {
      _conversations[i] = conv.copyWith(
        lastMessage: trimmed,
        lastMessageTime: now,
        unreadCountPatient: isPatient ? conv.unreadCountPatient : conv.unreadCountPatient + 1,
        unreadCountDoctor: isPatient ? conv.unreadCountDoctor + 1 : conv.unreadCountDoctor,
      );
    }
    notifyListeners();
  }

  Future<void> markRead({
    required String conversationId,
    required String userId,
    required String role,
  }) async {
    final conv = conversationById(conversationId);
    if (conv == null) return;

    if (FirebaseService.isInitialized) {
      await FirebaseService.markChatConversationRead(
        conversationId: conversationId,
        role: role,
      );
      return;
    }

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

  static bool _isBookedAppointmentStatus(String statusRaw) {
    final status = statusRaw.toLowerCase().trim();
    const blocked = {'cancelled', 'canceled', 'declined', 'rejected', 'pending', 'requested', 'waiting'};
    if (blocked.contains(status)) return false;
    if (status.isEmpty) return true;
    const ok = {'confirmed', 'accepted', 'approved', 'booked', 'active', 'scheduled'};
    if (ok.contains(status)) return true;
    return status.contains('confirm') || status.contains('accept');
  }

  static bool _doctorAppointmentEligibleForChat(String statusRaw) {
    final status = statusRaw.toLowerCase().trim();
    const blocked = {'cancelled', 'canceled', 'declined', 'rejected', 'pending', 'requested', 'waiting'};
    return !blocked.contains(status);
  }

  void _upsertConversation(ChatConversation conv) {
    if (!conv.appointmentAccepted) return;
    final idx = _conversations.indexWhere((c) => c.conversationId == conv.conversationId);
    if (idx >= 0) {
      _conversations[idx] = conv;
    } else {
      _conversations.add(conv);
    }
  }

  /// Pull confirmed appointments from Firestore and ensure a chat exists for each.
  Future<void> syncAcceptedAppointmentsFromFirestore({
    required String userId,
    required String role,
  }) async {
    if (!FirebaseService.isInitialized || userId.isEmpty) return;
    try {
      final appointmentDocs = role == 'doctor'
          ? await FirebaseService.getDoctorAppointmentsOnce(userId)
          : await FirebaseService.getPatientAppointmentsOnce(userId);

      final seenApptIds = <String>{};
      for (final d in appointmentDocs) {
        seenApptIds.add(d.id);
        await _ensureFromAppointmentDoc(
          d.id,
          d.data(),
          sessionUserId: userId,
          role: role,
        );
      }

      if (role == 'patient') {
        final fromNotifs = await FirebaseService.getConfirmedAppointmentIdsForPatient(userId);
        for (final apptId in fromNotifs) {
          if (seenApptIds.contains(apptId)) continue;
          final appt = await FirebaseService.getAppointmentOnce(apptId);
          if (appt == null) continue;
          seenApptIds.add(apptId);
          await _ensureFromAppointmentDoc(
            apptId,
            {...appt, 'status': 'confirmed'},
            sessionUserId: userId,
            role: role,
            treatAsConfirmed: true,
          );
        }
      }

      final convDocs = role == 'doctor'
          ? await FirebaseService.getChatConversationsForDoctorOnce(userId)
          : await FirebaseService.getChatConversationsForPatientOnce(userId);
      for (final d in convDocs) {
        final conv = _conversationFromFirestore(d.id, d.data()).copyWith(appointmentAccepted: true);
        _upsertConversation(conv);
      }

      notifyListeners();
      startListeningConversations(userId: userId, role: role, restart: true);
    } catch (e) {
      FirebaseService.lastChatSendError = FirebaseService.friendlyFirestoreError(e);
      debugPrint('ChatService.syncAcceptedAppointmentsFromFirestore: $e');
    }
  }

  Future<void> _ensureFromAppointmentDoc(
    String appointmentId,
    Map<String, dynamic> data, {
    required String sessionUserId,
    required String role,
    bool treatAsConfirmed = false,
  }) async {
    final status = (data['status'] ?? '').toString();
    if (!treatAsConfirmed && !_isBookedAppointmentStatus(status)) {
      if (role != 'doctor' || !_doctorAppointmentEligibleForChat(status)) return;
    }

    var patientId = (data['userId'] ?? data['patientId'] ?? data['uid'] ?? data['user_id'] ?? '')
        .toString()
        .trim();
    var doctorId =
        (data['doctorId'] ?? data['doctorID'] ?? data['doctor_id'] ?? '').toString().trim();
    if (role == 'patient') patientId = sessionUserId;
    if (role == 'doctor') doctorId = sessionUserId;
    if (patientId.isEmpty || doctorId.isEmpty) return;

    final dt = [data['date'], data['timeSlot'] ?? data['time']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' at ')
        .trim();
    final systemText = dt.isEmpty
        ? 'Appointment confirmed. You can now message each other.'
        : 'Appointment confirmed on $dt. You can now message each other.';

    final convId = _conversationIdFor(patientId, doctorId, appointmentId);
    _upsertConversation(
      ChatConversation(
        conversationId: convId,
        patientId: patientId,
        doctorId: doctorId,
        patientName: (data['patientName'] ?? data['patient_name'] ?? 'Patient').toString(),
        doctorName: (data['doctorName'] ?? data['doctor_name'] ?? 'Doctor').toString(),
        lastMessage: systemText,
        lastMessageTime: DateTime.now(),
        appointmentAccepted: true,
        appointmentId: appointmentId,
      ),
    );

    await ensureConversationAfterAccept(
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: (data['patientName'] ?? data['patient_name'] ?? 'Patient').toString(),
      doctorName: (data['doctorName'] ?? data['doctor_name'] ?? 'Doctor').toString(),
      date: data['date']?.toString(),
      timeSlot: (data['timeSlot'] ?? data['time'])?.toString(),
    );

    final stored = await FirebaseService.getChatConversationData(convId);
    if (stored != null) {
      _upsertConversation(_conversationFromFirestore(convId, stored).copyWith(appointmentAccepted: true));
    }
  }

  static String _conversationIdFor(String patientId, String doctorId, String appointmentId) {
    return 'appt_${appointmentId}_${patientId}_$doctorId';
  }

  /// Parses `appt_{appointmentId}_{patientId}_{doctorId}` when [appointmentId] was not stored on the doc.
  static ({String appointmentId, String patientId, String doctorId})? _parseConversationId(String conversationId) {
    if (!conversationId.startsWith('appt_')) return null;
    final body = conversationId.substring(5);
    final last = body.lastIndexOf('_');
    if (last <= 0) return null;
    final doctorId = body.substring(last + 1);
    final mid = body.substring(0, last);
    final second = mid.lastIndexOf('_');
    if (second <= 0) return null;
    final patientId = mid.substring(second + 1);
    final appointmentId = mid.substring(0, second);
    if (appointmentId.isEmpty || patientId.isEmpty || doctorId.isEmpty) return null;
    return (appointmentId: appointmentId, patientId: patientId, doctorId: doctorId);
  }

  Future<ChatConversation?> _repairConversationForSend(String conversationId, {required String senderId}) async {
    if (!FirebaseService.isInitialized) return null;
    final data = await FirebaseService.getChatConversationData(conversationId);
    if (data != null) {
      var conv = _conversationFromFirestore(conversationId, data);
      if (!conv.appointmentAccepted) {
        final parsed = _parseConversationId(conversationId);
        final apptId = conv.appointmentId ?? parsed?.appointmentId;
        if (apptId != null && apptId.isNotEmpty) {
          await ensureConversationAfterAccept(
            appointmentId: apptId,
            patientId: conv.patientId.isNotEmpty ? conv.patientId : (parsed?.patientId ?? ''),
            doctorId: conv.doctorId.isNotEmpty ? conv.doctorId : (parsed?.doctorId ?? ''),
            patientName: conv.patientName,
            doctorName: conv.doctorName,
          );
          conv = conversationById(conversationId) ?? conv;
        }
      }
      if (!_conversations.any((c) => c.conversationId == conversationId)) {
        _conversations.add(conv);
      }
      notifyListeners();
      return conv.appointmentAccepted ? conv : null;
    }

    final parsed = _parseConversationId(conversationId);
    if (parsed == null) return null;
    final rolePatient = senderId == parsed.patientId;
    final roleDoctor = senderId == parsed.doctorId;
    if (!rolePatient && !roleDoctor) return null;

    await ensureConversationAfterAccept(
      appointmentId: parsed.appointmentId,
      patientId: parsed.patientId,
      doctorId: parsed.doctorId,
      patientName: 'Patient',
      doctorName: 'Doctor',
    );
    final conv = conversationById(conversationId);
    return conv?.appointmentAccepted == true ? conv : null;
  }

  static bool _appointmentAcceptedFromMap(Map<String, dynamic> d) {
    if (!d.containsKey('appointmentAccepted')) return true;
    final v = d['appointmentAccepted'];
    if (v == true) return true;
    if (v is String && v.toLowerCase() == 'true') return true;
    return false;
  }

  ChatConversation _conversationFromFirestore(String docId, Map<String, dynamic> d) {
    final lastTime = FirebaseService.chatTimestampFromField(d['lastMessageTime']) ?? DateTime.now();
    return ChatConversation(
      conversationId: (d['conversationId'] ?? docId).toString(),
      patientId: (d['patientId'] ?? '').toString(),
      doctorId: (d['doctorId'] ?? '').toString(),
      patientName: (d['patientName'] ?? 'Patient').toString(),
      doctorName: (d['doctorName'] ?? 'Doctor').toString(),
      lastMessage: (d['lastMessage'] ?? '').toString(),
      lastMessageTime: lastTime,
      appointmentAccepted: _appointmentAcceptedFromMap(d),
      appointmentId: d['appointmentId']?.toString(),
      unreadCountPatient: (d['unreadCountPatient'] as num?)?.toInt() ?? 0,
      unreadCountDoctor: (d['unreadCountDoctor'] as num?)?.toInt() ?? 0,
    );
  }

  ChatMessage _messageFromFirestore(String docId, Map<String, dynamic> d) {
    return ChatMessage(
      messageId: (d['messageId'] ?? docId).toString(),
      conversationId: (d['conversationId'] ?? '').toString(),
      senderId: (d['senderId'] ?? '').toString(),
      text: (d['text'] ?? '').toString(),
      timestamp: FirebaseService.chatTimestampFromField(d['timestamp']) ?? DateTime.now(),
      isRead: d['isRead'] == true,
    );
  }

  /// Local-only demo when Firebase is unavailable.
  void seedDemoConversationsIfEmpty({
    required String userId,
    required String role,
  }) {
    if (FirebaseService.isInitialized) return;
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
    final conv = _ensureConversationLocal(
      convId: _conversationIdFor(patientId, doctorId, appointmentId),
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      patientName: patientName,
      doctorName: doctorName,
      systemText: 'Appointment confirmed. You can now message each other.',
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
