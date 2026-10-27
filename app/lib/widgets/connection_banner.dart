import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../services/game_client.dart';
import '../state/game_providers.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider);
    final status = statusAsync.value ?? ConnectionStatus.disconnected;

    if (status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    final isReconnecting = status == ConnectionStatus.reconnecting;
    final isConnecting = status == ConnectionStatus.connecting;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: isReconnecting
          ? AppTheme.accent.withAlpha(220)
          : AppTheme.impostorColor.withAlpha(220),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isReconnecting || isConnecting) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Reconnecting to server...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ] else ...[
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Disconnected from server',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
