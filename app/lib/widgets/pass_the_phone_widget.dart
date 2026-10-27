import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Interstitial safety barrier shown before any private content is displayed.
/// Requires the active player to explicitly confirm their identity.
class PassThePhoneWidget extends StatelessWidget {
  final String playerName;
  final String? subtitle;
  final VoidCallback onConfirmed;

  const PassThePhoneWidget({
    super.key,
    required this.playerName,
    required this.onConfirmed,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withAlpha(40),
                border: Border.all(color: AppTheme.primaryLight, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withAlpha(80),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.phonelink_ring_rounded,
                size: 72,
                color: AppTheme.primaryLight,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Pass the phone to',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withAlpha(100)),
              ),
              child: Text(
                playerName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              subtitle ?? 'Keep the screen hidden from other players.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                key: const ValueKey('confirm_identity_button'),
                onPressed: onConfirmed,
                icon: const Icon(Icons.lock_open_rounded, size: 24),
                label: Text(
                  'I am $playerName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
