# Impostor Network Protocol Specification

All communication between clients and the Impostor server occurs over WebSocket connections using JSON text frames.

---

## 1. Frame Envelope Structure

Every message sent by client or server adheres to the following envelope:

```json
{
  "type": "<message_name>",
  "id": "<optional_client_request_id>",
  "data": { ... }
}
```

- **`type`** *(string, required)*: The identifier of the action or event.
- **`id`** *(string, optional)*: Correlates request and response frames. When provided by a client, the server echoes this `id` in the direct response or error frame.
- **`data`** *(object, required)*: The payload dictionary specific to `type`.

---

## 2. Client $\rightarrow$ Server Messages

### 2.1 `create_room`
Creates a new game room and assigns the sender as the host.

```json
{
  "type": "create_room",
  "id": "req_1",
  "data": {
    "name": "Alice",
    "settings": {
      "clue_rounds": 2,
      "impostor_count": 1,
      "category": "Animals",
      "discussion_timer_seconds": 90,
      "impostor_sees_category": true,
      "turn_timer_seconds": 30,
      "voting_timer_seconds": 60
    }
  }
}
```

### 2.2 `join_room`
Joins an existing room in the `LOBBY` phase.

```json
{
  "type": "join_room",
  "id": "req_2",
  "data": {
    "code": "ABCD",
    "name": "Bob"
  }
}
```

### 2.3 `rejoin`
Re-authenticates a disconnected player into an active game session without state loss.

```json
{
  "type": "rejoin",
  "id": "req_3",
  "data": {
    "code": "ABCD",
    "player_id": "p_2_1842",
    "token": "tok_948271"
  }
}
```

### 2.4 `update_settings`
Updates room settings. Can only be invoked by the host while in `LOBBY`.

```json
{
  "type": "update_settings",
  "data": {
    "settings": {
      "clue_rounds": 3,
      "category": "random"
    }
  }
}
```

### 2.5 `start_game`
Starts the game. Requires at least 3 players. Host only, in `LOBBY`.

```json
{
  "type": "start_game",
  "data": {}
}
```

### 2.6 `confirm_role_seen`
Acknowledges that the player has viewed their private role card in `ROLE_REVEAL`.

```json
{
  "type": "confirm_role_seen",
  "data": {}
}
```

### 2.7 `submit_clue`
Submits a single-word clue on the player's turn during `CLUE_ROUND` (when `spoken_clues` is disabled).

```json
{
  "type": "submit_clue",
  "data": {
    "word": "Trunk"
  }
}
```

### 2.8 `end_turn`
Ends the active player's turn during `CLUE_ROUND` when `spoken_clues` is enabled (the clue was spoken aloud).

```json
{
  "type": "end_turn",
  "data": {}
}
```

### 2.9 `skip_discussion`
Host command to end discussion immediately and proceed to `VOTING`.

```json
{
  "type": "skip_discussion",
  "data": {}
}
```

### 2.9 `cast_vote`
Casts or updates a player's secret ballot during `VOTING`. Pass `null` or omit `target_id` to abstain.

```json
{
  "type": "cast_vote",
  "data": {
    "target_id": "p_3_5914"
  }
}
```

### 2.10 `impostor_guess`
Caught impostor's single chance to steal the win by guessing the secret word.

```json
{
  "type": "impostor_guess",
  "data": {
    "word": "Elephant"
  }
}
```

### 2.11 `play_again`
Host command to reset the room back to `LOBBY` while preserving scores. `ROUND_END` only.

```json
{
  "type": "play_again",
  "data": {}
}
```

### 2.12 `kick_player`
Host command in `LOBBY` to kick a player.

```json
{
  "type": "kick_player",
  "data": {
    "player_id": "p_4_8812"
  }
}
```

### 2.13 `leave`
Voluntarily leave the room.

```json
{
  "type": "leave",
  "data": {}
}
```

### 2.14 `ping`
Connection heartbeat.

```json
{
  "type": "ping",
  "data": {}
}
```

---

## 3. Server $\rightarrow$ Client Messages

### 3.1 `room_joined`
Sent directly to the client upon successful creation, join, or rejoin.

```json
{
  "type": "room_joined",
  "id": "req_1",
  "data": {
    "code": "ABCD",
    "player_id": "p_1_3491",
    "token": "tok_582914",
    "is_host": true
  }
}
```

### 3.2 `room_state` (Personalized Privacy View)
Broadcast to each connected player upon every state mutation. Each player receives an independently calculated view constructed by `build_player_view()`.

