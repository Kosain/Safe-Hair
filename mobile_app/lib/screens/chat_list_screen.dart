import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';
import '../models/chat_models.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';
import '../widgets/doctor_chat_shell.dart';
import '../widgets/patient_web_scaffold.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _syncing = true;

  @override
  void initState() {
    super.initState();
    ChatService.instance.addListener(_onChatChanged);
    _sync();
  }

  @override
  void dispose() {
    ChatService.instance.removeListener(_onChatChanged);
    super.dispose();
  }

  void _onChatChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId ?? '';
    final role = auth.role;
    if (mounted) setState(() => _syncing = true);
    if (uid.isNotEmpty) {
      await ChatService.instance.syncAcceptedAppointmentsFromFirestore(
        userId: uid,
        role: role,
      );
      if (!FirebaseService.isInitialized) {
        ChatService.instance.seedDemoConversationsIfEmpty(
          userId: uid,
          role: role,
        );
      }
    }
    if (mounted) setState(() => _syncing = false);
  }

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) {
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ap';
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.userId ?? '';
    final role = auth.role;
    final isDoctor = role == 'doctor';
    final service = ChatService.instance;
    final conversations = uid.isEmpty
        ? const <ChatConversation>[]
        : service.conversationsForUser(userId: uid, role: role);

    Widget listContent;
    if (_syncing) {
      listContent = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    } else if (conversations.isEmpty) {
      listContent = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t('no_chats_patient'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: context.sh.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 16),
              _RefreshChatsButton(syncing: _syncing, onPressed: _sync),
            ],
          ),
        ),
      );
    } else {
      listContent = ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final c = conversations[index];
          final otherName = service.otherParticipantName(c, role: role);
          final unread = service.unreadForUser(c, role: role);
          return _ConversationTile(
            otherName: otherName,
            lastMessage: c.lastMessage,
            timeLabel: _formatTime(c.lastMessageTime),
            unreadCount: unread,
            onTap: () => context.push(
              '/chat/${c.conversationId}',
              extra: otherName,
            ),
          );
        },
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Text(
            context.t('my_chats'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.sh.textPrimary,
            ),
          ),
        ),
        listContent,
      ],
    );

    if (isDoctor) {
      return DoctorChatShell(
        currentPath: GoRouterState.of(context).matchedLocation,
        child: Container(
          color: context.sh.card,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    context.t('my_chats'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: context.sh.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: _syncing
                      ? Center(
                          child: CircularProgressIndicator(color: context.sh.textPrimary),
                        )
                      : conversations.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      context.t('no_chats_doctor'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: context.sh.textSecondary,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _RefreshChatsButton(syncing: _syncing, onPressed: _sync),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: conversations.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = conversations[index];
                                final otherName = service.otherParticipantName(c, role: role);
                                return _ConversationTile(
                                  otherName: otherName,
                                  lastMessage: c.lastMessage,
                                  timeLabel: _formatTime(c.lastMessageTime),
                                  unreadCount: service.unreadForUser(c, role: role),
                                  onTap: () => context.push(
                                    '/chat/${c.conversationId}',
                                    extra: otherName,
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PatientWebScaffold(
      currentRoute: '/chat-list',
      backgroundColor: context.sh.card,
      extraScrollBottomPadding: 88,
      body: body,
    );
  }
}

class _RefreshChatsButton extends StatelessWidget {
  const _RefreshChatsButton({required this.syncing, required this.onPressed});

  final bool syncing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return OutlinedButton.icon(
      onPressed: syncing ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: sh.textPrimary,
        disabledForegroundColor: sh.textSecondary,
        backgroundColor: sh.card,
        side: BorderSide(color: sh.textPrimary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Refresh chats'),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.otherName,
    required this.lastMessage,
    required this.timeLabel,
    required this.unreadCount,
    required this.onTap,
  });

  final String otherName;
  final String lastMessage;
  final String timeLabel;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = lastMessage.length > 56 ? '${lastMessage.substring(0, 56)}…' : lastMessage;

    final sh = context.sh;
    return Material(
      color: sh.card,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFEFEFEF),
                child: Icon(Icons.person_outline, color: Colors.grey.shade700, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: sh.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          timeLabel,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: sh.textSecondary),
                    ),
                  ],
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
