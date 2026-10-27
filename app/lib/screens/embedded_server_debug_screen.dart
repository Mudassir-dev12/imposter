import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../core/theme.dart';
import '../services/host_service.dart';

class EmbeddedServerDebugScreen extends StatefulWidget {
  const EmbeddedServerDebugScreen({super.key});

  @override
  State<EmbeddedServerDebugScreen> createState() =>
      _EmbeddedServerDebugScreenState();
}

enum ServerState {
  stopped,
  starting,
  running,
  error,
}

class _EmbeddedServerDebugScreenState extends State<EmbeddedServerDebugScreen> {
  final NetworkInfo _networkInfo = NetworkInfo();
  final int _port = 8765;
  final HostService _hostService = HostService();

  String? _wifiIp;
  String _statusMessage = 'Server stopped';
  ServerState _serverState = ServerState.stopped;

  ServerStatus _liveStatus = ServerStatus.stopped();
  Timer? _pollTimer;
  DateTime? _startTime;
  int? _startupTimeMs;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _fetchWifiIp();
    _refreshStatus();
    _startPeriodicPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWifiIp() async {
    String? ip;
    try {
      ip = await _networkInfo.getWifiIP();
    } catch (_) {}

    if (ip == null || ip.isEmpty || ip == '0.0.0.0') {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              ip = addr.address;
              break;
            }
          }
          if (ip != null) break;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _wifiIp = ip ?? '127.0.0.1';
      });
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final isGamePortUp = await _hostService.isPortReachable(port: _port);
      final status = await _hostService.getStatus();

      if (!mounted) return;
      setState(() {
        _liveStatus = status;
        if (isGamePortUp && status.running) {
          _serverState = ServerState.running;
          _statusMessage = 'Server running on port $_port';
        } else if (_serverState != ServerState.starting) {
          _serverState = ServerState.stopped;
          _statusMessage = 'Server stopped';
        }
      });
    } catch (e) {
      if (mounted && _serverState != ServerState.starting) {
        setState(() {
          _serverState = ServerState.stopped;
          _statusMessage = 'Server stopped';
        });
      }
    }
  }

  void _startPeriodicPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_serverState != ServerState.starting) {
        _refreshStatus();
      }
    });
  }

  Future<void> _startServer() async {
    if (_serverState == ServerState.running || _serverState == ServerState.starting) {
      return;
    }

    setState(() {
      _serverState = ServerState.starting;
      _statusMessage = 'Starting supervisor & game server...';
      _startTime = DateTime.now();
      _startupTimeMs = null;
      _lastError = null;
    });

    try {
      await _hostService.ensureServerRunning(port: _port);
      final elapsed = _startTime != null
          ? DateTime.now().difference(_startTime!).inMilliseconds
          : 0;

      final status = await _hostService.getStatus();
      if (mounted) {
        setState(() {
          _serverState = ServerState.running;
          _statusMessage = 'Server running on port $_port';
          _startupTimeMs = elapsed;
          _liveStatus = status;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serverState = ServerState.error;
          _statusMessage = 'Startup failed';
          _lastError = e.toString();
        });
      }
    }
  }

  Future<void> _stopServer() async {
    setState(() {
      _statusMessage = 'Stopping server and releasing port...';
    });

    try {
      await _hostService.stopServer(port: _port);
      final status = await _hostService.getStatus();
      if (mounted) {
        setState(() {
          _serverState = ServerState.stopped;
          _statusMessage = 'Server stopped (port $_port released)';
          _liveStatus = status;
          _lastError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.crewColor,
            content: Text('Server stopped cleanly. Port $_port released.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = 'Stop failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wsUrl = 'ws://${_wifiIp ?? "..."}:$_port';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Embedded Python Server'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Card(
                color: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _serverState == ServerState.running
                        ? AppTheme.crewColor
                        : (_serverState == ServerState.starting
                            ? AppTheme.accent
                            : AppTheme.surfaceElevated),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _serverState == ServerState.running
                                  ? AppTheme.crewColor
                                  : (_serverState == ServerState.starting
                                      ? AppTheme.accent
                                      : AppTheme.impostorColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _statusMessage,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _serverState == ServerState.running
                                    ? AppTheme.crewColor
                                    : (_serverState == ServerState.starting
                                        ? AppTheme.accent
                                        : Colors.white),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_startupTimeMs != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Startup latency: ${_startupTimeMs}ms',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Live Status Card from STATUS Command
              Card(
                color: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LIVE SUPERVISOR STATUS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Control Channel',
                        value: '127.0.0.1:${HostService.defaultControlPort} (Protected)',
                        icon: Icons.security,
                      ),
                      const Divider(height: 24, color: AppTheme.surfaceElevated),
                      _InfoRow(
                        label: 'Game Server State',
                        value: _liveStatus.running ? 'Running (0.0.0.0:${_liveStatus.port})' : 'Stopped (Port Released)',
                        icon: Icons.power_settings_new,
                        isHighlight: _liveStatus.running,
                      ),
                      const Divider(height: 24, color: AppTheme.surfaceElevated),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoRow(
                              label: 'Active Rooms',
                              value: '${_liveStatus.rooms}',
                              icon: Icons.meeting_room_outlined,
                            ),
                          ),
                          Expanded(
                            child: _InfoRow(
                              label: 'Connections',
                              value: '${_liveStatus.connections}',
                              icon: Icons.people_outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Network Info Card
              Card(
                color: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NETWORK & ENDPOINT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Device Wi-Fi / Hotspot IP',
                        value: _wifiIp ?? 'Scanning...',
                        icon: Icons.wifi,
                      ),
                      const Divider(height: 24, color: AppTheme.surfaceElevated),
                      _InfoRow(
                        label: 'Game Server Port',
                        value: '$_port',
                        icon: Icons.numbers,
                      ),
                      const Divider(height: 24, color: AppTheme.surfaceElevated),
                      _InfoRow(
                        label: 'WebSocket URI',
                        value: wsUrl,
                        icon: Icons.link,
                        isHighlight: _serverState == ServerState.running,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              ElevatedButton.icon(
                onPressed: _serverState == ServerState.running ? null : _startServer,
                icon: _serverState == ServerState.starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _serverState == ServerState.running
                      ? 'Server is Running'
                      : 'Start Embedded Server',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _serverState == ServerState.stopped ? null : _stopServer,
                icon: const Icon(Icons.stop_rounded, color: AppTheme.accent),
                label: const Text(
                  'Stop Server',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              if (_lastError != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.impostorColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.impostorColor),
                  ),
                  child: Text(
                    'Error: $_lastError',
                    style: const TextStyle(
                      color: AppTheme.impostorColor,
                      fontSize: 13,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isHighlight;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isHighlight ? AppTheme.crewColor : AppTheme.primaryLight,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isHighlight ? AppTheme.crewColor : Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
