import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/confirm_dialog.dart';
import '../../../../l10n/app_localizations.dart';
import '../../logic/chatbot_controller.dart';
import '../widgets/itinerary_card.dart';
import 'chat_history_screen.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _chatCtrl = ChatbotController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _chatCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _chatCtrl.isLoading) return;
    _msgCtrl.clear();
    await _chatCtrl.sendMessage(text);
    _scrollToBottom();
    if (!mounted) {
      return;
    }
    if (_chatCtrl.errorMessage != null) {
      AppSnackbar.error(context, _chatCtrl.errorMessage!);
    }
  }

  void _sendQuickPrompt(String prompt) {
    if (_chatCtrl.isLoading) return;
    _msgCtrl.text = prompt;
    _send();
  }

  Future<void> _clearChat() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showAppConfirmDialog(
      context,
      title: l10n.clearChatTitle,
      message: l10n.clearChatMessage,
    );
    if (ok) _chatCtrl.clearChat();
  }

  Future<void> _openHistory() async {
    final session = await Navigator.push<ChatSession>(
      context,
      MaterialPageRoute(builder: (_) => const ChatHistoryScreen()),
    );
    if (session != null) {
      _chatCtrl.loadSession(session);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    _chatCtrl.configure(
      isArabic: isArabic,
      welcomeText: l10n.chatbotWelcome,
      connectionErrorText: l10n.chatConnectionError,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.purpleGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.chatbotTitle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: AppColors.accentGreen, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(l10n.chatOnlineStatus,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.accentGreen)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.history_rounded),
              onPressed: _openHistory,
              tooltip: l10n.chatHistoryTooltip),
          IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _clearChat,
              tooltip: l10n.newChat),
        ],
      ),
      body: Column(
        children: [
          // ── Quick Prompts ────────────────────────────────────────────────
          ListenableBuilder(
            listenable: _chatCtrl,
            builder: (_, __) => _QuickPrompts(
              onTap: _sendQuickPrompt,
              isLoading: _chatCtrl.isLoading,
            ),
          ),

          // ── Messages ─────────────────────────────────────────────────────
          Expanded(
            child: ListenableBuilder(
              listenable: _chatCtrl,
              builder: (_, __) {
                final showTyping =
                    _chatCtrl.isLoading && !_chatCtrl.hasStreamedReply;
                final shouldFollowReply = !_scrollCtrl.hasClients ||
                    _scrollCtrl.position.extentAfter < 80;
                if (_chatCtrl.isLoading && shouldFollowReply) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollCtrl.hasClients && mounted) {
                      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                    }
                  });
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _chatCtrl.messages.length + (showTyping ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (showTyping && i == _chatCtrl.messages.length) {
                      return _TypingIndicator();
                    }
                    final msg = _chatCtrl.messages[i];
                    if (msg.isItinerary && msg.itineraryData != null) {
                      return ItineraryCard(
                        data: msg.itineraryData!,
                        isSaved: msg.isSavedItinerary,
                        onSave: () async {
                          try {
                            await _chatCtrl.saveItinerary(msg);
                            if (ctx.mounted) {
                              AppSnackbar.success(
                                ctx,
                                l10n.chatItinerarySavedSuccess,
                              );
                            }
                          } catch (_) {
                            if (ctx.mounted) {
                              AppSnackbar.error(
                                ctx,
                                l10n.chatItinerarySaveFailed,
                              );
                            }
                          }
                        },
                      );
                    }
                    return _MessageBubble(message: msg);
                  },
                );
              },
            ),
          ),

          // ── Input bar ────────────────────────────────────────────────────
          ListenableBuilder(
            listenable: _chatCtrl,
            builder: (_, __) => _ChatInputBar(
              controller: _msgCtrl,
              focusNode: _focusNode,
              isDark: isDark,
              isLoading: _chatCtrl.isLoading,
              onSend: _send,
              onCancel: _chatCtrl.cancelResponse,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _QuickPrompts extends StatelessWidget {
  final void Function(String) onTap;
  final bool isLoading;
  const _QuickPrompts({required this.onTap, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final prompts = <(String, String)>[
      (l10n.chatQuickPromptIstanbul, l10n.chatQuickPromptIstanbulText),
      (l10n.chatQuickPromptCheapest, l10n.chatQuickPromptCheapestText),
      (l10n.chatQuickPromptBudget, l10n.chatQuickPromptBudgetText),
    ];
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
            bottom: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.divider)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: prompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(
          child: GestureDetector(
            onTap: isLoading ? null : () => onTap(prompts[i].$2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Opacity(
                opacity: isLoading ? 0.5 : 1,
                child: Text(prompts[i].$1,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        gradient: isUser ? AppColors.primaryGradient : null,
        color: isUser ? null : (isDark ? AppColors.darkSurface : Colors.white),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        boxShadow: isUser
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color: isUser
              ? Colors.white
              : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble)
          .animate()
          .fade(duration: 200.ms)
          .slideX(begin: 0.05, end: 0);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 6, bottom: 2),
            decoration: const BoxDecoration(
                gradient: AppColors.purpleGradient, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 14),
          ),
          Flexible(child: bubble),
        ],
      ),
    ).animate().fade(duration: 200.ms).slideX(begin: -0.05, end: 0);
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(
                gradient: AppColors.purpleGradient, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 14),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurface
                  : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                  3,
                  (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            shape: BoxShape.circle),
                      )
                          .animate(onPlay: (c) => c.repeat())
                          .scale(
                            delay: Duration(milliseconds: 160 * i),
                            duration: const Duration(milliseconds: 480),
                            begin: const Offset(0.6, 0.6),
                            end: const Offset(1, 1),
                          )
                          .then()
                          .scale(
                              begin: const Offset(1, 1),
                              end: const Offset(0.6, 0.6))),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isLoading;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.isLoading,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
            top: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceSecondary
                      : AppColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).chatbotInputHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13),
                    filled: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: isLoading
                  ? AppLocalizations.of(context).cancel
                  : AppLocalizations.of(context).chatbotSend,
              onPressed: isLoading ? onCancel : onSend,
              style: IconButton.styleFrom(
                fixedSize: const Size(46, 46),
                padding: EdgeInsets.zero,
                backgroundColor:
                    isLoading ? AppColors.accentRed : AppColors.primary,
              ),
              icon: Icon(
                isLoading ? Icons.stop_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