#### Innocent Crew Member View:
```json
{
  "type": "room_state",
  "data": {
    "room_code": "ABCD",
    "phase": "CLUE_ROUND",
    "players": [
      {"id": "p_1_3491", "name": "Alice", "score": 0, "is_host": true, "connected": true},
      {"id": "p_2_1842", "name": "Bob", "score": 0, "is_host": false, "connected": true},
      {"id": "p_3_5914", "name": "Charlie", "score": 0, "is_host": false, "connected": true}
    ],
    "settings": {
      "clue_rounds": 2,
      "impostor_count": 1,
      "category": "Animals",
      "discussion_timer_seconds": 90,
      "impostor_sees_category": true,
      "turn_timer_seconds": 30,
      "voting_timer_seconds": 60,
      "role_reveal_timer_seconds": 45
    },
    "my_id": "p_1_3491",
    "my_role": "CREW",
    "my_word": "Elephant",
    "category": "Animals",
    "round_index": 1,
    "clues": [
      {"player_id": "p_1_3491", "word": "Gray", "round_index": 1, "timestamp": 1729761234.5}
    ],
    "current_turn_player_id": "p_2_1842",
    "deadline_epoch_ms": 1729761264500,
    "has_confirmed_role": true,
    "vote_progress": {"voted_count": 0, "total": 3},
    "votes": null,
    "impostor_ids": null,
    "caught_impostor_id": null,
    "round_result": null
  }
}
```

#### Impostor View (Zero Word Leakage):
```json
{
  "type": "room_state",
  "data": {
    "room_code": "ABCD",
    "phase": "CLUE_ROUND",
    "players": [ ... ],
    "settings": { ... },
    "my_id": "p_2_1842",
    "my_role": "IMPOSTOR",
    "my_word": null,
    "category": "Animals",
    "round_index": 1,
    "clues": [ ... ],
    "current_turn_player_id": "p_2_1842",
    "deadline_epoch_ms": 1729761264500,
    "has_confirmed_role": true,
    "vote_progress": {"voted_count": 0, "total": 3},
    "votes": null,
    "impostor_ids": null,
    "caught_impostor_id": null,
    "round_result": null
  }
}
```

### 3.3 `clue_posted`
Broadcast when a player submits a clue.

```json
{
  "type": "clue_posted",
  "data": {
    "player_id": "p_1_3491",
    "word": "Gray",
    "round_index": 1,
    "timestamp": 1729761234.5
  }
}
```

### 3.4 `room_closed`
Broadcast to remaining participants if the host leaves or disconnects.

```json
{
  "type": "room_closed",
  "data": {
    "reason": "Host disconnected. Room has closed."
  }
}
```

### 3.5 `error`
Sent directly when an action fails validation or violates rules.

```json
{
  "type": "error",
  "id": "req_2",
  "data": {
    "code": "ROOM_NOT_FOUND",
    "message": "Room 'ABCD' does not exist."
  }
}
```

### 3.6 `pong`
Heartbeat response.

```json
{
  "type": "pong",
  "data": {}
}
```

---

## 4. Stable Error Codes

| Error Code | Meaning |
| :--- | :--- |
| `INVALID_JSON` | Frame is not valid JSON text. |
| `FRAME_TOO_LARGE` | Frame exceeds 64 KB limit. |
| `RATE_LIMITED` | Connection exceeded request rate limit (>25 req/sec). |
| `UNKNOWN_TYPE` | Unrecognized message type string. |
| `INVALID_PAYLOAD` | Missing required payload object or fields. |
| `INVALID_NAME` | Player name not between 1 and 16 characters or malformed. |
| `NAME_TAKEN` | Another player in the room already has this name. |
| `ROOM_NOT_FOUND` | Provided room code does not exist. |
| `ROOM_FULL` | Room reached maximum capacity (10 players). |
| `NOT_IN_ROOM` | Client attempted a room action without joining first. |
| `NOT_HOST` | Attempted a host-only action (start game, kick, skip, settings). |
| `WRONG_PHASE` | Action is not permitted in the current game phase. |
| `NOT_YOUR_TURN` | Submitted a clue when it was another player's turn. |
| `INVALID_CLUE` | Clue has spaces, is too long, or equals the secret word. |
| `INVALID_ACTION` | Self-voting or illegal ballot. |
| `NOT_ENOUGH_PLAYERS` | Attempted to start game with fewer than 3 players. |
| `INVALID_TOKEN` | Token does not match player record during rejoin. |
| `KICKED` | The host kicked this player. |
