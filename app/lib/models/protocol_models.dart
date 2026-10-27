/// Protocol models mirroring docs/PROTOCOL.md specifications exactly.
library;

class PlayerSummary {
  final String id;
  final String name;
  final int score;
  final bool isHost;
  final bool connected;

  const PlayerSummary({
    required this.id,
    required this.name,
    required this.score,
    required this.isHost,
    required this.connected,
  });

  factory PlayerSummary.fromJson(Map<String, dynamic> json) {
    return PlayerSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      isHost: json['is_host'] as bool? ?? false,
      connected: json['connected'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'score': score,
    'is_host': isHost,
    'connected': connected,
  };
}

class GameSettingsModel {
  final int clueRounds;
  final int impostorCount;
  final String category;
  final int discussionTimerSeconds;
  final bool impostorSeesCategory;
  final int turnTimerSeconds;
  final int votingTimerSeconds;
  final int roleRevealTimerSeconds;
  final bool spokenClues;

  const GameSettingsModel({
    this.clueRounds = 2,
    this.impostorCount = 1,
    this.category = 'random',
    this.discussionTimerSeconds = 90,
    this.impostorSeesCategory = true,
    this.turnTimerSeconds = 30,
    this.votingTimerSeconds = 60,
    this.roleRevealTimerSeconds = 45,
    this.spokenClues = false,
  });

