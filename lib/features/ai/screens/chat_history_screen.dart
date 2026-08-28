import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/ai_models.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/auth_controller.dart';
import '../chat_repository.dart';

/// Past AI conversations. Selecting one returns its id to the assistant screen.
class ChatHistoryScreen extends StatelessWidget {
  const ChatHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? uid = context.read<AuthController>().uid;
    if (uid == null) return const SizedBox.shrink();

    final ChatRepository chats = ChatRepository(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Delete all conversations',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final bool ok = await confirmAction(
                context,
                title: 'Delete all conversations?',
                message:
                    'Every saved conversation and message will be permanently '
                    'removed. Your pet records are not affected.',
                confirmLabel: 'Delete all',
              );
              if (!ok) return;
              await chats.deleteAllSessions();
              if (context.mounted) {
                showAppSnack(context, 'All conversations deleted');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<ChatSession>>(
          stream: chats.watchSessions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingView();
            }
            if (snapshot.hasError) {
              return ErrorView(message: snapshot.error.toString());
            }

            final List<ChatSession> sessions =
                snapshot.data ?? const <ChatSession>[];

            if (sessions.isEmpty) {
              return const EmptyState(
                icon: Icons.forum_outlined,
                title: 'No conversations yet',
                message:
                    'Start chatting with PetMate AI to get personalised care '
                    'insights. Your conversations will appear here.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(AppTheme.gapLg),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppTheme.gapMd),
              itemBuilder: (context, i) {
                final ChatSession s = sessions[i];
                return AppCard(
                  onTap: () => Navigator.of(context).pop(s.id),
                  child: Row(
                    children: <Widget>[
                      const CareIconTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        color: AppColors.navy,
                        size: 38,
                      ),
                      const SizedBox(width: AppTheme.gapMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              s.title,
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              <String>[
                                if (s.petName != null) s.petName!,
                                '${s.messageCount} message${s.messageCount == 1 ? '' : 's'}',
                                _relative(s.updatedAt),
                              ].join(' · '),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            if (s.lastMessagePreview != null) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                s.lastMessagePreview!,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete conversation',
                        icon: const Icon(Icons.delete_outline_rounded, size: 19),
                        onPressed: () async {
                          final bool ok = await confirmAction(
                            context,
                            title: 'Delete conversation?',
                            message: '"${s.title}" will be permanently removed.',
                          );
                          if (!ok) return;
                          await chats.deleteSession(s.id);
                          if (context.mounted) {
                            showAppSnack(context, 'Conversation deleted');
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _relative(DateTime d) {
    final Duration diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}
