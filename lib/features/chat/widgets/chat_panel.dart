import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../models/chat_models.dart';
import '../providers/chat_controller.dart';
import 'chat_restaurant_card.dart';
import 'chat_text.dart';

/// The conversation: header, messages with their restaurant cards, and the input. One implementation for the website
/// and the phone apps ([ChatOverlay] only decides where it sits).
class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key, required this.onMinimize, required this.onClose});

  final VoidCallback onMinimize;
  final VoidCallback onClose;

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || ref.read(chatControllerProvider).busy) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    ref.listen(
      chatControllerProvider.select((s) => (s.messages.length, s.busy)),
      (_, _) => _toEnd(),
    );
    final chat = ref.watch(chatControllerProvider);
    final last = chat.messages.isEmpty ? null : chat.messages.last;
    final showMore =
        chat.hasMore && !chat.busy && last != null && last.hits.isNotEmpty;

    return Column(
      children: [
        _Header(onMinimize: widget.onMinimize, onClose: widget.onClose),
        Divider(height: 1, color: p.border),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            children: [
              if (chat.messages.isEmpty)
                _Bubble(text: l10n.chatWelcome, assistant: true, avatar: true),
              for (var i = 0; i < chat.messages.length; i++)
                _MessageView(
                  key: ValueKey('chat-msg-${chat.messages[i].id}'),
                  message: chat.messages[i],
                  onRetry: ref.read(chatControllerProvider.notifier).retry,
                ),
              if (chat.busy) const _Typing(),
              if (showMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton.icon(
                      key: const ValueKey('chat-more'),
                      onPressed: ref
                          .read(chatControllerProvider.notifier)
                          .showMore,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l10n.chatShowMore),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Text(
            l10n.chatFootnote,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: p.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: kChatMaxMessageChars,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.chatInputHint,
                    filled: true,
                    fillColor: p.surfaceAlt,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('chat-send'),
                tooltip: l10n.chatSend,
                onPressed: chat.busy || _input.text.trim().isEmpty
                    ? null
                    : _send,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.onMinimize, required this.onClose});

  final VoidCallback onMinimize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final started = ref.watch(
      chatControllerProvider.select((s) => s.messages.isNotEmpty),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          _Avatar(size: 38, color: p.accentSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chatTitle,
                  style: AppText.title.copyWith(fontSize: 16),
                ),
                Text(
                  l10n.chatSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (started)
            IconButton(
              key: const ValueKey('chat-new'),
              tooltip: l10n.chatNewChat,
              onPressed: ref.read(chatControllerProvider.notifier).reset,
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            key: const ValueKey('chat-minimize'),
            tooltip: l10n.chatMinimize,
            onPressed: onMinimize,
            icon: const Icon(Icons.remove_rounded),
          ),
          IconButton(
            key: const ValueKey('chat-close'),
            tooltip: l10n.chatCloseClear,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * 0.1),
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: Image.asset(
      AppAssets.mascotSearching,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}

class _MessageView extends StatelessWidget {
  const _MessageView({super.key, required this.message, required this.onRetry});

  final ChatMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (message.role == ChatRole.user) {
      return _Bubble(text: message.text ?? '', assistant: false);
    }
    final paragraphs = [
      if (message.text != null && message.text!.isNotEmpty) message.text!,
      for (final n in message.notes) chatNoteText(l10n, n),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (paragraphs.isNotEmpty)
          _Bubble(
            text: paragraphs.join('\n'),
            assistant: true,
            avatar: true,
            error: message.failed,
            onRetry: message.failed ? onRetry : null,
          ),
        for (final hit in message.hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 34),
            child: ChatRestaurantCard(
              key: ValueKey('chat-hit-${message.id}-${hit.id}'),
              hit: hit,
              initiallyExpanded: message.expand.contains(hit.id),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.assistant,
    this.avatar = false,
    this.error = false,
    this.onRetry,
  });

  final String text;
  final bool assistant;
  final bool avatar;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final bg = assistant
        ? (error ? p.error.withValues(alpha: 0.10) : p.surfaceAlt)
        : scheme.primary;
    final fg = assistant ? p.textPrimary : scheme.onPrimary;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(assistant ? 4 : 18),
      bottomRight: Radius.circular(assistant ? 18 : 4),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: assistant
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (assistant && avatar) ...[
            _Avatar(size: 26, color: p.accentSoft),
            const SizedBox(width: 8),
          ] else if (assistant)
            const SizedBox(width: 34),
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(color: bg, borderRadius: radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      text,
                      style: TextStyle(fontSize: 14, height: 1.4, color: fg),
                    ),
                    if (onRetry != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton.icon(
                          key: const ValueKey('chat-retry'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(context.l10n.commonRetry),
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

/// Three dots that rise in turn: "the assistant is writing".
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: context.l10n.chatThinking,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            _Avatar(size: 26, color: p.accentSoft),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                          child: Opacity(
                            opacity:
                                0.35 +
                                0.65 *
                                    math.max(
                                      0,
                                      math.sin(
                                        (_c.value - i * 0.16) * 2 * math.pi,
                                      ),
                                    ),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: p.textSecondary,
                                shape: BoxShape.circle,
                              ),
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
      ),
    );
  }
}