  factory GameSettingsModel.fromJson(Map<String, dynamic> json) {
    return GameSettingsModel(
      clueRounds: (json['clue_rounds'] as num?)?.toInt() ?? 2,
      impostorCount: (json['impostor_count'] as num?)?.toInt() ?? 1,
      category: json['category'] as String? ?? 'random',
      discussionTimerSeconds:
          (json['discussion_timer_seconds'] as num?)?.toInt() ?? 90,
      impostorSeesCategory: json['impostor_sees_category'] as bool? ?? true,
      turnTimerSeconds: (json['turn_timer_seconds'] as num?)?.toInt() ?? 30,
      votingTimerSeconds: (json['voting_timer_seconds'] as num?)?.toInt() ?? 60,
      roleRevealTimerSeconds:
          (json['role_reveal_timer_seconds'] as num?)?.toInt() ?? 45,
      spokenClues: json['spoken_clues'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'clue_rounds': clueRounds,
    'impostor_count': impostorCount,
    'category': category,
    'discussion_timer_seconds': discussionTimerSeconds,
    'impostor_sees_category': impostorSeesCategory,
    'turn_timer_seconds': turnTimerSeconds,
    'voting_timer_seconds': votingTimerSeconds,
    'role_reveal_timer_seconds': roleRevealTimerSeconds,
    'spoken_clues': spokenClues,
  };

  GameSettingsModel copyWith({
    int? clueRounds,
    int? impostorCount,
    String? category,
    int? discussionTimerSeconds,
    bool? impostorSeesCategory,
    int? turnTimerSeconds,
    int? votingTimerSeconds,
    int? roleRevealTimerSeconds,
    bool? spokenClues,
  }) {
    return GameSettingsModel(
      clueRounds: clueRounds ?? this.clueRounds,
      impostorCount: impostorCount ?? this.impostorCount,
      category: category ?? this.category,
      discussionTimerSeconds:
          discussionTimerSeconds ?? this.discussionTimerSeconds,
      impostorSeesCategory: impostorSeesCategory ?? this.impostorSeesCategory,
      turnTimerSeconds: turnTimerSeconds ?? this.turnTimerSeconds,
      votingTimerSeconds: votingTimerSeconds ?? this.votingTimerSeconds,
      roleRevealTimerSeconds:
          roleRevealTimerSeconds ?? this.roleRevealTimerSeconds,
      spokenClues: spokenClues ?? this.spokenClues,
    );
  }
}

class ClueModel {
  final String playerId;
  final String word;
  final int roundIndex;
  final double timestamp;

  const ClueModel({
    required this.playerId,
    required this.word,
    required this.roundIndex,
    required this.timestamp,
  });

  factory ClueModel.fromJson(Map<String, dynamic> json) {
    return ClueModel(
      playerId: json['player_id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      roundIndex: (json['round_index'] as num?)?.toInt() ?? 1,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'word': word,
    'round_index': roundIndex,
    'timestamp': timestamp,
  };
}

class VoteProgressModel {
  final int votedCount;
  final int total;

  const VoteProgressModel({required this.votedCount, required this.total});

  factory VoteProgressModel.fromJson(Map<String, dynamic> json) {
    return VoteProgressModel(
      votedCount: (json['voted_count'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'voted_count': votedCount, 'total': total};
}

class RoundResultModel {
  final String? ejectedId;
  final bool? wasImpostor;
  final String outcome;
  final Map<String, String?> votes;
  final String secretWord;
  final String category;
  final List<String> impostorIds;
  final List<ClueModel> clues;
  final Map<String, int> scoreDelta;
  final Map<String, int> scores;
  final String? impostorGuess;
  final bool? guessCorrect;

  const RoundResultModel({
    this.ejectedId,
    this.wasImpostor,
    required this.outcome,
    required this.votes,
    required this.secretWord,
    required this.category,
    required this.impostorIds,
    required this.clues,
    required this.scoreDelta,
    required this.scores,
    this.impostorGuess,
    this.guessCorrect,
  });

  factory RoundResultModel.fromJson(Map<String, dynamic> json) {
    final rawVotes = json['votes'] as Map<String, dynamic>? ?? {};
    final votesMap = rawVotes.map((k, v) => MapEntry(k, v as String?));

    final rawClues = json['clues'] as List<dynamic>? ?? [];
    final cluesList = rawClues
        .map((c) => ClueModel.fromJson(c as Map<String, dynamic>))
        .toList();

    final rawDelta = json['score_delta'] as Map<String, dynamic>? ?? {};
    final deltaMap = rawDelta.map((k, v) => MapEntry(k, (v as num).toInt()));

    final rawScores = json['scores'] as Map<String, dynamic>? ?? {};
    final scoresMap = rawScores.map((k, v) => MapEntry(k, (v as num).toInt()));

    final rawImpostors = json['impostor_ids'] as List<dynamic>? ?? [];
    final impostorsList = rawImpostors.map((e) => e.toString()).toList();

    return RoundResultModel(
      ejectedId: json['ejected_id'] as String?,
      wasImpostor: json['was_impostor'] as bool?,
      outcome: json['outcome'] as String? ?? '',
      votes: votesMap,
      secretWord: json['secret_word'] as String? ?? '',
      category: json['category'] as String? ?? '',
      impostorIds: impostorsList,
      clues: cluesList,
      scoreDelta: deltaMap,
      scores: scoresMap,
      impostorGuess: json['impostor_guess'] as String?,
      guessCorrect: json['guess_correct'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'ejected_id': ejectedId,
    'was_impostor': wasImpostor,
    'outcome': outcome,
    'votes': votes,
    'secret_word': secretWord,
    'category': category,
    'impostor_ids': impostorIds,
    'clues': clues.map((c) => c.toJson()).toList(),
    'score_delta': scoreDelta,
    'scores': scores,
    'impostor_guess': impostorGuess,
    'guess_correct': guessCorrect,
  };
}

class RoomStateModel {
  final String roomCode;
  final String phase;
  final List<PlayerSummary> players;
  final GameSettingsModel settings;
  final String myId;
  final String? myRole;
  final String? myWord;
  final String? category;
  final int roundIndex;
  final List<ClueModel> clues;
  final String? currentTurnPlayerId;
  final int? deadlineEpochMs;
  final bool hasConfirmedRole;
  final VoteProgressModel voteProgress;
  final Map<String, String?>? votes;
  final List<String>? impostorIds;
  final String? caughtImpostorId;
  final RoundResultModel? roundResult;

  const RoomStateModel({
    required this.roomCode,
    required this.phase,
    required this.players,
    required this.settings,
    required this.myId,
    this.myRole,
    this.myWord,
    this.category,
    required this.roundIndex,
    required this.clues,
    this.currentTurnPlayerId,
    this.deadlineEpochMs,
    required this.hasConfirmedRole,
    required this.voteProgress,
    this.votes,
    this.impostorIds,
    this.caughtImpostorId,
    this.roundResult,
  });

  bool get isImpostor => myRole == 'IMPOSTOR';
  bool get isCrew => myRole == 'CREW';
  bool get isMyTurn => currentTurnPlayerId == myId;

  factory RoomStateModel.fromJson(Map<String, dynamic> json) {
    final rawPlayers = json['players'] as List<dynamic>? ?? [];
    final players = rawPlayers
        .map((p) => PlayerSummary.fromJson(p as Map<String, dynamic>))
        .toList();

    final rawClues = json['clues'] as List<dynamic>? ?? [];
    final clues = rawClues
        .map((c) => ClueModel.fromJson(c as Map<String, dynamic>))
        .toList();

    final rawSettings = json['settings'] as Map<String, dynamic>? ?? {};
    final settings = GameSettingsModel.fromJson(rawSettings);

    final rawProg = json['vote_progress'] as Map<String, dynamic>? ?? {};
    final voteProgress = VoteProgressModel.fromJson(rawProg);

    Map<String, String?>? votes;
    if (json['votes'] != null) {
      final rawVotes = json['votes'] as Map<String, dynamic>;
      votes = rawVotes.map((k, v) => MapEntry(k, v as String?));
    }

    List<String>? impostorIds;
    if (json['impostor_ids'] != null) {
      impostorIds = (json['impostor_ids'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }

    RoundResultModel? roundResult;
    if (json['round_result'] != null) {
      roundResult = RoundResultModel.fromJson(
        json['round_result'] as Map<String, dynamic>,
      );
    }

    return RoomStateModel(
      roomCode: json['room_code'] as String? ?? '',
      phase: json['phase'] as String? ?? 'LOBBY',
      players: players,
      settings: settings,
      myId: json['my_id'] as String? ?? '',
      myRole: json['my_role'] as String?,
      myWord: json['my_word'] as String?,
      category: json['category'] as String?,
      roundIndex: (json['round_index'] as num?)?.toInt() ?? 1,
      clues: clues,
      currentTurnPlayerId: json['current_turn_player_id'] as String?,
      deadlineEpochMs: (json['deadline_epoch_ms'] as num?)?.toInt(),
      hasConfirmedRole: json['has_confirmed_role'] as bool? ?? false,
      voteProgress: voteProgress,
      votes: votes,
      impostorIds: impostorIds,
      caughtImpostorId: json['caught_impostor_id'] as String?,
      roundResult: roundResult,
    );
  }

  Map<String, dynamic> toJson() => {
    'room_code': roomCode,
    'phase': phase,
    'players': players.map((p) => p.toJson()).toList(),
    'settings': settings.toJson(),
    'my_id': myId,
    'my_role': myRole,
    'my_word': myWord,
    'category': category,
    'round_index': roundIndex,
    'clues': clues.map((c) => c.toJson()).toList(),
    'current_turn_player_id': currentTurnPlayerId,
    'deadline_epoch_ms': deadlineEpochMs,
    'has_confirmed_role': hasConfirmedRole,
    'vote_progress': voteProgress.toJson(),
    'votes': votes,
    'impostor_ids': impostorIds,
    'caught_impostor_id': caughtImpostorId,
    'round_result': roundResult?.toJson(),
  };
}

class RoomJoinedModel {
  final String code;
  final String playerId;
  final String token;
  final bool isHost;

  const RoomJoinedModel({
    required this.code,
    required this.playerId,
    required this.token,
    required this.isHost,
  });

  factory RoomJoinedModel.fromJson(Map<String, dynamic> json) {
    return RoomJoinedModel(
      code: json['code'] as String? ?? '',
      playerId: json['player_id'] as String? ?? '',
      token: json['token'] as String? ?? '',
      isHost: json['is_host'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'player_id': playerId,
    'token': token,
    'is_host': isHost,
  };
}

class ErrorMessageModel {
  final String code;
  final String message;

  const ErrorMessageModel({required this.code, required this.message});

  factory ErrorMessageModel.fromJson(Map<String, dynamic> json) {
    return ErrorMessageModel(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'An error occurred.',
    );
  }

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

class CluePostedModel {
  final String playerId;
  final String word;
  final int roundIndex;
  final double timestamp;

  const CluePostedModel({
    required this.playerId,
    required this.word,
    required this.roundIndex,
    required this.timestamp,
  });

  factory CluePostedModel.fromJson(Map<String, dynamic> json) {
    return CluePostedModel(
      playerId: json['player_id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      roundIndex: (json['round_index'] as num?)?.toInt() ?? 1,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RoomClosedModel {
  final String reason;

  const RoomClosedModel({required this.reason});

  factory RoomClosedModel.fromJson(Map<String, dynamic> json) {
    return RoomClosedModel(
      reason: json['reason'] as String? ?? 'Room was closed.',
    );
  }
}
