import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/protocol_models.dart';
import '../services/host_service.dart';
import '../state/game_providers.dart';
import 'join_screen.dart';

class WifiHubScreen extends ConsumerStatefulWidget {
  final String playerName;

  const WifiHubScreen({super.key, required this.playerName});

  @override
  ConsumerState<WifiHubScreen> createState() => _WifiHubScreenState();
}

class _WifiHubScreenState extends ConsumerState<WifiHubScreen> {
  final TextEditingController _customServerAddressController =
      TextEditingController();
  StreamSubscription<RoomJoinedModel>? _roomJoinedSub;
  bool _isLoading = false;
  String _loadingMessage = '';
  String? _detectedHostIp;
  bool _checkingNetwork = true;
  String? _errorMessage;
  bool _showCustomServerField = false;

  @override
  void initState() {
    super.initState();
    _loadSavedServerAddress();
    _detectLocalNetwork();

    // Listen for room creation success to trigger foreground hosting service
    final client = ref.read(gameClientProvider);
    _roomJoinedSub = client.roomJoinedStream.listen((joined) {
      if (joined.isHost) {
        final hostService = ref.read(hostServiceProvider);
        final ip = _detectedHostIp ?? '127.0.0.1';
        ref.read(hostIpProvider.notifier).setIp(ip);
        hostService.startHosting(
          roomCode: joined.code,
          hostIp: ip,
          port: HostService.defaultPort,
        );
      }
    });
  }

  Future<void> _loadSavedServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConstants.prefServerAddress);
    if (mounted) {
      _customServerAddressController.text =
          saved ?? AppConstants.defaultServerAddress;
    }
  }

  Future<void> _detectLocalNetwork() async {
    setState(() => _checkingNetwork = true);
    final hostService = ref.read(hostServiceProvider);
    final ip = await hostService.resolveHostIp();
    if (mounted) {
      setState(() {
        _detectedHostIp = ip;
        _checkingNetwork = false;
        if (ip != null) {
          ref.read(hostIpProvider.notifier).setIp(ip);
        }
      });
    }
  }

  Future<void> _handleCreateRoom() async {
    // 1. Verify network status
    String? hostIp = _detectedHostIp;
    if (hostIp == null) {
      // Re-check once before prompting
      hostIp = await ref.read(hostServiceProvider).resolveHostIp();
      _detectedHostIp = hostIp;
    }

    if (hostIp == null && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppTheme.accent),
              SizedBox(width: 10),
              Text('No Wi-Fi or Hotspot', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: const Text(
            'Your phone is not connected to Wi-Fi and mobile hotspot is turned off.\n\n'
            'Other players will NOT be able to join your room without a shared local network.\n\n'
            'To host a game with friends, connect to Wi-Fi or turn on Mobile Hotspot in your phone settings.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Host Anyway (Solo)',
                style: TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Starting embedded server...';
      _errorMessage = null;
    });

    try {
      final hostService = ref.read(hostServiceProvider);
      // Start or reuse embedded server
      await hostService.ensureServerRunning(port: HostService.defaultPort);

      if (!mounted) return;
      setState(() => _loadingMessage = 'Connecting to server...');

      // Connect loopback client
      final client = ref.read(gameClientProvider);
      await client.connect('127.0.0.1:${HostService.defaultPort}');

      if (!mounted) return;
      setState(() => _loadingMessage = 'Creating game room...');

      // Create room as host
      await client.createRoom(widget.playerName);

      // Save default server address preference
      final prefs = await SharedPreferences.getInstance();
      if (hostIp != null) {
        await prefs.setString(
          AppConstants.prefServerAddress,
          '$hostIp:${HostService.defaultPort}',
        );
      }

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Failed to create room: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _customServerAddressController.dispose();
    _roomJoinedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Multiplayer'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Network status card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _detectedHostIp != null
                        ? AppTheme.primaryLight.withAlpha(80)
                        : AppTheme.accent.withAlpha(80),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _detectedHostIp != null
                          ? AppTheme.primaryLight.withAlpha(30)
                          : AppTheme.accent.withAlpha(30),
                      child: Icon(
                        _detectedHostIp != null
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        color: _detectedHostIp != null
                            ? AppTheme.primaryLight
                            : AppTheme.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _checkingNetwork
                                ? 'Checking network...'
                                : (_detectedHostIp != null
                                    ? 'Host IP: $_detectedHostIp'
                                    : 'No Wi-Fi / Hotspot IP'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _detectedHostIp != null
                                ? 'Ready to host or join nearby games'
                                : 'Turn on hotspot or connect to Wi-Fi to play with friends',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh network IP',
                      onPressed: _detectLocalNetwork,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Create Room Section (Host)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withAlpha(60),
                      AppTheme.surfaceElevated,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withAlpha(120),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.stars_rounded, color: AppTheme.accent, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'HOST A GAME',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppTheme.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Run the game on this phone. Friends join via QR code or room code.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleCreateRoom,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _loadingMessage.isNotEmpty
                                      ? _loadingMessage
                                      : 'Creating...',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline_rounded, size: 22),
                                SizedBox(width: 10),
                                Text('Create Room', style: TextStyle(fontSize: 16)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Join Room Section (Guest)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.group_rounded, color: AppTheme.primaryLight, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'JOIN A GAME',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan the QR code on the host\'s phone, or enter their IP and room code.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              final defaultAddr = _detectedHostIp != null
                                  ? '$_detectedHostIp:${HostService.defaultPort}'
                                  : _customServerAddressController.text.trim();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => JoinScreen(
                                    playerName: widget.playerName,
                                    serverAddress: defaultAddr,
                                  ),
                                ),
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 22,
                            color: AppTheme.primaryLight,
                          ),
                          SizedBox(width: 10),
                          Text('Scan QR / Join Room', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.impostorColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.impostorColor.withAlpha(100),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.impostorColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.impostorColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Advanced option for remote testing (e.g. laptop or emulator)
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showCustomServerField = !_showCustomServerField;
                    });
                  },
                  icon: Icon(
                    _showCustomServerField
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.settings_ethernet_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  label: Text(
                    _showCustomServerField
                        ? 'Hide Remote Server Config'
                        : 'Remote Server (Laptop/Emulator)',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              if (_showCustomServerField) ...[
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CUSTOM SERVER ADDRESS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _customServerAddressController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. 10.0.2.2:8765 or 192.168.1.50:8765',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
