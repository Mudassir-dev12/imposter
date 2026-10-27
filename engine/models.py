"""Data models, enums, and dataclasses for the Impostor game engine."""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class Phase(str, Enum):
    """Game phase state machine states."""
    LOBBY = "LOBBY"
    ROLE_REVEAL = "ROLE_REVEAL"
    CLUE_ROUND = "CLUE_ROUND"
    DISCUSSION = "DISCUSSION"
    VOTING = "VOTING"
    RESULT = "RESULT"
    IMPOSTOR_GUESS = "IMPOSTOR_GUESS"
    ROUND_END = "ROUND_END"
    GAME_OVER = "GAME_OVER"


class Role(str, Enum):
    """Player role within a round."""
    CREW = "CREW"
    IMPOSTOR = "IMPOSTOR"


class Outcome(str, Enum):
    """Round resolution outcome."""
    CREW_WIN = "CREW_WIN"
    IMPOSTOR_STEAL_WIN = "IMPOSTOR_STEAL_WIN"
    IMPOSTOR_WIN_INNOCENT_VOTED = "IMPOSTOR_WIN_INNOCENT_VOTED"
    IMPOSTOR_WIN_TIE = "IMPOSTOR_WIN_TIE"
    IMPOSTOR_WIN_NOT_CAUGHT = "IMPOSTOR_WIN_NOT_CAUGHT"


class TimerType(str, Enum):
    """Types of timers scheduled in the MinHeap."""
    TURN_TIMEOUT = "TURN_TIMEOUT"
    DISCUSSION_TIMEOUT = "DISCUSSION_TIMEOUT"
    VOTING_TIMEOUT = "VOTING_TIMEOUT"
    ROLE_REVEAL_TIMEOUT = "ROLE_REVEAL_TIMEOUT"


@dataclass
class GameSettings:
    """Configurable room settings set by the host in the lobby."""
    clue_rounds: int = 2
    impostor_count: int = 1
    category: str = "random"
    discussion_timer_seconds: int = 90
    impostor_sees_category: bool = True
    turn_timer_seconds: int = 30
    voting_timer_seconds: int = 60
    role_reveal_timer_seconds: int = 45
    spoken_clues: bool = False

    def validate(self, player_count: int) -> None:
        """Validate settings against room rules."""
        if not (1 <= self.clue_rounds <= 3):
            raise ValueError("clue_rounds must be between 1 and 3.")
        if self.impostor_count < 1:
            raise ValueError("impostor_count must be at least 1.")
        if self.impostor_count > 2:
            raise ValueError("impostor_count cannot exceed 2.")
        if self.impostor_count == 2 and player_count < 7:
            raise ValueError("2 impostors are only allowed with 7 or more players.")
        if self.discussion_timer_seconds < 0:
            raise ValueError("discussion_timer_seconds cannot be negative.")
        if self.turn_timer_seconds < 0:
            raise ValueError("turn_timer_seconds cannot be negative.")
        if 0 < self.turn_timer_seconds < 5:
            raise ValueError("turn_timer_seconds must be at least 5 seconds if enabled.")

    def to_dict(self) -> Dict[str, Any]:
        return {
            "clue_rounds": self.clue_rounds,
            "impostor_count": self.impostor_count,
            "category": self.category,
            "discussion_timer_seconds": self.discussion_timer_seconds,
            "impostor_sees_category": self.impostor_sees_category,
            "turn_timer_seconds": self.turn_timer_seconds,
            "voting_timer_seconds": self.voting_timer_seconds,
            "role_reveal_timer_seconds": self.role_reveal_timer_seconds,
            "spoken_clues": self.spoken_clues,
        }


@dataclass
class Player:
    """Represents a connected or disconnected participant in a room."""
    id: str
    name: str
    token: str
    role: Role = Role.CREW
    score: int = 0
    is_host: bool = False
    connected: bool = True
    has_confirmed_role: bool = False

    def to_public_dict(self) -> Dict[str, Any]:
        """Public player info safe to broadcast (excludes secret role & token)."""
        return {
            "id": self.id,
            "name": self.name,
            "score": self.score,
            "is_host": self.is_host,
            "connected": self.connected,
        }


@dataclass
class Clue:
    """A single-word clue submitted by a player during a clue round."""
    player_id: str
    word: str
    round_index: int
    timestamp: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "player_id": self.player_id,
            "word": self.word,
            "round_index": self.round_index,
            "timestamp": self.timestamp,
        }


@dataclass
class TimerEvent:
    """Event payload stored inside the MinHeap keyed by expiry timestamp."""
    timer_type: TimerType
    phase: Phase
    deadline_epoch_s: float
    item_id: str
    player_id: Optional[str] = None
    round_index: int = 0


@dataclass
class RoundResult:
    """Summary of round outcome, secret roles, words, votes, and score updates."""
    ejected_id: Optional[str]
    was_impostor: Optional[bool]
    outcome: Outcome
    votes: Dict[str, Optional[str]]
    secret_word: str
    category: str
    impostor_ids: List[str]
    clues: List[Dict[str, Any]]
    score_delta: Dict[str, int]
    scores: Dict[str, int]
    impostor_guess: Optional[str] = None
    guess_correct: Optional[bool] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ejected_id": self.ejected_id,
            "was_impostor": self.was_impostor,
            "outcome": self.outcome.value,
            "votes": self.votes,
            "secret_word": self.secret_word,
            "category": self.category,
            "impostor_ids": self.impostor_ids,
            "clues": self.clues,
            "score_delta": self.score_delta,
            "scores": self.scores,
            "impostor_guess": self.impostor_guess,
            "guess_correct": self.guess_correct,
        }
