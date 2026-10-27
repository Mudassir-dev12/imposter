"""Core Game Engine for Impostor.

Implements the complete phase state machine, turn rotation via custom CircularLinkedList,
timer management via custom MinHeap, and action queuing via custom Queue.
Zero third-party dependencies, 100% Python 3.12 compatible.
"""

from collections import Counter
import random
import time
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from engine.models import (
    Clue,
    GameSettings,
    Outcome,
    Phase,
    Player,
    Role,
    RoundResult,
    TimerEvent,
    TimerType,
)
from engine.protocol import (
    ProtocolError,
    generate_room_code,
    matches_secret_word,
    sanitize_name,
    validate_clue,
)
from engine.structures.circular_linked_list import CircularLinkedList
from engine.structures.min_heap import MinHeap
from engine.structures.queue import Queue
from engine.words import WordRepository


class GameEngine:
    """Impostor Room State Machine and Engine."""

    def __init__(
        self,
        room_code: Optional[str] = None,
        settings: Optional[GameSettings] = None,
        word_repo: Optional[WordRepository] = None,
        rng: Optional[random.Random] = None,
        time_provider: Optional[Callable[[], float]] = None,
    ) -> None:
        self.rng: random.Random = rng if rng is not None else random.Random()
        self.time_provider: Callable[[], float] = time_provider if time_provider is not None else time.time
        self.word_repo: WordRepository = word_repo if word_repo is not None else WordRepository()

        self.room_code: str = room_code or generate_room_code(self.rng)
        self.settings: GameSettings = settings or GameSettings()
        self.phase: Phase = Phase.LOBBY

        # Player storage: player_id -> Player
        self.players: Dict[str, Player] = {}
        self.host_id: Optional[str] = None

        # Data structures
        self._turn_order: CircularLinkedList[str] = CircularLinkedList[str]()
        self._timer_heap: MinHeap[TimerEvent] = MinHeap[TimerEvent]()
        self._action_queue: Queue[Tuple[str, Callable[..., Any], Tuple[Any, ...], Dict[str, Any]]] = Queue()

        # Round state
        self.secret_word: str = ""
        self.category: str = ""
        self.impostor_ids: List[str] = []
        self.caught_impostor_id: Optional[str] = None
        self.uncaught_impostors: Set[str] = set()

        self.current_round_index: int = 1
        self._turns_taken_this_round: int = 0
        self.clues: List[Clue] = []

        # Voting state: voter_id -> target_id (or None for abstain)
        self.votes: Dict[str, Optional[str]] = {}
        self.vote_timestamps: Dict[str, float] = {}  # voter_id -> timestamp (for earliest correct vote bonus)

        # Round history
        self.last_round_result: Optional[RoundResult] = None
        self.current_deadline: Optional[float] = None

    # =========================================================================
    # Time & Timer Helpers (MinHeap integration)
    # =========================================================================

    def current_time(self) -> float:
        """Return current timestamp using time_provider."""
        return self.time_provider()

    def _schedule_timer(self, timer_type: TimerType, duration_seconds: float, player_id: Optional[str] = None) -> None:
        """Schedule a timer in the custom MinHeap."""
        if duration_seconds <= 0:
            return

        now = self.current_time()
        deadline = now + duration_seconds
        item_id = f"{timer_type.value}_{player_id or 'phase'}"
        event = TimerEvent(
            timer_type=timer_type,
            phase=self.phase,
            deadline_epoch_s=deadline,
            item_id=item_id,
            player_id=player_id,
            round_index=self.current_round_index,
        )
        self._timer_heap.push(key=deadline, value=event, item_id=item_id)
        self.current_deadline = deadline

    def _cancel_timer(self, timer_type: TimerType, player_id: Optional[str] = None) -> None:
        """Cancel a pending timer in the custom MinHeap."""
        item_id = f"{timer_type.value}_{player_id or 'phase'}"
        self._timer_heap.remove(item_id)
        if not self._timer_heap.is_empty():
            self.current_deadline = self._timer_heap.peek()[0]
        else:
            self.current_deadline = None

    def tick(self, current_time: Optional[float] = None) -> List[TimerEvent]:
        """Process any expired timers in the MinHeap and return triggered events."""
        now = current_time if current_time is not None else self.current_time()
        fired_events: List[TimerEvent] = []

        while not self._timer_heap.is_empty():
            min_key, event = self._timer_heap.peek()
            if min_key <= now:
                self._timer_heap.pop_min()
                # Verify event is still relevant to current phase
                if event.phase == self.phase:
                    self._handle_timer_expired(event)
                    fired_events.append(event)
            else:
                break

        if not self._timer_heap.is_empty():
            self.current_deadline = self._timer_heap.peek()[0]
        else:
            self.current_deadline = None

        return fired_events

    def _handle_timer_expired(self, event: TimerEvent) -> None:
        """Dispatch timer expiration logic."""
        if event.timer_type == TimerType.ROLE_REVEAL_TIMEOUT:
            if self.phase == Phase.ROLE_REVEAL:
                self._start_clue_rounds()

        elif event.timer_type == TimerType.TURN_TIMEOUT:
            if self.phase == Phase.CLUE_ROUND and event.player_id == self.current_turn_player_id:
                # Auto-skip AFK/disconnected player's turn
                self._record_clue(event.player_id, "[skipped]")

        elif event.timer_type == TimerType.DISCUSSION_TIMEOUT:
            if self.phase == Phase.DISCUSSION:
                self._start_voting()

        elif event.timer_type == TimerType.VOTING_TIMEOUT:
            if self.phase == Phase.VOTING:
                self._conclude_voting()

    # =========================================================================
    # Action Queue Processing (Queue integration)
    # =========================================================================

    def enqueue_action(self, action_name: str, fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
        """Enqueue an action into the custom Queue and execute queued actions in FIFO order."""
        self._action_queue.enqueue((action_name, fn, args, kwargs))
        result = None
        while not self._action_queue.is_empty():
            _, act_fn, act_args, act_kwargs = self._action_queue.dequeue()
            result = act_fn(*act_args, **act_kwargs)
        return result

    # =========================================================================
    # Lobby Phase
    # =========================================================================

    def get_player(self, player_id: str) -> Optional[Player]:
        return self.players.get(player_id)

    @property
    def current_turn_player_id(self) -> Optional[str]:
        if self.phase == Phase.CLUE_ROUND and not self._turn_order.is_empty():
            return self._turn_order.peek()
        return None

    def add_player(self, name: str, token: Optional[str] = None) -> Tuple[Player, str]:
        """Add a new player to the room in LOBBY phase."""
        if self.phase != Phase.LOBBY:
            raise ProtocolError("WRONG_PHASE", "Cannot join game in progress.")
        if len(self.players) >= 10:
            raise ProtocolError("ROOM_FULL", "Room is full (maximum 10 players).")

        clean_name = sanitize_name(name)
        for existing in self.players.values():
            if existing.name.lower() == clean_name.lower():
                raise ProtocolError("NAME_TAKEN", f"The name '{clean_name}' is already taken.")

        player_id = f"p_{len(self.players) + 1}_{self.rng.randint(1000, 9999)}"
        player_token = token or f"tok_{self.rng.randint(100000, 999999)}"
        is_first = len(self.players) == 0

        player = Player(
            id=player_id,
            name=clean_name,
            token=player_token,
            is_host=is_first,
            connected=True,
        )
        self.players[player_id] = player
        if is_first:
            self.host_id = player_id

        return player, player_token

    def remove_player(self, player_id: str, requester_id: Optional[str] = None) -> None:
        """Remove a player from the room (kick or voluntary leave)."""
        player = self.players.get(player_id)
        if not player:
            return

        if requester_id and requester_id != player_id:
            if requester_id != self.host_id:
                raise ProtocolError("NOT_HOST", "Only the host can kick players.")
            if self.phase != Phase.LOBBY:
                raise ProtocolError("WRONG_PHASE", "Players can only be kicked in the lobby.")

        del self.players[player_id]
        self._turn_order.remove(player_id)

        # Host migration if host leaves
        if player.is_host and self.players:
            new_host = next(iter(self.players.values()))
            new_host.is_host = True
            self.host_id = new_host.id

    def update_settings(self, requester_id: str, new_settings: Dict[str, Any]) -> None:
        """Update room settings (host only, lobby only)."""
        if self.phase != Phase.LOBBY:
            raise ProtocolError("WRONG_PHASE", "Settings can only be changed in the lobby.")
        if requester_id != self.host_id:
            raise ProtocolError("NOT_HOST", "Only the host can update room settings.")

        for key, val in new_settings.items():
            if hasattr(self.settings, key):
                setattr(self.settings, key, val)

        self.settings.validate(len(self.players))

    def start_game(self, requester_id: str) -> None:
        """Start game from LOBBY. Transitions to ROLE_REVEAL."""
        if self.phase != Phase.LOBBY:
            raise ProtocolError("WRONG_PHASE", "Game has already started.")
        if requester_id != self.host_id:
            raise ProtocolError("NOT_HOST", "Only the host can start the game.")

        player_count = len(self.players)
        if player_count < 3:
            raise ProtocolError("NOT_ENOUGH_PLAYERS", "At least 3 players are required to start.")

        self.settings.validate(player_count)

        # Pick secret word and category
        self.category, self.secret_word = self.word_repo.pick_word(
            category=self.settings.category,
            rng=self.rng,
        )

        # Assign roles
        all_ids = list(self.players.keys())
        self.rng.shuffle(all_ids)
        impostor_count = self.settings.impostor_count
        self.impostor_ids = all_ids[:impostor_count]
        self.uncaught_impostors = set(self.impostor_ids)

        for p_id, player in self.players.items():
            player.role = Role.IMPOSTOR if p_id in self.impostor_ids else Role.CREW
            player.has_confirmed_role = False

        # Build turn order circular linked list
        self._turn_order.clear()
        # Seat order is shuffled for variety
        seat_order = list(all_ids)
        self.rng.shuffle(seat_order)
        for s_id in seat_order:
            self._turn_order.append(s_id)

        # Reset round tracking
        self.clues.clear()
        self.votes.clear()
        self.vote_timestamps.clear()
        self.caught_impostor_id = None
        self.current_round_index = 1
        self._turns_taken_this_round = 0

        # Transition to ROLE_REVEAL
        self.phase = Phase.ROLE_REVEAL
        self._schedule_timer(
            TimerType.ROLE_REVEAL_TIMEOUT,
            self.settings.role_reveal_timer_seconds,
        )

    # =========================================================================
    # Role Reveal Phase
    # =========================================================================

    def confirm_role_seen(self, player_id: str) -> bool:
        """Acknowledge private role card. Phase advances when all connected confirm."""
        if self.phase != Phase.ROLE_REVEAL:
            raise ProtocolError("WRONG_PHASE", "Cannot confirm role outside ROLE_REVEAL phase.")

        player = self.players.get(player_id)
        if not player:
            raise ProtocolError("PLAYER_NOT_FOUND", "Player not found.")

        player.has_confirmed_role = True

        # Check if all connected players have confirmed
        all_confirmed = all(p.has_confirmed_role for p in self.players.values() if p.connected)
        if all_confirmed:
            self._cancel_timer(TimerType.ROLE_REVEAL_TIMEOUT)
            self._start_clue_rounds()
            return True

        return False

    # =========================================================================
    # Clue Round Phase (CircularLinkedList integration)
    # =========================================================================

    def _start_clue_rounds(self) -> None:
        """Enter CLUE_ROUND phase."""
        self.phase = Phase.CLUE_ROUND
        self.current_round_index = 1
        self._turns_taken_this_round = 0
        self._schedule_current_turn_timer()

    def _schedule_current_turn_timer(self) -> None:
        """Schedule turn deadline timer for active player in MinHeap."""
        current_id = self.current_turn_player_id
        if current_id and self.settings.turn_timer_seconds > 0:
            self._schedule_timer(
                TimerType.TURN_TIMEOUT,
                self.settings.turn_timer_seconds,
                player_id=current_id,
            )

    def submit_clue(self, player_id: str, word: str) -> Clue:
        """Submit a single-word clue on player's turn."""
        if self.phase != Phase.CLUE_ROUND:
            raise ProtocolError("WRONG_PHASE", "Clues can only be submitted during CLUE_ROUND.")

        if self.settings.spoken_clues:
            raise ProtocolError("SPOKEN_CLUES_ENABLED", "Typed clues are disabled when spoken_clues is enabled. Use end_turn.")

        if player_id != self.current_turn_player_id:
            raise ProtocolError("NOT_YOUR_TURN", "It is not your turn to submit a clue.")

        validated_word = validate_clue(word, self.secret_word)
        return self._record_clue(player_id, validated_word)

    def end_turn(self, player_id: str) -> Clue:
        """End turn in spoken_clues mode where the clue is spoken out loud."""
        if self.phase != Phase.CLUE_ROUND:
            raise ProtocolError("WRONG_PHASE", "Turns can only be ended during CLUE_ROUND.")

        if not self.settings.spoken_clues:
            raise ProtocolError("SPOKEN_CLUES_DISABLED", "end_turn is only available when spoken_clues is enabled.")

        if player_id != self.current_turn_player_id:
            raise ProtocolError("NOT_YOUR_TURN", "It is not your turn to end the turn.")

        return self._record_clue(player_id, "[spoken]")

    def _record_clue(self, player_id: str, word: str) -> Clue:
        """Save clue and rotate turn order."""
        self._cancel_timer(TimerType.TURN_TIMEOUT, player_id=player_id)

        clue = Clue(
            player_id=player_id,
            word=word,
            round_index=self.current_round_index,
            timestamp=self.current_time(),
        )
        self.clues.append(clue)
        self._turns_taken_this_round += 1

        total_players = len(self._turn_order)

        # Check if all players have given a clue for the current round
        if self._turns_taken_this_round >= total_players:
            if self.current_round_index < self.settings.clue_rounds:
                # Proceed to next clue round
                self.current_round_index += 1
                self._turns_taken_this_round = 0
                self._turn_order.next()
                self._schedule_current_turn_timer()
            else:
                # All clue rounds completed -> move to DISCUSSION
                self._start_discussion()
        else:
            # Advance to next player
            self._turn_order.next()
            self._schedule_current_turn_timer()

        return clue

    # =========================================================================
    # Discussion Phase
    # =========================================================================

    def _start_discussion(self) -> None:
        """Enter DISCUSSION phase."""
        self.phase = Phase.DISCUSSION
        if self.settings.discussion_timer_seconds > 0:
            self._schedule_timer(
                TimerType.DISCUSSION_TIMEOUT,
                self.settings.discussion_timer_seconds,
            )

    def skip_discussion(self, requester_id: str) -> None:
        """Host ends discussion early."""
        if self.phase != Phase.DISCUSSION:
            raise ProtocolError("WRONG_PHASE", "Cannot skip discussion when not in DISCUSSION phase.")
        if requester_id != self.host_id:
            raise ProtocolError("NOT_HOST", "Only the host can skip discussion.")

        self._cancel_timer(TimerType.DISCUSSION_TIMEOUT)
        self._start_voting()

    # =========================================================================
    # Voting Phase
    # =========================================================================

    def _start_voting(self) -> None:
        """Enter VOTING phase."""
        self.phase = Phase.VOTING
        self.votes.clear()
        self.vote_timestamps.clear()
        self._schedule_timer(
            TimerType.VOTING_TIMEOUT,
            self.settings.voting_timer_seconds,
        )

    def cast_vote(self, voter_id: str, target_id: Optional[str]) -> bool:
        """Cast or change vote (target_id=None means abstain). Returns True if voting concluded."""
        if self.phase != Phase.VOTING:
            raise ProtocolError("WRONG_PHASE", "Votes can only be cast during VOTING phase.")
        if voter_id not in self.players:
            raise ProtocolError("PLAYER_NOT_FOUND", "Voter not in room.")
        if target_id is not None:
            if target_id not in self.players:
                raise ProtocolError("PLAYER_NOT_FOUND", "Voted target not in room.")
            if target_id == voter_id:
                raise ProtocolError("INVALID_ACTION", "Players cannot vote for themselves.")

        self.votes[voter_id] = target_id
        self.vote_timestamps[voter_id] = self.current_time()

        # Check if all connected players have voted
        connected_ids = {p.id for p in self.players.values() if p.connected}
        if connected_ids.issubset(set(self.votes.keys())):
            self._cancel_timer(TimerType.VOTING_TIMEOUT)
            self._conclude_voting()
            return True

        return False

    def _conclude_voting(self) -> None:
        """Tally votes, determine outcome, or handle second round of 2-impostor game."""
        # Tally non-null votes
        vote_counts: Counter[str] = Counter()
        for target in self.votes.values():
            if target is not None:
                vote_counts[target] += 1

        if not vote_counts:
            # Everyone abstained -> Impostor win tie
            self._resolve_round(ejected_id=None, outcome=Outcome.IMPOSTOR_WIN_TIE)
            return

        most_common = vote_counts.most_common()
        top_target, top_votes = most_common[0]

        # Check for tie at the top
        if len(most_common) > 1 and most_common[1][1] == top_votes:
            # Plurality tie = nobody ejected and impostor wins
            self._resolve_round(ejected_id=None, outcome=Outcome.IMPOSTOR_WIN_TIE)
            return

        # Top target is ejected
        ejected_player = self.players.get(top_target)
        was_impostor = ejected_player.role == Role.IMPOSTOR if ejected_player else False

        if not was_impostor:
            # Innocent crew member was voted out -> Impostors win
            self._resolve_round(
                ejected_id=top_target,
                outcome=Outcome.IMPOSTOR_WIN_INNOCENT_VOTED,
                was_impostor=False,
            )
            return

        # Top target WAS an impostor
        self.uncaught_impostors.discard(top_target)
        self.caught_impostor_id = top_target

        if self.uncaught_impostors:
            # 2-impostor game: one impostor caught, one remaining!
            # Crew gets a second brief discussion & vote
            self.phase = Phase.DISCUSSION
            self._start_voting()
            return

        # All impostors caught -> Give caught impostor a chance to guess secret word
        self.phase = Phase.IMPOSTOR_GUESS
        # Set a 30s guess timer
        self._schedule_timer(TimerType.TURN_TIMEOUT, 30.0, player_id=top_target)

    # =========================================================================
    # Impostor Guess Phase
    # =========================================================================

    def submit_impostor_guess(self, player_id: str, guess_word: str) -> bool:
        """Caught impostor attempts to guess secret word and steal win."""
        if self.phase != Phase.IMPOSTOR_GUESS:
            raise ProtocolError("WRONG_PHASE", "Impostor guess only allowed during IMPOSTOR_GUESS phase.")

        if player_id != self.caught_impostor_id:
            raise ProtocolError("NOT_HOST", "Only the caught impostor can guess the word.")

        self._cancel_timer(TimerType.TURN_TIMEOUT, player_id=player_id)
        is_correct = matches_secret_word(guess_word, self.secret_word)

        if is_correct:
            outcome = Outcome.IMPOSTOR_STEAL_WIN
        else:
            outcome = Outcome.CREW_WIN

        self._resolve_round(
            ejected_id=self.caught_impostor_id,
            outcome=outcome,
            was_impostor=True,
            impostor_guess=guess_word,
            guess_correct=is_correct,
        )
        return is_correct

    # =========================================================================
    # Round Resolution & Scoring
    # =========================================================================

    def _resolve_round(
        self,
        ejected_id: Optional[str],
        outcome: Outcome,
        was_impostor: Optional[bool] = None,
        impostor_guess: Optional[str] = None,
        guess_correct: Optional[bool] = None,
    ) -> RoundResult:
        """Compute scores and finalize round into ROUND_END phase."""
        self.phase = Phase.ROUND_END

        score_deltas: Dict[str, int] = {p_id: 0 for p_id in self.players}

        if outcome == Outcome.CREW_WIN:
            # +2 to each crew member
            for p_id, p in self.players.items():
                if p.role == Role.CREW:
                    score_deltas[p_id] += 2

            # +1 bonus to whoever voted for the impostor first
            if self.caught_impostor_id:
                earliest_voter: Optional[str] = None
                earliest_time = float("inf")
                for voter_id, target in self.votes.items():
                    if target == self.caught_impostor_id and voter_id in self.vote_timestamps:
                        if self.vote_timestamps[voter_id] < earliest_time:
                            earliest_time = self.vote_timestamps[voter_id]
                            earliest_voter = voter_id

                if earliest_voter and earliest_voter in score_deltas:
                    score_deltas[earliest_voter] += 1

        elif outcome in (Outcome.IMPOSTOR_WIN_INNOCENT_VOTED, Outcome.IMPOSTOR_WIN_TIE, Outcome.IMPOSTOR_WIN_NOT_CAUGHT):
            # +3 to each impostor
            for imp_id in self.impostor_ids:
                if imp_id in score_deltas:
                    score_deltas[imp_id] += 3

        elif outcome == Outcome.IMPOSTOR_STEAL_WIN:
            # +2 to each impostor for stealing win
            for imp_id in self.impostor_ids:
                if imp_id in score_deltas:
                    score_deltas[imp_id] += 2

        # Apply score deltas
        for p_id, delta in score_deltas.items():
            self.players[p_id].score += delta

        self.last_round_result = RoundResult(
            ejected_id=ejected_id,
            was_impostor=was_impostor,
            outcome=outcome,
            votes=dict(self.votes),
            secret_word=self.secret_word,
            category=self.category,
            impostor_ids=list(self.impostor_ids),
            clues=[c.to_dict() for c in self.clues],
            score_delta=score_deltas,
            scores={p_id: p.score for p_id, p in self.players.items()},
            impostor_guess=impostor_guess,
            guess_correct=guess_correct,
        )
        return self.last_round_result

    def play_again(self, requester_id: str) -> None:
        """Return room to LOBBY while retaining player scores."""
        if self.phase != Phase.ROUND_END:
            raise ProtocolError("WRONG_PHASE", "Can only play again from ROUND_END.")
        if requester_id != self.host_id:
            raise ProtocolError("NOT_HOST", "Only the host can start a new game.")

        self.phase = Phase.LOBBY
        self.secret_word = ""
        self.category = ""
        self.impostor_ids.clear()
        self.uncaught_impostors.clear()
        self.caught_impostor_id = None
        self.clues.clear()
        self.votes.clear()
        self.vote_timestamps.clear()
        self._turn_order.clear()
        self._timer_heap.clear()
        self.current_deadline = None

        for player in self.players.values():
            player.role = Role.CREW
            player.has_confirmed_role = False

    # =========================================================================
    # Disconnection & Rejoining
    # =========================================================================

    def disconnect_player(self, player_id: str) -> None:
        """Mark player disconnected without deleting them from the room."""
        player = self.players.get(player_id)
        if not player:
            return

        player.connected = False

        if self.phase == Phase.ROLE_REVEAL:
            # Advance if all remaining connected players have confirmed
            all_confirmed = all(p.has_confirmed_role for p in self.players.values() if p.connected)
            if all_confirmed:
                self._cancel_timer(TimerType.ROLE_REVEAL_TIMEOUT)
                self._start_clue_rounds()

        elif self.phase == Phase.VOTING:
            # Advance if all remaining connected players have voted
            connected_ids = {p.id for p in self.players.values() if p.connected}
            if connected_ids.issubset(set(self.votes.keys())):
                self._cancel_timer(TimerType.VOTING_TIMEOUT)
                self._conclude_voting()

    def rejoin_player(self, player_id: str, token: str) -> Player:
        """Rejoin a disconnected player using their token."""
        player = self.players.get(player_id)
        if not player:
            raise ProtocolError("PLAYER_NOT_FOUND", "Player not found in this room.")
        if player.token != token:
            raise ProtocolError("INVALID_TOKEN", "Invalid player token.")

        player.connected = True
        return player
