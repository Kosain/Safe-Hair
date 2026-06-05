import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../l10n/tr.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    this.otherUserName,
  });

  final String conversationId;
  final String? otherUserName;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ChatService.instance.addListener(_onChatChanged);
    ChatService.instance.startListeningMessages(widget.conversationId);
    _markRead();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    ChatService.instance.removeListener(_onChatChanged);
    ChatService.instance.stopListeningMessages(widget.conversationId);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _markRead() {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId ?? '';
    final role = auth.role;
    if (uid.isEmpty) return;
    ChatService.instance.markRead(
      conversationId: widget.conversationId,
      userId: uid,
      role: role,
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(max);
  }

  String _formatMessageTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final uid = context.read<AuthProvider>().userId ?? '';
    if (uid.isEmpty) return;

    final ok = await ChatService.instance.sendMessage(
      conversationId: widget.conversationId,
      senderId: uid,
      text: text,
    );
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      final detail = FirebaseService.lastChatSendError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            detail != null && detail.isNotEmpty
                ? 'Message could not be sent. $detail'
                : 'Message could not be sent. Ask the doctor to confirm the appointment, then open My Chats again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.userId ?? '';
    final role = auth.role;
    final sh = context.sh;
    final service = ChatService.instance;
    final conv = service.conversationById(widget.conversationId);
    final title = widget.otherUserName ??
        (conv != null ? service.otherParticipantName(conv, role: role) : 'Chat');
    final messages = service.messagesFor(widget.conversationId);

    return Scaffold(
      backgroundColor: sh.scaffold,
      appBar: AppBar(
        backgroundColor: sh.appBar,
        foregroundColor: sh.textPrimary,
        elevation: 0,
        surfaceTintColor: sh.appBar,
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: sh.textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: sh.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      context.t('send_message_start'),
                      style: TextStyle(color: sh.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      if (msg.isSystem) {
                        return _SystemBubble(
                          text: msg.text,
                          timeLabel: _formatMessageTime(msg.timestamp),
                        );
                      }
                      final isMine = msg.senderId == uid;
                      return _MessageBubble(
                        text: msg.text,
                        timeLabel: _formatMessageTime(msg.timestamp),
                        isMine: isMine,
                      );
                    },
                  ),
          ),
          Material(
            color: sh.card,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(color: sh.textPrimary),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: context.t('type_message'),
                          filled: true,
                          fillColor: sh.card,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: sh.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: sh.textPrimary),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: sh.selectedNavBg,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _send,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.send_rounded, color: sh.selectedNavFg, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.timeLabel,
    required this.isMine,
  });

  final String text;
  final String timeLabel;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? sh.selectedNavBg : sh.sidebarSelectedBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMine ? sh.selectedNavFg : sh.textPrimary,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeLabel,
              style: TextStyle(
                fontSize: 11,
                color: isMine ? sh.selectedNavFg.withValues(alpha: 0.7) : sh.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.text, required this.timeLabel});

  final String text;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        decoration: BoxDecoration(
          color: sh.sidebarSelectedBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sh.border),
        ),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: sh.textPrimary, height: 1.35),
            ),
            const SizedBox(height: 4),
            Text(
              timeLabel,
              style: TextStyle(fontSize: 10, color: sh.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
