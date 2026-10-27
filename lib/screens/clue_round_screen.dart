import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/game_providers.dart';
import '../widgets/countdown_timer.dart';

class ClueRoundScreen extends ConsumerStatefulWidget {
  const ClueRoundScreen({super.key});

  @override
  ConsumerState<ClueRoundScreen> createState() => _ClueRoundScreenState();
}

class _ClueRoundScreenState extends ConsumerState<ClueRoundScreen> {
  final TextEditingController _clueController = TextEditingController();

  void _handleSubmitClue() {
    final clue = _clueController.text.trim();
    if (clue.isEmpty) return;

    if (clue.contains(' ')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clue must be a single word with no spaces!'),
        ),
      );
      return;
    }

    ref.read(gameClientProvider).submitClue(clue);
    _clueController.clear();
  }

  @override
  void dispose() {
    _clueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomStateProvider).value;

    if (roomState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isMyTurn = roomState.isMyTurn;
    final activePlayerName = roomState.players
        .firstWhere(
          (p) => p.id == roomState.currentTurnPlayerId,
          orElse: () => roomState.players.first,
        )
        .name;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Clue Round ${roomState.roundIndex} of ${roomState.settings.clueRounds}',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Turn indicator & countdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isMyTurn
                      ? AppTheme.accent.withAlpha(35)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isMyTurn ? AppTheme.accent : AppTheme.border,
                    width: isMyTurn ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isMyTurn
                          ? Icons.stars_rounded
                          : Icons.hourglass_top_rounded,
                      color: isMyTurn
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMyTurn
                                ? "IT'S YOUR TURN!"
                                : "$activePlayerName's Turn",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isMyTurn ? AppTheme.accent : Colors.white,
                            ),
                          ),
                          Text(
                            isMyTurn
                                ? 'Say your clue out loud and type it'
                                : 'Listening for their clue...',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CountdownTimerWidget(
                      deadlineEpochMs: roomState.deadlineEpochMs,
                      label: '',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Clues list title
              const Text(
                'CLUES SUBMITTED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              // Clues feed
              Expanded(
                child: roomState.clues.isEmpty
                    ? Center(
                        child: Text(
                          'No clues yet. First player is thinking...',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withAlpha(150),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: roomState.clues.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final c = roomState.clues[idx];
                          final author = roomState.players
                              .firstWhere(
                                (p) => p.id == c.playerId,
                                orElse: () => roomState.players.first,
                              )
                              .name;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: AppTheme.primary.withAlpha(
                                    50,
                                  ),
                                  child: Text(
                                    '${c.roundIndex}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryLight,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    author,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    c.word,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),

              // Clue submission box (active only when it's my turn)
              if (isMyTurn) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.accent),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _clueController,
                          maxLength: 20,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Enter 1-word clue (no spaces)',
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                          ),
                          onSubmitted: (_) => _handleSubmitClue(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                        ),
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.black,
                        ),
                        onPressed: _handleSubmitClue,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Waiting for $activePlayerName to give their clue...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
