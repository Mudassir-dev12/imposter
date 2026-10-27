import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/protocol_models.dart';
import '../models/qr_payload.dart';
import '../state/game_providers.dart';
import 'qr_scanner_screen.dart';

class JoinScreen extends ConsumerStatefulWidget {
  final String playerName;
  final String serverAddress;

  const JoinScreen({
    super.key,
    required this.playerName,
    required this.serverAddress,
  });

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final TextEditingController _codeController = TextEditingController();
  late final TextEditingController _serverAddressController;
  late final TextEditingController _nameController;
  StreamSubscription<ErrorMessageModel>? _errorSub;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _serverAddressController = TextEditingController(text: widget.serverAddress);
    _nameController = TextEditingController(text: widget.playerName);

    // Listen to error stream to display clean server errors
    final client = ref.read(gameClientProvider);
    _errorSub = client.errorStream.listen((err) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = switch (err.code) {
            'ROOM_NOT_FOUND' => 'Room not found. Check the 4-letter code.',
            'NAME_TAKEN' => 'That name is already taken in this room.',
            'ROOM_FULL' => 'This room is full (max 10 players).',
            'WRONG_PHASE' => 'Game is already in progress.',
            _ => err.message,
          };
        });
      }
    });
  }

  Future<void> _openQrScanner() async {
    final payload = await Navigator.of(context).push<QrPayload>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (payload != null && mounted) {
      setState(() {
        _serverAddressController.text = payload.address;
        _codeController.text = payload.code;
        _errorMessage = null;
      });

      // Save server address
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefServerAddress, payload.address);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primary,
            content: Text('Scanned Room ${payload.code} at ${payload.address}'),
            duration: const Duration(seconds: 2),
          ),
        );

        if (_nameController.text.trim().isNotEmpty) {
          _handleJoin();
        }
      }
    }
  }

  Future<void> _handleJoin() async {
    final address = _serverAddressController.text.trim();
    final code = _codeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (address.isEmpty) {
      setState(() => _errorMessage = 'Please enter the server address (IP:port).');
      return;
    }
    if (code.length != 4) {
      setState(() => _errorMessage = 'Please enter a 4-letter room code.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefServerAddress, address);

      final client = ref.read(gameClientProvider);
      await client.connect(address);
      await client.joinRoom(code, name);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not reach server at $address. Ensure host phone is running and both devices share Wi-Fi or Hotspot.';
        });
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _serverAddressController.dispose();
    _nameController.dispose();
    _errorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Room'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scan QR Code Button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _openQrScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                label: const Text(
                  'Scan QR Code',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 20),

              // OR divider
              const Row(
                children: [
                  Expanded(child: Divider(color: AppTheme.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR ENTER MANUALLY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: AppTheme.border)),
                ],
              ),
              const SizedBox(height: 20),

              // Manual Input Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HOST ADDRESS (IP:PORT)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _serverAddressController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 192.168.43.1:8765',
                          prefixIcon: Icon(
                            Icons.dns_rounded,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'ROOM CODE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        maxLength: 4,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: AppTheme.primaryLight,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'ABCD',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'YOUR NAME',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        maxLength: 16,
                        decoration: const InputDecoration(
                          hintText: 'Enter name',
                          counterText: '',
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
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

              OutlinedButton(
                onPressed: _isLoading ? null : _handleJoin,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Join Game with Manual Code', style: TextStyle(fontSize: 16)),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
