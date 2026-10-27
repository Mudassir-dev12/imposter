import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'screens/clue_round_screen.dart';
import 'screens/discussion_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/result_screen.dart';
import 'screens/role_reveal_screen.dart';
import 'screens/voting_screen.dart';
import 'services/host_service.dart';
import 'state/game_providers.dart';
import 'widgets/connection_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HostService.initForegroundTask();
  runApp(const ProviderScope(child: ImpostorApp()));
}

class ImpostorApp extends StatelessWidget {
  const ImpostorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Impostor',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const GameRoot(),
    );
  }
}

class GameRoot extends ConsumerStatefulWidget {
  const GameRoot({super.key});

  @override
  ConsumerState<GameRoot> createState() => _GameRootState();
}

class _GameRootState extends ConsumerState<GameRoot> {
  @override
  void initState() {
    super.initState();
    // Try restoring any previous session on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameClientProvider).tryRestoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for server errors and present snackbars
    ref.listen(errorStreamProvider, (prev, next) {
      next.whenData((err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.impostorColor,
            content: Text(
              '[${err.code}] ${err.message}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      });
    });

    // Listen for room_closed event
    ref.listen(roomClosedStreamProvider, (prev, next) {
      next.whenData((closed) {
        ref.read(hostServiceProvider).stopHosting();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surfaceElevated,
            title: const Text('Room Closed'),
            content: Text(closed.reason),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'OK',
                  style: TextStyle(color: AppTheme.primaryLight),
                ),
              ),
            ],
          ),
        );
      });
    });

    // Listen for entering/exiting a room
    ref.listen(roomStateProvider, (prev, next) {
      if (prev?.value == null && next.value != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (prev?.value != null && next.value == null) {
        // Player left or room closed: clean up host service
        ref.read(hostServiceProvider).stopHosting();
      }
    });

    final roomState = ref.watch(roomStateProvider).value;

    // Pick active screen based on server phase state
    Widget activeScreen;
    if (roomState == null) {
      activeScreen = const HomeScreen();
    } else {
      switch (roomState.phase) {
        case 'ROLE_REVEAL':
          activeScreen = const RoleRevealScreen();
          break;
        case 'CLUE_ROUND':
          activeScreen = const ClueRoundScreen();
          break;
        case 'DISCUSSION':
          activeScreen = const DiscussionScreen();
          break;
        case 'VOTING':
          activeScreen = const VotingScreen();
          break;
        case 'IMPOSTOR_GUESS':
        case 'ROUND_END':
          activeScreen = const ResultScreen();
          break;
        case 'LOBBY':
        default:
          activeScreen = const LobbyScreen();
          break;
      }
    }

    return Column(
      children: [
        const ConnectionBanner(),
        Expanded(child: activeScreen),
      ],
    );
  }
}
