import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/game_providers.dart';
import '../widgets/countdown_timer.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  final TextEditingController _guessController = TextEditingController();

  void _handleSubmitGuess() {
    final word = _guessController.text.trim();
    if (word.isEmpty) return;
    ref.read(gameClientProvider).submitImpostorGuess(word);
    _guessController.clear();
  }

  @override
  void dispose() {
    _guessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomStateProvider).value;
    final isHost = ref.watch(isHostProvider);
    final client = ref.read(gameClientProvider);

    if (roomState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final phase = roomState.phase;

    // Phase: IMPOSTOR_GUESS
    if (phase == 'IMPOSTOR_GUESS') {
      final isCaughtImpostor = roomState.caughtImpostorId == roomState.myId;

      return Scaffold(
        appBar: AppBar(
          title: const Text('Impostor Last Chance'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: CountdownTimerWidget(
                    deadlineEpochMs: roomState.deadlineEpochMs,
                    label: 'Guess Time',
                  ),
                ),
                const SizedBox(height: 30),
                if (isCaughtImpostor) ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.impostorBackground,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppTheme.impostorColor,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.psychology_alt_rounded,
                          size: 56,
                          color: AppTheme.impostorColor,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'YOU WERE CAUGHT!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.impostorColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'You have ONE chance to steal the victory. Guess the secret word:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _guessController,
                          textCapitalization: TextCapitalization.words,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Enter secret word',
                          ),
                          onSubmitted: (_) => _handleSubmitGuess(),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.impostorColor,
                          ),
                          onPressed: _handleSubmitGuess,
                          child: const Text('Steal Victory!'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Column(
                      children: [
                        CircularProgressIndicator(color: AppTheme.accent),
                        SizedBox(height: 24),
                        Text(
                          'Impostor Was Caught!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'The impostor is now attempting to guess the secret word...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Phase: ROUND_END
    final result = roomState.roundResult;
    final outcome = result?.outcome ?? '';
    final isCrewWin = outcome == 'CREW_WIN';
    final isSteal = outcome == 'IMPOSTOR_STEAL_WIN';

    final outcomeColor = isCrewWin
        ? AppTheme.crewColor
        : (isSteal ? AppTheme.accent : AppTheme.impostorColor);
    final outcomeTitle = isCrewWin
        ? 'CREW VICTORY! 👨‍🚀'
        : (isSteal ? 'IMPOSTOR STOLE THE WIN! 🕵️' : 'IMPOSTOR VICTORY! 🕵️');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Round Results'),
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
              // Outcome Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: outcomeColor.withAlpha(35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: outcomeColor, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      outcomeTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: outcomeColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (result != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Secret Word: ',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            result.secretWord,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Category: ',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            result.category,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Leaderboard Title
              const Text(
                'SCOREBOARD',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              // Leaderboard list
              Expanded(
                child: ListView.separated(
                  itemCount: roomState.players.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final p = roomState.players[idx];
                    final isImpostor =
                        result?.impostorIds.contains(p.id) ?? false;
                    final delta = result?.scoreDelta[p.id] ?? 0;
                    final totalScore = result?.scores[p.id] ?? p.score;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isImpostor
                              ? AppTheme.impostorColor.withAlpha(80)
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: isImpostor
                                ? AppTheme.impostorColor.withAlpha(40)
                                : AppTheme.crewColor.withAlpha(40),
                            child: Icon(
                              isImpostor
                                  ? Icons.visibility_off_rounded
                                  : Icons.shield_rounded,
                              size: 16,
                              color: isImpostor
                                  ? AppTheme.impostorColor
                                  : AppTheme.crewColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      p.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (isImpostor) ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        '[IMPOSTOR]',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.impostorColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (result?.votes[p.id] != null) ...[
                                  Text(
                                    'Voted for: ${roomState.players.firstWhere((pl) => pl.id == result?.votes[p.id], orElse: () => p).name}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$totalScore pts',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (delta > 0)
                                Text(
                                  '+$delta',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.crewColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Actions: Host Play Again & Leave
              if (isHost) ...[
                ElevatedButton(
                  onPressed: () => client.playAgain(),
                  child: const Text('Play Again'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton(
                onPressed: () => client.leaveRoom(),
                child: const Text('Leave Room'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
