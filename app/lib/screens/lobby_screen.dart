import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import '../models/protocol_models.dart';
import '../models/qr_payload.dart';
import '../services/host_service.dart';
import '../state/game_providers.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ref.read(hostIpProvider) == null) {
        final ip = await ref.read(hostServiceProvider).resolveHostIp();
        if (mounted && ip != null) {
          ref.read(hostIpProvider.notifier).setIp(ip);
        }
      }
    });
  }

  void _openSettingsDialog(
    BuildContext context,
    GameSettingsModel currentSettings,
  ) {
    int rounds = currentSettings.clueRounds;
    int impostors = currentSettings.impostorCount;
    String category = currentSettings.category;
    int discussionSec = currentSettings.discussionTimerSeconds;
    bool seesCategory = currentSettings.impostorSeesCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: AppTheme.primaryLight),
                    SizedBox(width: 8),
                    Text(
                      'Game Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Clue rounds (1 to 3)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Clue Rounds', style: TextStyle(fontSize: 16)),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1')),
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                      ],
                      selected: {rounds},
                      onSelectionChanged: (val) =>
                          setModalState(() => rounds = val.first),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Impostors (1 or 2)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Impostors', style: TextStyle(fontSize: 16)),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1')),
                        ButtonSegment(value: 2, label: Text('2 (7+ p)')),
                      ],
                      selected: {impostors},
                      onSelectionChanged: (val) =>
                          setModalState(() => impostors = val.first),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Discussion Timer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Discussion Timer',
                      style: TextStyle(fontSize: 16),
                    ),
                    DropdownButton<int>(
                      value: discussionSec,
                      dropdownColor: AppTheme.surfaceElevated,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('No Timer')),
                        DropdownMenuItem(value: 45, child: Text('45s')),
                        DropdownMenuItem(value: 60, child: Text('60s')),
                        DropdownMenuItem(value: 90, child: Text('90s')),
                        DropdownMenuItem(value: 120, child: Text('2m')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => discussionSec = val);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Impostor sees category hint
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Impostor sees category hint',
                    style: TextStyle(fontSize: 16),
                  ),
                  value: seesCategory,
                  activeThumbColor: AppTheme.primaryLight,
                  onChanged: (val) => setModalState(() => seesCategory = val),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    final updated = currentSettings.copyWith(
                      clueRounds: rounds,
                      impostorCount: impostors,
                      category: category,
                      discussionTimerSeconds: discussionSec,
                      impostorSeesCategory: seesCategory,
                    );
                    ref.read(gameClientProvider).updateSettings(updated);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save Settings'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomStateProvider).value;
    final isHost = ref.watch(isHostProvider);
    final client = ref.read(gameClientProvider);

    if (roomState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final players = roomState.players;
    final canStart = players.length >= 3;

    String resolvedHostIp = ref.watch(hostIpProvider) ??
        HostService().lastResolvedHostIp ??
        '';
    int resolvedPort = HostService.defaultPort;

    // On guest devices or if host provider is loopback, resolve from client's active server connection
    if (resolvedHostIp.isEmpty || resolvedHostIp == '127.0.0.1') {
      final sAddr = client.serverAddress;
      if (sAddr != null && sAddr.isNotEmpty) {
        final colonIdx = sAddr.lastIndexOf(':');
        if (colonIdx > 0) {
          final ipPart = sAddr.substring(0, colonIdx).trim();
          final portPart = sAddr.substring(colonIdx + 1).trim();
          if (ipPart != '127.0.0.1' && ipPart.isNotEmpty) {
            resolvedHostIp = ipPart;
          }
          final parsedPort = int.tryParse(portPart);
          if (parsedPort != null) {
            resolvedPort = parsedPort;
          }
        } else if (sAddr != '127.0.0.1') {
          resolvedHostIp = sAddr;
        }
      }
    }
    if (resolvedHostIp.isEmpty) {
      resolvedHostIp = '127.0.0.1';
    }

    final wsAddress = 'ws://$resolvedHostIp:$resolvedPort';
    final manualAddress = '$resolvedHostIp:$resolvedPort';
    final qrPayload = QrPayload(
      host: resolvedHostIp,
      port: resolvedPort,
      code: roomState.roomCode,
    ).encodeJson();

    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = (screenWidth * 0.70).clamp(200.0, 320.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Lobby'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Leave Room',
            icon: const Icon(
              Icons.exit_to_app_rounded,
              color: AppTheme.impostorColor,
            ),
            onPressed: () => client.leaveRoom(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Room Code & Host Join Info Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withAlpha(50),
                      AppTheme.surfaceElevated,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.primary.withAlpha(100),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ROOM CODE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              roomState.roomCode,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(40),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.primaryLight.withAlpha(80),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_alt_rounded,
                                size: 14,
                                color: AppTheme.primaryLight,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${players.length} / 10',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                          text: '$manualAddress ${roomState.roomCode}',
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied address & code!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '$wsAddress • ${roomState.roomCode}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // QR Code Section:
              // Prominently shown on ALL screens in the lobby (Host and Guests)
              // at ~70% screen width with white background, quiet margin,
              // and high error correction (QrErrorCorrectLevel.H).
              // Kept near the top so it is directly visible without scrolling on small phones.
              const SizedBox(height: 12),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(50),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: qrPayload,
                        version: QrVersions.auto,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        size: qrSize,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.all(8),
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Scan with Imposter app to join room',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isHost && resolvedHostIp == '127.0.0.1') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppTheme.accent.withAlpha(60)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 14,
                        color: AppTheme.accent,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Offline / Hotspot off. Turn on Hotspot for friends.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Settings summary chip (tap to edit if host)
              InkWell(
                onTap: isHost
                    ? () => _openSettingsDialog(context, roomState.settings)
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${roomState.settings.clueRounds} Rounds • ${roomState.settings.impostorCount} Impostor • ${roomState.settings.category}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (isHost)
                        const Text(
                          'EDIT',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Player List
              const Text(
                'PLAYERS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: players.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final p = players[idx];
                  final isMe = p.id == roomState.myId;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppTheme.primary.withAlpha(25)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isMe
                            ? AppTheme.primary.withAlpha(120)
                            : AppTheme.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: p.connected
                              ? AppTheme.crewColor.withAlpha(40)
                              : Colors.grey.withAlpha(40),
                          child: Icon(
                            p.isHost
                                ? Icons.star_rounded
                                : Icons.person_rounded,
                            size: 18,
                            color: p.connected
                                ? (p.isHost
                                      ? AppTheme.accent
                                      : AppTheme.crewColor)
                                : Colors.grey,
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
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: p.connected
                                          ? Colors.white
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 6),
                                    const Text(
                                      '(You)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.primaryLight,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (!p.connected)
                                const Text(
                                  'Disconnected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.impostorColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (p.isHost)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'HOST',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                        if (isHost && !p.isHost)
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppTheme.impostorColor,
                              size: 20,
                            ),
                            tooltip: 'Kick player',
                            onPressed: () => client.kickPlayer(p.id),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Bottom action bar
              if (isHost) ...[
                if (!canStart)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Need at least 3 players to start game',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ElevatedButton(
                  onPressed: canStart ? () => client.startGame() : null,
                  child: const Text('Start Game'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Waiting for host to start...',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
