import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/protocol_models.dart';
import '../services/game_client.dart';
import '../services/host_service.dart';

/// Singleton GameClient provider.
final gameClientProvider = Provider<GameClient>((ref) {
  final client = GameClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// Stream of ConnectionStatus.
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final client = ref.watch(gameClientProvider);
  return client.statusStream;
});

/// Stream of latest RoomStateModel.
final roomStateProvider = StreamProvider<RoomStateModel?>((ref) {
  final client = ref.watch(gameClientProvider);
  return client.roomStateStream;
});

/// Stream of RoomJoinedModel.
final roomJoinedProvider = StreamProvider<RoomJoinedModel>((ref) {
  final client = ref.watch(gameClientProvider);
  return client.roomJoinedStream;
});

/// Stream of ErrorMessageModel.
final errorStreamProvider = StreamProvider<ErrorMessageModel>((ref) {
  final client = ref.watch(gameClientProvider);
  return client.errorStream;
});

/// Stream of CluePostedModel.
final cluePostedStreamProvider = StreamProvider<CluePostedModel>((ref) {
  final client = ref.watch(gameClientProvider);
  return client.cluePostedStream;
});

/// Stream of RoomClosedModel.
final roomClosedStreamProvider = StreamProvider<RoomClosedModel>((ref) {
  final client = ref.watch(gameClientProvider);
  return client.roomClosedStream;
});

// ============================================================================
// Derived State Selectors
// ============================================================================

/// Current phase string ('LOBBY', 'ROLE_REVEAL', 'CLUE_ROUND', etc.).
final currentPhaseProvider = Provider<String>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.phase ?? 'LOBBY';
});

/// My role string ('CREW', 'IMPOSTOR', or null).
final myRoleProvider = Provider<String?>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.myRole;
});

/// Secret word (null if impostor or during active game).
final myWordProvider = Provider<String?>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.myWord;
});

/// Category name string.
final categoryProvider = Provider<String?>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.category;
});

/// Current list of clues.
final cluesProvider = Provider<List<ClueModel>>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.clues ?? [];
});

/// Current vote progress.
final voteProgressProvider = Provider<VoteProgressModel?>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.voteProgress;
});

/// Latest RoundResultModel.
final roundResultProvider = Provider<RoundResultModel?>((ref) {
  final roomState = ref.watch(roomStateProvider).value;
  return roomState?.roundResult;
});

/// Whether the current local player is the host of the room.
final isHostProvider = Provider<bool>((ref) {
  final client = ref.watch(gameClientProvider);
  final roomState = ref.watch(roomStateProvider).value;
  if (roomState != null) {
    for (final p in roomState.players) {
      if (p.id == roomState.myId) {
        return p.isHost;
      }
    }
  }
  return client.isHost;
});

/// Singleton HostService provider.
final hostServiceProvider = Provider<HostService>((ref) {
  return HostService();
});

/// Notifier for storing the local IP of the host device.
class HostIpNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setIp(String? ip) => state = ip;
}

/// Current resolved local IP of the host device.
final hostIpProvider =
    NotifierProvider<HostIpNotifier, String?>(HostIpNotifier.new);

