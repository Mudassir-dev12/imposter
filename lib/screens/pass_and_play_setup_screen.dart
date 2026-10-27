import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../models/protocol_models.dart';
import '../services/pass_and_play_controller.dart';
import 'pass_and_play_game_screen.dart';

class PassAndPlaySetupScreen extends StatefulWidget {
  const PassAndPlaySetupScreen({super.key});

  @override
  State<PassAndPlaySetupScreen> createState() => _PassAndPlaySetupScreenState();
}

class _PassAndPlaySetupScreenState extends State<PassAndPlaySetupScreen> {
  static const String _prefNamesKey = 'pass_and_play_saved_names';

  final List<TextEditingController> _nameControllers = [];
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String _category = 'random';
  int _impostorCount = 1;
  int _clueRounds = 2;
  int _discussionTimer = 60;
  bool _impostorSeesCategory = true;
  bool _isStarting = false;

  final List<String> _categories = [
    'random',
    'Animals',
    'Food',
    'Objects',
    'Places',
    'Occupations',
    'Movies',
    'Sports',
    'Technology',
    'Nature',
    'Vehicles',
    'Music',
    'Science',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedNames();
  }

  Future<void> _loadSavedNames() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefNamesKey);
    final initialNames = (saved != null && saved.length >= 3)
        ? saved.take(10).toList()
        : ['Player 1', 'Player 2', 'Player 3', 'Player 4'];

    if (mounted) {
      setState(() {
        for (final name in initialNames) {
          _nameControllers.add(TextEditingController(text: name));
        }
      });
    }
  }

  Future<void> _saveNames() async {
    final prefs = await SharedPreferences.getInstance();
    final names = _nameControllers.map((c) => c.text.trim()).toList();
    await prefs.setStringList(_prefNamesKey, names);
  }

  void _addPlayer() {
    if (_nameControllers.length >= 10) return;
    setState(() {
      _nameControllers.add(
        TextEditingController(text: 'Player ${_nameControllers.length + 1}'),
      );
    });
  }

  void _removePlayer(int index) {
    if (_nameControllers.length <= 3) return;
    setState(() {
      _nameControllers.removeAt(index).dispose();
      // Adjust impostor count if player count drops below 7
      if (_nameControllers.length < 7 && _impostorCount > 1) {
        _impostorCount = 1;
      }
    });
  }

  String? _validateName(String? value, int currentIndex) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter name';
    }
    final trimmed = value.trim();
    if (trimmed.length > 16) {
      return 'Max 16 chars';
    }

    // Check for duplicates
    for (int i = 0; i < _nameControllers.length; i++) {
      if (i != currentIndex &&
          _nameControllers[i].text.trim().toLowerCase() == trimmed.toLowerCase()) {
        return 'Name taken';
      }
    }
    return null;
  }

  Future<void> _startGame() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isStarting = true);

    try {
      await _saveNames();

      final playerNames = _nameControllers.map((c) => c.text.trim()).toList();
      final settings = GameSettingsModel(
        category: _category,
        impostorCount: _impostorCount,
        clueRounds: _clueRounds,
        discussionTimerSeconds: _discussionTimer,
        impostorSeesCategory: _impostorSeesCategory,
        turnTimerSeconds: 0, // No turn timers by default in pass-and-play
        spokenClues: true,   // Spoken clues mode for offline party play
      );

      final controller = PassAndPlayController(
        playerNames: playerNames,
        settings: settings,
      );

      await controller.startSession();

      if (!mounted) return;

      if (controller.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start: ${controller.errorMessage}'),
            backgroundColor: AppTheme.impostorColor,
          ),
        );
        setState(() => _isStarting = false);
        return;
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PassAndPlayGameScreen(controller: controller),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.impostorColor,
          ),
        );
        setState(() => _isStarting = false);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Pass & Play Setup'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isStarting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryLight),
                  SizedBox(height: 20),
                  Text(
                    'Setting up offline game...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // Players Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Players (${_nameControllers.length}/10)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_nameControllers.length < 10)
                        TextButton.icon(
                          onPressed: _addPlayer,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Add Player'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryLight,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Reorderable Player Name List
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _nameControllers.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _nameControllers.removeAt(oldIndex);
                        _nameControllers.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (ctx, index) {
                      return Padding(
                        key: ValueKey('player_tile_$index'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primary.withAlpha(80),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: TextFormField(
                              controller: _nameControllers[index],
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              validator: (val) => _validateName(val, index),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_nameControllers.length > 3)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: AppTheme.textSecondary,
                                      size: 20,
                                    ),
                                    onPressed: () => _removePlayer(index),
                                  ),
                                const Icon(
                                  Icons.drag_handle_rounded,
                                  color: AppTheme.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Game Settings Section
                  const Text(
                    'Game Rules',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category Dropdown
                        const Text(
                          'Category',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _category,
                              isExpanded: true,
                              dropdownColor: AppTheme.surfaceElevated,
                              items: _categories.map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c == 'random' ? 'Random Category' : c,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _category = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Impostor Count
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Impostors',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SegmentedButton<int>(
                              segments: [
                                const ButtonSegment(value: 1, label: Text('1')),
                                ButtonSegment(
                                  value: 2,
                                  label: const Text('2'),
                                  enabled: _nameControllers.length >= 7,
                                ),
                              ],
                              selected: {_impostorCount},
                              onSelectionChanged: (set) {
                                setState(() => _impostorCount = set.first);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Clue Rounds
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Clue Rounds',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(value: 1, label: Text('1')),
                                ButtonSegment(value: 2, label: Text('2')),
                                ButtonSegment(value: 3, label: Text('3')),
                              ],
                              selected: {_clueRounds},
                              onSelectionChanged: (set) {
                                setState(() => _clueRounds = set.first);
                              },
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
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            DropdownButton<int>(
                              value: _discussionTimer,
                              dropdownColor: AppTheme.surfaceElevated,
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('No Timer')),
                                DropdownMenuItem(value: 30, child: Text('30s')),
                                DropdownMenuItem(value: 60, child: Text('60s')),
                                DropdownMenuItem(value: 90, child: Text('90s')),
                                DropdownMenuItem(value: 120, child: Text('120s')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _discussionTimer = val);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Impostor Sees Category
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Impostor Sees Category',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Gives the Impostor a clue about the topic',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          value: _impostorSeesCategory,
                          activeThumbColor: AppTheme.primaryLight,
                          onChanged: (val) {
                            setState(() => _impostorSeesCategory = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Start Game Button
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _startGame,
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: const Text(
                        'Start Game',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
