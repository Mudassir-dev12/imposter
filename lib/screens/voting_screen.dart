import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/game_providers.dart';
import '../widgets/countdown_timer.dart';

class VotingScreen extends ConsumerStatefulWidget {
  const VotingScreen({super.key});

  @override
  ConsumerState<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends ConsumerState<VotingScreen> {
  String? _selectedTargetId;
  bool _abstained = false;

  void _handleVote(String? targetId) {
    setState(() {
      _selectedTargetId = targetId;
      _abstained = targetId == null;
    });
    ref.read(gameClientProvider).castVote(targetId);
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomStateProvider).value;

    if (roomState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final myId = roomState.myId;
    final otherPlayers = roomState.players.where((p) => p.id != myId).toList();
    final prog = roomState.voteProgress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cast Your Secret Ballot'),
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
              // Vote progress & Timer banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_vote_rounded,
                      color: AppTheme.primaryLight,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'VOTING IN PROGRESS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '${prog.votedCount} of ${prog.total} Votes Cast',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

              const Text(
                'SELECT SUSPECT TO EJECT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              // Player suspects list
              Expanded(
                child: ListView.separated(
                  itemCount: otherPlayers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final p = otherPlayers[idx];
                    final isSelected = _selectedTargetId == p.id;

                    return InkWell(
                      onTap: () => _handleVote(p.id),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.impostorColor.withAlpha(40)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.impostorColor
                                : AppTheme.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isSelected
                                  ? AppTheme.impostorColor.withAlpha(60)
                                  : AppTheme.primary.withAlpha(40),
                              child: Icon(
                                Icons.person_rounded,
                                color: isSelected
                                    ? AppTheme.impostorColor
                                    : AppTheme.primaryLight,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? AppTheme.impostorColor
                                      : Colors.white,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.impostorColor,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Abstain Option
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _abstained ? AppTheme.accent : AppTheme.border,
                    width: _abstained ? 2 : 1,
                  ),
                  backgroundColor: _abstained
                      ? AppTheme.accent.withAlpha(30)
                      : null,
                ),
                onPressed: () => _handleVote(null),
                icon: Icon(
                  Icons.do_not_disturb_on_total_silence_rounded,
                  color: _abstained ? AppTheme.accent : AppTheme.textSecondary,
                  size: 20,
                ),
                label: Text(
                  'Abstain from Voting',
                  style: TextStyle(
                    color: _abstained
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
