import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/ai_models.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../../care/care_controller.dart';
import '../ai_service.dart';
import '../chat_repository.dart';
import '../pet_context_builder.dart';
import 'chat_history_screen.dart';
import 'vet_summary_screen.dart';

/// The PetMate AI assistant.
///
/// Every answer is grounded in the current pet's real records: the context
/// block built by [PetContextBuilder] is sent with the conversation, and the
/// statistics inside it were computed on-device. The assistant is explicitly
/// not a veterinarian — clinical requests are intercepted by the safety layer
/// before they ever reach a model.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  AiService? _ai;
  ChatRepository? _chats;

  String? _sessionId;
  bool _sending = false;
  bool _starting = false;

  static const List<({String label, String prompt, IconData icon})> _suggestions =
      <({String label, String prompt, IconData icon})>[
    (
      label: 'Due today',
      prompt: 'What care activities are due today?',
      icon: Icons.today_rounded,
    ),
    (
      label: 'This week',
      prompt: 'What happened this week?',
      icon: Icons.date_range_rounded,
    ),
    (
      label: 'Did I miss anything?',
      prompt: 'Did I miss anything today?',
      icon: Icons.rule_rounded,
    ),
    (
      label: 'Coming up',
      prompt: 'What is coming up?',
      icon: Icons.event_rounded,
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? uid = context.read<AuthController>().uid;
    if (uid != null && _ai == null) {
      _ai = AiService(uid: uid);
      _chats = ChatRepository(uid);
    }
  }

  Future<String?> _ensureSession(CareController care) async {
    if (_sessionId != null) return _sessionId;
    final ChatRepository? chats = _chats;
    if (chats == null) return null;

    setState(() => _starting = true);
    try {
      final ChatSession session = await chats.createSession(
        petId: care.pet.id,
        petName: care.pet.name,
      );
      if (!mounted) return null;
      setState(() {
        _sessionId = session.id;
        _starting = false;
      });
      return session.id;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _starting = false);
      showAppSnack(context, 'Could not start the conversation.', isError: true);
      return null;
    }
  }

  Future<void> _send(String text, CareController care) async {
    final String question = text.trim();
    if (question.isEmpty || _sending) return;

    final AiService? ai = _ai;
    final ChatRepository? chats = _chats;
    final PetContext? petContext = care.context;

    if (ai == null || chats == null || petContext == null) return;

    final String? sessionId = await _ensureSession(care);
    if (sessionId == null) return;

    // Creating the session is a Firestore round-trip, during which the screen
    // can be torn down — signing out unwinds the stack, for instance. Touching
    // state after that would throw.
    if (!mounted) return;

    _input.clear();
    setState(() => _sending = true);

    // The user's own turn is written first so it appears immediately and
    // survives even if the model call subsequently fails.
    final ChatMessage userMessage = ChatMessage(
      id: '',
      role: ChatRole.user,
      text: question,
      createdAt: DateTime.now(),
    );

    try {
      await chats.addMessage(sessionId, userMessage);
      _scrollToEnd();

      final List<ChatMessage> history = await chats
          .watchMessages(sessionId)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => <ChatMessage>[]);

      final AiResult result = await ai.chat(
        question: question,
        petName: care.pet.name,
        context: petContext,
        // Exclude the message just sent; it is passed separately as the prompt.
        history: history.where((ChatMessage m) => m.text != question).toList(),
      );

      await chats.addMessage(
        sessionId,
        ChatMessage(
          id: '',
          role: ChatRole.assistant,
          text: result.text,
          createdAt: DateTime.now(),
          provider: result.provider,
        ),
      );

      if (history.length <= 1) {
        await chats.titleFromFirstMessage(sessionId, question);
      }
    } on AiException catch (e) {
      await chats.addMessage(
        sessionId,
        ChatMessage(
          id: '',
          role: ChatRole.assistant,
          text: e.message,
          createdAt: DateTime.now(),
          isError: true,
        ),
      );
    } catch (e) {
      await chats.addMessage(
        sessionId,
        ChatMessage(
          id: '',
          role: ChatRole.assistant,
          text: 'Something went wrong. Please try again.',
          createdAt: DateTime.now(),
          isError: true,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _newConversation() {
    setState(() => _sessionId = null);
    _input.clear();
    _inputFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppTheme.gapLg,
        title: Row(
          children: <Widget>[
            const PetMateMark(size: 30),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text('PetMate AI', style: TextStyle(fontSize: 17)),
                  Text(
                    'About ${care.pet.name}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VetSummaryScreen()),
            ),
            icon: const Icon(Icons.summarize_outlined),
            tooltip: 'Vet visit summary',
          ),
          IconButton(
            onPressed: () async {
              final String? id = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => const ChatHistoryScreen(),
                ),
              );
              if (id != null && mounted) setState(() => _sessionId = id);
            },
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Conversation history',
          ),
          IconButton(
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New conversation',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (!AppConfig.aiConfigured)
              Padding(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                child: InlineNotice(
                  message:
                      'AI features are not configured in this build. Your care '
                      'records and on-device statistics still work normally.',
                ),
              ),
            Expanded(
              child: _sessionId == null
                  ? _Welcome(
                      care: care,
                      suggestions: _suggestions,
                      onPick: (String prompt) => _send(prompt, care),
                      starting: _starting,
                    )
                  : _MessageList(
                      sessionId: _sessionId!,
                      chats: _chats!,
                      scroll: _scroll,
                      sending: _sending,
                      petName: care.pet.name,
                    ),
            ),
            _Composer(
              controller: _input,
              focusNode: _inputFocus,
              enabled: !_sending && care.context != null,
              onSend: (String text) => _send(text, care),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================== welcome

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.care,
    required this.suggestions,
    required this.onPick,
    required this.starting,
  });

  final CareController care;
  final List<({String label, String prompt, IconData icon})> suggestions;
  final ValueChanged<String> onPick;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    if (starting) return const LoadingView(message: 'Starting a conversation…');

    return ListView(
      padding: const EdgeInsets.all(AppTheme.gapXl),
      children: <Widget>[
        const SizedBox(height: AppTheme.gapXl),
        const Center(child: PetMateMark(size: 84, elevated: true)),
        const SizedBox(height: AppTheme.gapXl),
        Text(
          'Ask about ${care.pet.name}',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.gapSm),
        Text(
          'I can answer from ${care.pet.name}\'s actual records — feeding, '
          'activity, medication, vaccinations and vet visits.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTheme.gapXxl),

        ...suggestions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
              child: AppCard(
                onTap: () => onPick(s.prompt),
                child: Row(
                  children: <Widget>[
                    CareIconTile(
                      icon: s.icon,
                      color: AppColors.navy,
                      size: 36,
                    ),
                    const SizedBox(width: AppTheme.gapMd),
                    Expanded(
                      child: Text(
                        s.prompt,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const Icon(Icons.arrow_outward_rounded,
                        size: 17, color: AppColors.inkFaint),
                  ],
                ),
              ),
            )),

        const SizedBox(height: AppTheme.gapLg),
        Container(
          padding: const EdgeInsets.all(AppTheme.gapMd),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: Text(
                  'PetMate AI is a care assistant, not a veterinarian. It cannot '
                  'diagnose conditions or advise on medication.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================== message list

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.sessionId,
    required this.chats,
    required this.scroll,
    required this.sending,
    required this.petName,
  });

  final String sessionId;
  final ChatRepository chats;
  final ScrollController scroll;
  final bool sending;
  final String petName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatMessage>>(
      stream: chats.watchMessages(sessionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView();
        }

        final List<ChatMessage> messages =
            snapshot.data ?? const <ChatMessage>[];

        return ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.all(AppTheme.gapLg),
          itemCount: messages.length + (sending ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= messages.length) return const _TypingBubble();
            return _MessageBubble(message: messages[i]);
          },
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...<Widget>[
            const PetMateMark(size: 28),
            const SizedBox(width: AppTheme.gapSm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.gapLg,
                    vertical: AppTheme.gapMd,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColors.navy
                        : message.isError
                            ? AppColors.danger.withValues(alpha: 0.08)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppTheme.radiusMd),
                      topRight: const Radius.circular(AppTheme.radiusMd),
                      bottomLeft: Radius.circular(isUser ? AppTheme.radiusMd : 4),
                      bottomRight: Radius.circular(isUser ? 4 : AppTheme.radiusMd),
                    ),
                    border: isUser
                        ? null
                        : Border.all(
                            color: message.isError
                                ? AppColors.danger.withValues(alpha: 0.3)
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                  ),
                  child: SelectableText(
                    message.text,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: isUser
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (!isUser && message.provider != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      message.provider == AiProvider.local
                          ? 'Safety response · on-device'
                          : message.provider!.label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
      child: Row(
        children: <Widget>[
          const PetMateMark(size: 28),
          const SizedBox(width: AppTheme.gapSm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.gapLg,
              vertical: AppTheme.gapMd + 2,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMd),
                topRight: Radius.circular(AppTheme.radiusMd),
                bottomRight: Radius.circular(AppTheme.radiusMd),
                bottomLeft: Radius.circular(4),
              ),
              border:
                  Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const SizedBox(
              width: 34,
              height: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _Dot(delay: 0),
                  _Dot(delay: 180),
                  _Dot(delay: 360),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});

  final int delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.inkFaint,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ================================================================= composer

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapLg,
        AppTheme.gapSm,
        AppTheme.gapLg,
        AppTheme.gapMd,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? onSend : null,
              decoration: InputDecoration(
                hintText: enabled ? 'Ask about your pet…' : 'Loading…',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.gapLg,
                  vertical: AppTheme.gapMd,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  borderSide: const BorderSide(color: AppColors.navy, width: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.gapSm),
          Material(
            color: enabled ? AppColors.navy : AppColors.inkFaint,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? () => onSend(controller.text) : null,
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
