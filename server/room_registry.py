"""Room Registry mapping room codes to GameEngine instances using custom ChainedHashTable."""

import random
from typing import Callable, List, Optional

from engine.game import GameEngine
from engine.models import GameSettings
from engine.protocol import generate_room_code
from engine.structures.hash_table import ChainedHashTable
from engine.words import WordRepository


class RoomRegistry:
    """Manages all active game rooms keyed by 4-letter room code.

    Backbone data structure: custom ChainedHashTable (DSA course requirement).
    """

    def __init__(self, word_repo: Optional[WordRepository] = None) -> None:
        self.word_repo: WordRepository = word_repo or WordRepository()
        self._table: ChainedHashTable[str, GameEngine] = ChainedHashTable[str, GameEngine]()

    def create_room(
        self,
        settings: Optional[GameSettings] = None,
        rng: Optional[random.Random] = None,
        time_provider: Optional[Callable[[], float]] = None,
        custom_code: Optional[str] = None,
    ) -> GameEngine:
        """Create a new room, store it in the ChainedHashTable, and return the engine."""
        rand = rng or random.Random()
        # Find unused room code
        if custom_code:
            code = custom_code.upper()
        else:
            for _ in range(100):
                candidate = generate_room_code(rand)
                if not self._table.contains(candidate):
                    code = candidate
                    break
            else:
                raise RuntimeError("Failed to generate a unique room code after 100 attempts.")

        engine = GameEngine(
            room_code=code,
            settings=settings or GameSettings(),
            word_repo=self.word_repo,
            rng=rand,
            time_provider=time_provider,
        )
        self._table.put(code, engine)
        return engine

    def get_room(self, room_code: str) -> Optional[GameEngine]:
        """Retrieve GameEngine by room code (case-insensitive)."""
        return self._table.get(room_code.strip().upper())

    def has_room(self, room_code: str) -> bool:
        """Check if room exists in the registry."""
        return self._table.contains(room_code.strip().upper())

    def remove_room(self, room_code: str) -> bool:
        """Remove a room from registry when game ends or host disconnects."""
        return self._table.remove(room_code.strip().upper())

    def all_rooms(self) -> List[GameEngine]:
        """Return a list of all active GameEngine instances."""
        return self._table.values()

    def all_codes(self) -> List[str]:
        """Return a list of all active room codes."""
        return self._table.keys()

    def clear(self) -> None:
        """Clear all active rooms from the registry."""
        self._table.clear()

    def __len__(self) -> int:
        return len(self._table)
