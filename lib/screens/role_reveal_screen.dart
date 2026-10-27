import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/game_providers.dart';
import '../widgets/countdown_timer.dart';

class RoleRevealScreen extends ConsumerStatefulWidget {
  const RoleRevealScreen({super.key});

  @override
  ConsumerState<RoleRevealScreen> createState() => _RoleRevealScreenState();
}

class _RoleRevealScreenState extends ConsumerState<RoleRevealScreen> {
  bool _isHolding = false;

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomStateProvider).value;
    final client = ref.read(gameClientProvider);

    if (roomState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isImpostor = roomState.isImpostor;
    final hasConfirmed = roomState.hasConfirmedRole;
    final themeColor = isImpostor ? AppTheme.impostorColor : AppTheme.crewColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secret Role Assignment'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timer pill
              Center(
                child: CountdownTimerWidget(
                  deadlineEpochMs: roomState.deadlineEpochMs,
                  label: 'Reveal Ends in',
                ),
              ),
              const SizedBox(height: 20),

              // Hold-to-reveal card
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _isHolding = true),
                  onTapUp: (_) => setState(() => _isHolding = false),
                  onTapCancel: () => setState(() => _isHolding = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _isHolding
                          ? (isImpostor
                                ? AppTheme.impostorBackground
                                : AppTheme.crewBackground)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _isHolding ? themeColor : AppTheme.border,
                        width: _isHolding ? 2.5 : 1.5,
                      ),
                      boxShadow: _isHolding
                          ? [
                              BoxShadow(
                                color: themeColor.withAlpha(80),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: _isHolding
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isImpostor
                                      ? Icons.visibility_off_rounded
                                      : Icons.shield_rounded,
                                  size: 64,
                                  color: themeColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isImpostor
                                      ? 'YOU ARE THE IMPOSTOR'
                                      : 'YOU ARE CREW',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    color: themeColor,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (roomState.category != null) ...[
                                  const Text(
                                    'CATEGORY',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    roomState.category!,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                if (!isImpostor &&
                                    roomState.myWord != null) ...[
                                  const Text(
                                    'SECRET WORD',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.crewColor.withAlpha(40),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.crewColor,
                                      ),
                                    ),
                                    child: Text(
                                      roomState.myWord!,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ] else if (isImpostor) ...[
                                  const Text(
                                    'Blend in and guess the secret word!\nDo not get caught.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withAlpha(40),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.touch_app_rounded,
                                    size: 48,
                                    color: AppTheme.primaryLight,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'PRESS & HOLD TO REVEAL',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Make sure nobody is looking at your screen',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // "I've seen it" Confirmation Button
              ElevatedButton(
                onPressed: hasConfirmed ? null : () => client.confirmRoleSeen(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasConfirmed
                      ? AppTheme.surfaceElevated
                      : AppTheme.primary,
                ),
                child: hasConfirmed
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.crewColor,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Waiting for other players...',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      )
                    : const Text("I've seen it!"),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
