import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import 'embedded_server_debug_screen.dart';
import 'pass_and_play_setup_screen.dart';
import 'wifi_hub_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(AppConstants.prefPlayerName);
    if (savedName != null && mounted) {
      _nameController.text = savedName;
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefPlayerName, name);
    }
  }

  void _showHowToPlayDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: AppTheme.primaryLight),
            SizedBox(width: 10),
            Text('How to Play', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RuleSection(
                number: '1',
                title: 'Secret Word vs. Impostor',
                desc: 'Every player secretly receives the same secret word, except the Impostor, who receives only the category as a hint.',
              ),
              _RuleSection(
                number: '2',
                title: 'Clue Rounds',
                desc: 'Players take turns giving a one-word clue related to the secret word. Be subtle so the impostor doesn\'t guess the word!',
              ),
              _RuleSection(
                number: '3',
                title: 'Discussion & Voting',
                desc: 'Discuss and cast secret votes on who you think the Impostor is. Plurality wins.',
              ),
              _RuleSection(
                number: '4',
                title: 'Steal the Win',
                desc: 'If the Impostor is caught, they get one chance to guess the secret word. A correct guess steals the win!',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Got it!',
              style: TextStyle(color: AppTheme.primaryLight, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Game Logo / Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(40),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primary.withAlpha(100),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 72,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onLongPress: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EmbeddedServerDebugScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'IMPOSTOR',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A Social Word Deduction Game',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Name input card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Enter your name (1-16 chars)',
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
                const SizedBox(height: 28),

                // Play on Wi-Fi Button
                ElevatedButton(
                  onPressed: () async {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter your name first.'),
                        ),
                      );
                      return;
                    }
                    await _saveName();
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WifiHubScreen(playerName: name),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_rounded, size: 22),
                      SizedBox(width: 10),
                      Text('Play on Wi-Fi'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Offline Pass & Play Button
                OutlinedButton(
                  onPressed: () async {
                    await _saveName();
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PassAndPlaySetupScreen(),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.phonelink_ring_rounded,
                        size: 20,
                        color: AppTheme.primaryLight,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Pass & Play (1 Phone)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // How to play button
                TextButton.icon(
                  onPressed: _showHowToPlayDialog,
                  icon: const Icon(
                    Icons.help_outline_rounded,
                    size: 20,
                    color: AppTheme.primaryLight,
                  ),
                  label: const Text(
                    'How to Play',
                    style: TextStyle(
                      color: AppTheme.primaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  final String number;
  final String title;
  final String desc;

  const _RuleSection({
    required this.number,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppTheme.primary.withAlpha(80),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
