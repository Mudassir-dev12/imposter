"""Network protocol definitions, input validation, and privacy-preserving view building."""

import random
import re
from typing import Any, Dict, List, Optional, Set

from engine.models import Phase, Role

# Ambiguous letters omitted from room codes (avoid O, I, 0, 1)
ALLOWED_ROOM_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


class ProtocolError(Exception):
    """Exception raised for protocol validation errors with a stable error code."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def generate_room_code(rng: Optional[random.Random] = None, length: int = 4) -> str:
    """Generate a clean, unambiguous room code."""
    rand = rng if rng is not None else random
    return "".join(rand.choice(ALLOWED_ROOM_CODE_CHARS) for _ in range(length))


def sanitize_name(name: str) -> str:
    """Sanitize player name: 1 to 16 characters, trimmed."""
    if not isinstance(name, str):
        raise ProtocolError("INVALID_NAME", "Player name must be a string.")
    trimmed = name.strip()
    if len(trimmed) < 1 or len(trimmed) > 16:
        raise ProtocolError("INVALID_NAME", "Player name must be between 1 and 16 characters.")
    return trimmed


def validate_clue(word: str, secret_word: str) -> str:
    """Validate a submitted clue.

    Rules:
    - 1 to 20 characters
    - Single word (no spaces or whitespace)
    - Must not equal the secret word (case-insensitive, trimmed)
    """
    if not isinstance(word, str):
        raise ProtocolError("INVALID_CLUE", "Clue must be a string.")
    cleaned = word.strip()
    if not cleaned or len(cleaned) > 20:
        raise ProtocolError("INVALID_CLUE", "Clue must be between 1 and 20 characters.")
    if re.search(r"\s", cleaned):
        raise ProtocolError("INVALID_CLUE", "Clue must be a single word with no spaces.")
    if cleaned.lower() == secret_word.strip().lower():
        raise ProtocolError("INVALID_CLUE", "Clue cannot be the secret word.")
    return cleaned


def matches_secret_word(guess: str, secret_word: str) -> bool:
    """Check if an impostor's guess matches the secret word.

    Accepts case-insensitive, trimmed strings, and simple plural/singular variations:
    e.g. 'panda' matches 'pandas', 'sandwiches' matches 'sandwich', 'boxes' matches 'box'.
    """
    g = guess.strip().lower()
    s = secret_word.strip().lower()
    if g == s:
        return True

    # Check simple English plural/singular suffixes: -s, -es, -ies
    if g + "s" == s or s + "s" == g:
        return True
    if g + "es" == s or s + "es" == g:
        return True
    if g.endswith("ies") and g[:-3] + "y" == s:
        return True
    if s.endswith("ies") and s[:-3] + "y" == g:
        return True

    return False


def build_player_view(engine: Any, player_id: str) -> Dict[str, Any]:
    """Build a privacy-preserving state dictionary for a specific player.

    CRITICAL SECRECY RULES:
    1. An innocent crew member's view must NEVER contain the impostor(s) identities
       during LOBBY, ROLE_REVEAL, CLUE_ROUND, DISCUSSION, or VOTING.
    2. An impostor's view must NEVER contain the secret word during LOBBY, ROLE_REVEAL,
       CLUE_ROUND, DISCUSSION, VOTING, or IMPOSTOR_GUESS.
    3. During VOTING, only aggregate vote counts (e.g. 3 of 4 voted) are exposed.
       Individual votes are hidden until RESULT/ROUND_END.
    """
    player = engine.get_player(player_id)
    if player is None:
        raise ProtocolError("PLAYER_NOT_FOUND", f"Player {player_id} not found in room.")

    phase = engine.phase
    is_impostor = player.role == Role.IMPOSTOR

    # Players list: public info only
    players_data = [p.to_public_dict() for p in engine.players.values()]

    # Role & secret word visibility
    revealed_end = phase in (Phase.RESULT, Phase.IMPOSTOR_GUESS, Phase.ROUND_END, Phase.GAME_OVER)

    if phase == Phase.LOBBY:
        my_role = None
        my_word = None
        category = None
    elif is_impostor:
        my_role = Role.IMPOSTOR.value
        # Impostor NEVER sees secret word until ROUND_END (even during IMPOSTOR_GUESS they must guess it)
        my_word = engine.secret_word if phase in (Phase.ROUND_END, Phase.GAME_OVER) else None
        category = (
            engine.category
            if (engine.settings.impostor_sees_category or revealed_end)
            else None
        )
    else:  # Innocent Crew
        my_role = Role.CREW.value
        my_word = engine.secret_word
        category = engine.category

    # Impostor identities visibility
    impostor_ids: Optional[List[str]] = None
    if revealed_end:
        impostor_ids = list(engine.impostor_ids)
    elif is_impostor and len(engine.impostor_ids) > 1:
        # Impostors know their fellow impostor(s)
        impostor_ids = list(engine.impostor_ids)

    # Vote progress vs full votes
    vote_progress = {
        "voted_count": len(engine.votes),
        "total": len(engine.players),
    }

    # Only show who voted for whom during RESULT or later
    votes_summary = engine.votes if revealed_end else None

    # Current turn player ID
    current_turn_player_id = engine.current_turn_player_id if phase == Phase.CLUE_ROUND else None

    # Deadline in epoch milliseconds
    deadline_ms = int(engine.current_deadline * 1000) if engine.current_deadline else None

    view: Dict[str, Any] = {
        "room_code": engine.room_code,
        "phase": phase.value,
        "players": players_data,
        "settings": engine.settings.to_dict(),
        "my_id": player.id,
        "my_role": my_role,
        "my_word": my_word,
        "category": category,
        "round_index": engine.current_round_index,
        "clues": [c.to_dict() for c in engine.clues],
        "current_turn_player_id": current_turn_player_id,
        "deadline_epoch_ms": deadline_ms,
        "has_confirmed_role": player.has_confirmed_role,
        "vote_progress": vote_progress,
        "votes": votes_summary,
        "impostor_ids": impostor_ids,
        "caught_impostor_id": engine.caught_impostor_id,
        "round_result": engine.last_round_result.to_dict() if engine.last_round_result and revealed_end else None,
    }

    return view
