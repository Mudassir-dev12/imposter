import 'dart:async';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/protocol_models.dart';
import '../services/pass_and_play_controller.dart';
import '../widgets/pass_the_phone_widget.dart';

class PassAndPlayGameScreen extends StatefulWidget {
  final PassAndPlayController controller;

  const PassAndPlayGameScreen({
    super.key,
    required this.controller,
  });

  @override
  State<PassAndPlayGameScreen> createState() => _PassAndPlayGameScreenState();
}

class _PassAndPlayGameScreenState extends State<PassAndPlayGameScreen>
    with WidgetsBindingObserver {
  String? _selectedVoteTargetId;
  final TextEditingController _guessController = TextEditingController();
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _isCardHeld = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerUpdated);
    _startTimerIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Hide any private content immediately if app leaves foreground
      widget.controller.lockPrivateContent();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Safety lock on orientation or window size change
    widget.controller.lockPrivateContent();
  }

  void _onControllerUpdated() {
    if (!mounted) return;
    _startTimerIfNeeded();
    setState(() {});
  }

  void _startTimerIfNeeded() {
    final deadlineMs = widget.controller.primaryState?.deadlineEpochMs;
    if (deadlineMs != null) {
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final diff = ((deadlineMs - nowMs) / 1000).ceil();
        if (mounted) {
          setState(() {
            _remainingSeconds = diff > 0 ? diff : 0;
          });
        }
        if (diff <= 0) {
          timer.cancel();
        }
      });
    } else {
      _countdownTimer?.cancel();
      _remainingSeconds = 0;
    }
  }

  Future<void> _showExitConfirmationDialog() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Game?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to end this Pass & Play session? Current game progress will be lost.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.impostorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave Game'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      await widget.controller.disposeSession();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerUpdated);
    _countdownTimer?.cancel();
    _guessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.primaryState;
    if (state == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryLight),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _showExitConfirmationDialog();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(_appBarTitleForPhase(state.phase)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _showExitConfirmationDialog,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    state.category ?? state.settings.category,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: _buildPhaseContent(state),
        ),
      ),
    );
  }

  String _appBarTitleForPhase(String phase) {
    switch (phase) {
      case 'ROLE_REVEAL':
        return 'Role Reveal';
      case 'CLUE_ROUND':
        return 'Clue Round ${widget.controller.primaryState?.roundIndex ?? 1}';
      case 'DISCUSSION':
        return 'Discussion';
      case 'VOTING':
        return 'Voting';
      case 'IMPOSTOR_GUESS':
        return 'Impostor Steal';
      case 'RESULT':
      case 'ROUND_END':
      case 'GAME_OVER':
        return 'Round Results';
      default:
        return 'Pass & Play';
    }
  }

  Widget _buildPhaseContent(RoomStateModel state) {
    switch (state.phase) {
      case 'ROLE_REVEAL':
        return _buildRoleRevealPhase();
      case 'CLUE_ROUND':
        return _buildClueRoundPhase(state);
      case 'DISCUSSION':
        return _buildDiscussionPhase(state);
      case 'VOTING':
        return _buildVotingPhase(state);
      case 'IMPOSTOR_GUESS':
        return _buildImpostorGuessPhase(state);
      case 'RESULT':
      case 'ROUND_END':
      case 'GAME_OVER':
        return _buildResultPhase(state);
      default:
        return const Center(child: Text('Preparing game...'));
    }
  }

  // =========================================================================
  // 1. Role Reveal (Private)
  // =========================================================================
  Widget _buildRoleRevealPhase() {
    if (!widget.controller.isPrivateContentRevealed) {
      return PassThePhoneWidget(
        playerName: widget.controller.activePrivatePlayerName,
        subtitle: 'Reveal your secret role in private.',
        onConfirmed: widget.controller.revealPrivateContent,
      );
    }

    final activeState = widget.controller.activePrivateState;
    final isImpostor = activeState?.myRole == 'IMPOSTOR';
    final word = activeState?.myWord ?? '???';
    final category = activeState?.category ?? 'Unknown';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Text(
            widget.controller.activePrivatePlayerName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hold the card below to reveal your secret identity.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Hold-to-Reveal Card
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isCardHeld = true),
              onTapUp: (_) => setState(() => _isCardHeld = false),
              onTapCancel: () => setState(() => _isCardHeld = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isCardHeld
                      ? (isImpostor ? AppTheme.impostorColor.withAlpha(40) : AppTheme.crewColor.withAlpha(40))
                      : AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isCardHeld
                        ? (isImpostor ? AppTheme.impostorColor : AppTheme.crewColor)
                        : AppTheme.border,
                    width: 2,
                  ),
                  boxShadow: _isCardHeld
                      ? [
                          BoxShadow(
                            color: (isImpostor ? AppTheme.impostorColor : AppTheme.crewColor).withAlpha(80),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: _isCardHeld
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isImpostor ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                              size: 72,
                              color: isImpostor ? AppTheme.impostorColor : AppTheme.crewColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              isImpostor ? 'YOU ARE THE IMPOSTOR' : 'YOU ARE A CREWMATE',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isImpostor ? AppTheme.impostorColor : AppTheme.crewColor,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Category: $category',
                              style: const TextStyle(fontSize: 16, color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            if (!isImpostor)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.crewColor.withAlpha(60),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  word,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else
                              const Text(
                                'You do not know the secret word!\nBlend in and don\'t get caught.',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app_rounded, size: 64, color: AppTheme.primaryLight),
                            SizedBox(height: 16),
                            Text(
                              'PRESS & HOLD TO REVEAL',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Hide and Pass Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _isCardHeld = false);
                widget.controller.confirmRoleSeen();
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'Hide & Pass Phone',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. Clue Round (Public - Spoken Clues)
  // =========================================================================
  Widget _buildClueRoundPhase(RoomStateModel state) {
    final currentTurnId = state.currentTurnPlayerId;
    final currentSpeakerName = currentTurnId != null
        ? widget.controller.playerNameForId(currentTurnId)
        : 'Active Player';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryLight.withAlpha(80)),
            ),
            child: Column(
              children: [
                const Icon(Icons.record_voice_over_rounded, size: 54, color: AppTheme.primaryLight),
                const SizedBox(height: 14),
                Text(
                  currentSpeakerName,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Say your one-word clue out loud!',
                  style: TextStyle(fontSize: 16, color: AppTheme.primaryLight, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Be subtle so the Impostor doesn\'t guess the secret word.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Turn Order Progress Chips
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Turn Order:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: widget.controller.playerNames.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (ctx, index) {
                final name = widget.controller.playerNames[index];
                final client = widget.controller.clients[index];
                final isCurrent = client.state?.myId == currentTurnId;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isCurrent ? AppTheme.primary.withAlpha(40) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent ? AppTheme.primaryLight : AppTheme.border,
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isCurrent ? AppTheme.primaryLight : AppTheme.border,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCurrent ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: isCurrent ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        const Chip(
                          label: Text('Speaking Now', style: TextStyle(fontSize: 10, color: Colors.white)),
                          backgroundColor: AppTheme.primary,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // "I Said It" Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: widget.controller.endTurn,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 24),
              label: Text(
                '$currentSpeakerName: I Said It!',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. Discussion Phase (Public)
  // =========================================================================
  Widget _buildDiscussionPhase(RoomStateModel state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withAlpha(30),
              border: Border.all(color: AppTheme.primaryLight, width: 2),
            ),
            child: Column(
              children: [
                Text(
                  '$_remainingSeconds',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Text('seconds', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Discuss the Clues!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Who seemed hesitant? Who knew too much?\nTalk out loud before casting your secret votes.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: widget.controller.skipDiscussion,
              icon: const Icon(Icons.how_to_vote_rounded),
              label: const Text(
                'Skip to Voting',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // =========================================================================
  // 4. Voting Phase (Private)
  // =========================================================================
  Widget _buildVotingPhase(RoomStateModel state) {
    if (!widget.controller.isPrivateContentRevealed) {
      return PassThePhoneWidget(
        playerName: widget.controller.activePrivatePlayerName,
        subtitle: 'Cast your vote secretly for who you suspect.',
        onConfirmed: widget.controller.revealPrivateContent,
      );
    }

    final voterName = widget.controller.activePrivatePlayerName;
    final activeClient = widget.controller.activePrivateClient;
    final voterId = activeClient?.state?.myId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$voterName\'s Vote',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select who you believe is the Impostor:',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView.separated(
              itemCount: state.players.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (ctx, index) {
                final target = state.players[index];
                final isMe = target.id == voterId;
                final isSelected = _selectedVoteTargetId == target.id;

                return InkWell(
                  onTap: () {
                    setState(() => _selectedVoteTargetId = target.id);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary.withAlpha(40) : AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryLight : AppTheme.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? AppTheme.primaryLight : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          target.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        if (isMe)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text('(You)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _selectedVoteTargetId != null
                  ? () {
                      final target = _selectedVoteTargetId;
                      setState(() => _selectedVoteTargetId = null);
                      widget.controller.castVote(target);
                    }
                  : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'Cast Vote & Pass Phone',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. Impostor Guess Phase (Private)
  // =========================================================================
  Widget _buildImpostorGuessPhase(RoomStateModel state) {
    final caughtId = state.caughtImpostorId;
    final impostorName = caughtId != null ? widget.controller.playerNameForId(caughtId) : 'Impostor';

    if (!widget.controller.isPrivateContentRevealed) {
      return PassThePhoneWidget(
        playerName: impostorName,
        subtitle: 'You were caught! You have one final chance to steal the win.',
        onConfirmed: widget.controller.revealPrivateContent,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.psychology_rounded, size: 64, color: AppTheme.accent),
          const SizedBox(height: 16),
          Text(
            '$impostorName, Steal the Win!',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Guess the secret word based on the clues you heard. A correct guess wins the game!',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _guessController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Enter your guess...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primaryLight, width: 2),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                final guess = _guessController.text.trim();
                if (guess.isNotEmpty) {
                  widget.controller.submitImpostorGuess(guess);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Submit Guess', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 6. Result Phase (Public)
  // =========================================================================
  String _formatOutcomeMessage(RoundResultModel? result) {
    if (result == null) return '';
    final outcome = result.outcome;
    if (outcome == 'CREW_WIN') {
      return 'The Impostor was caught and failed to guess the secret word!';
    } else if (outcome == 'IMPOSTOR_STEAL_WIN') {
      return 'The Impostor guessed the secret word and stole the victory!';
    } else if (outcome == 'IMPOSTOR_WIN_TIE') {
      return 'The vote was tied! The Impostor escaped undetected.';
    } else if (outcome == 'IMPOSTOR_WIN_INNOCENT_VOTED') {
      return 'An innocent crewmate was voted out!';
    }
    return outcome;
  }

  Widget _buildResultPhase(RoomStateModel state) {
    final result = state.roundResult;
    final outcome = result?.outcome;
    final isCrewWin = outcome == 'CREW_WIN';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          // Outcome Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isCrewWin ? AppTheme.crewColor.withAlpha(40) : AppTheme.impostorColor.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isCrewWin ? AppTheme.crewColor : AppTheme.impostorColor,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  isCrewWin ? Icons.emoji_events_rounded : Icons.sentiment_very_dissatisfied_rounded,
                  size: 48,
                  color: isCrewWin ? Colors.amber : AppTheme.impostorColor,
                ),
                const SizedBox(height: 8),
                Text(
                  isCrewWin ? 'CREWMATES WIN!' : 'IMPOSTOR WINS!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isCrewWin ? AppTheme.crewColor : AppTheme.impostorColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatOutcomeMessage(result),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Word & Impostor Details
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Secret Word', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      state.myWord ?? result?.secretWord ?? 'N/A',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Container(width: 1, height: 32, color: AppTheme.border),
                Column(
                  children: [
                    const Text('Impostor(s)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      (state.impostorIds ?? [])
                          .map((id) => widget.controller.playerNameForId(id))
                          .join(', '),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.impostorColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Scoreboard Header
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Scores:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),

          // Scoreboard List
          Expanded(
            child: ListView.separated(
              itemCount: state.players.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (ctx, index) {
                final p = state.players[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text('${p.score} pts', style: const TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await widget.controller.disposeSession();
                    if (mounted) Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Back to Home'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.controller.playAgain,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Play Again', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
