import random
from typing import Any, List, Tuple
import pytest

from engine.game import GameEngine
from engine.models import GameSettings, Outcome, Phase, Role
from engine.protocol import ProtocolError, build_player_view
from engine.words import WordRepository


class MockClock:
    """Controllable clock for deterministic timer testing."""

    def __init__(self, start_time: float = 1000.0) -> None:
        self.now = start_time

    def time(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


Tuple_Engine_Players = Tuple[GameEngine, List[Any], MockClock]


def setup_4p_engine(seed: int = 42, clue_rounds: int = 2) -> Tuple_Engine_Players:
    rng = random.Random(seed)
    clock = MockClock()
    custom_words = {"Animals": ["Panda", "Tiger", "Lion", "Elephant"]}
    repo = WordRepository(custom_words=custom_words)
    settings = GameSettings(
        clue_rounds=clue_rounds,
        impostor_count=1,
        discussion_timer_seconds=90,
        turn_timer_seconds=30,
        voting_timer_seconds=60,
    )
    engine = GameEngine(
        settings=settings,
        word_repo=repo,
        rng=rng,
        time_provider=clock.time,
    )
    p1, tok1 = engine.add_player("Alice")
    p2, tok2 = engine.add_player("Bob")
    p3, tok3 = engine.add_player("Charlie")
    p4, tok4 = engine.add_player("David")
    return engine, [p1, p2, p3, p4], clock


def test_full_happy_path_crew_win():
    """Happy path: 4 players, 2 clue rounds, vote impostor, wrong guess, crew wins."""
    engine, players, clock = setup_4p_engine(seed=10, clue_rounds=2)
    host = players[0]

    assert engine.phase == Phase.LOBBY
    engine.start_game(host.id)
    assert engine.phase == Phase.ROLE_REVEAL

    impostor_id = engine.impostor_ids[0]
    crew_ids = [p.id for p in players if p.id != impostor_id]

    # All players confirm role
    for p in players:
        engine.confirm_role_seen(p.id)
    assert engine.phase == Phase.CLUE_ROUND
    assert engine.current_round_index == 1

    # Round 1 clues (4 turns)
    for _ in range(4):
        curr = engine.current_turn_player_id
        engine.submit_clue(curr, "ClueA")

    assert engine.current_round_index == 2
    assert engine.phase == Phase.CLUE_ROUND

    # Round 2 clues (4 turns)
    for _ in range(4):
        curr = engine.current_turn_player_id
        engine.submit_clue(curr, "ClueB")

    # Clue rounds completed -> DISCUSSION
    assert engine.phase == Phase.DISCUSSION
    assert len(engine.clues) == 8

    # Host skips discussion to voting
    engine.skip_discussion(host.id)
    assert engine.phase == Phase.VOTING

    # Voting: all crew members vote for impostor
    clock.advance(1.0)
    engine.cast_vote(crew_ids[0], impostor_id)
    clock.advance(1.0)
    engine.cast_vote(crew_ids[1], impostor_id)
    clock.advance(1.0)
    engine.cast_vote(crew_ids[2], impostor_id)
    clock.advance(1.0)
    engine.cast_vote(impostor_id, host.id)

    # Caught impostor goes to IMPOSTOR_GUESS
    assert engine.phase == Phase.IMPOSTOR_GUESS
    assert engine.caught_impostor_id == impostor_id

    # Impostor guesses wrong word
    is_correct = engine.submit_impostor_guess(impostor_id, "TotallyWrongWord")
    assert not is_correct
    assert engine.phase == Phase.ROUND_END

    res = engine.last_round_result
    assert res is not None
    assert res.outcome == Outcome.CREW_WIN
    assert res.was_impostor is True
    assert res.ejected_id == impostor_id

    # Scores: +2 to crew, +1 bonus to earliest correct voter (crew_ids[0]), 0 to impostor
    assert res.score_delta[crew_ids[0]] == 3  # 2 + 1 bonus
    assert res.score_delta[crew_ids[1]] == 2
    assert res.score_delta[crew_ids[2]] == 2
    assert res.score_delta[impostor_id] == 0

    # Play again preserves scores and resets to lobby
    engine.play_again(host.id)
    assert engine.phase == Phase.LOBBY
    assert engine.players[crew_ids[0]].score == 3
    assert engine.players[impostor_id].score == 0


def test_impostor_steal_win():
    """Impostor is caught by voting, but correctly guesses the secret word."""
    engine, players, _ = setup_4p_engine(seed=12, clue_rounds=1)
    host = players[0]
    engine.start_game(host.id)

    for p in players:
        engine.confirm_role_seen(p.id)

    for _ in range(4):
        engine.submit_clue(engine.current_turn_player_id, "Clue")

    engine.skip_discussion(host.id)

    imp_id = engine.impostor_ids[0]
    other_for_imp = [p.id for p in players if p.id != imp_id][0]
    for p in players:
        target = imp_id if p.id != imp_id else other_for_imp
        engine.cast_vote(p.id, target)

    assert engine.phase == Phase.IMPOSTOR_GUESS
    secret = engine.secret_word

    # Impostor steals win (test case-insensitive + plural match)
    guessed = secret.lower() + "s"
    is_correct = engine.submit_impostor_guess(imp_id, guessed)
    assert is_correct
    assert engine.phase == Phase.ROUND_END

    res = engine.last_round_result
    assert res.outcome == Outcome.IMPOSTOR_STEAL_WIN
    # Impostor gets +2 steal-win points, crew gets 0
    assert res.score_delta[imp_id] == 2
    for p in players:
        if p.id != imp_id:
            assert res.score_delta[p.id] == 0


def test_tie_vote_impostor_wins():
    """Tied vote means nobody is ejected and impostors win the round."""
    engine, players, _ = setup_4p_engine(seed=15, clue_rounds=1)
    host = players[0]
    engine.start_game(host.id)
    for p in players:
        engine.confirm_role_seen(p.id)
    for _ in range(4):
        engine.submit_clue(engine.current_turn_player_id, "Clue")
    engine.skip_discussion(host.id)

    imp_id = engine.impostor_ids[0]
    p1, p2, p3, p4 = players

    # 2 votes for p1, 2 votes for p2
    engine.cast_vote(p1.id, p2.id)
    engine.cast_vote(p3.id, p2.id)
    engine.cast_vote(p2.id, p1.id)
    engine.cast_vote(p4.id, p1.id)

    assert engine.phase == Phase.ROUND_END
    res = engine.last_round_result
    assert res.outcome == Outcome.IMPOSTOR_WIN_TIE
    assert res.ejected_id is None
    # Impostor team gets +3
    assert res.score_delta[imp_id] == 3


def test_innocent_player_voted_out():
    """When an innocent player is voted out, impostors win immediately."""
    engine, players, _ = setup_4p_engine(seed=20, clue_rounds=1)
    host = players[0]
    engine.start_game(host.id)
    for p in players:
        engine.confirm_role_seen(p.id)
    for _ in range(4):
        engine.submit_clue(engine.current_turn_player_id, "Clue")
    engine.skip_discussion(host.id)

    imp_id = engine.impostor_ids[0]
    innocent_target = [p.id for p in players if p.id != imp_id][0]

    # 3 votes for innocent player
    for p in players:
        if p.id != innocent_target:
            engine.cast_vote(p.id, innocent_target)
        else:
            engine.cast_vote(p.id, imp_id)

    assert engine.phase == Phase.ROUND_END
    res = engine.last_round_result
    assert res.outcome == Outcome.IMPOSTOR_WIN_INNOCENT_VOTED
    assert res.ejected_id == innocent_target
    assert res.was_impostor is False
    assert res.score_delta[imp_id] == 3


def test_two_impostor_flow():
    """7 players, 2 impostors: first caught triggers second vote round."""
    rng = random.Random(99)
    custom_words = {"Animals": ["Panda", "Tiger", "Elephant"]}
    repo = WordRepository(custom_words=custom_words)
    settings = GameSettings(clue_rounds=1, impostor_count=2)
    engine = GameEngine(settings=settings, word_repo=repo, rng=rng)

    p_list = []
    for i in range(7):
        p, _ = engine.add_player(f"Player_{i}")
        p_list.append(p)

    engine.start_game(p_list[0].id)
    assert len(engine.impostor_ids) == 2
    imp1, imp2 = engine.impostor_ids

    for p in p_list:
        engine.confirm_role_seen(p.id)

    # Submit clues
    for _ in range(7):
        engine.submit_clue(engine.current_turn_player_id, "Clue")

    engine.skip_discussion(engine.host_id)
    assert engine.phase == Phase.VOTING

    # Round 1 vote: vote out imp1
    for p in p_list:
        engine.cast_vote(p.id, imp1 if p.id != imp1 else imp2)

    # 1 impostor caught, but imp2 still uncaught -> transitions to second vote round
    assert engine.phase == Phase.VOTING
    assert engine.uncaught_impostors == {imp2}

    # Round 2 vote: vote out imp2
    for p in p_list:
        engine.cast_vote(p.id, imp2 if p.id != imp2 else imp1)

    # Both caught -> goes to IMPOSTOR_GUESS
    assert engine.phase == Phase.IMPOSTOR_GUESS
    assert engine.caught_impostor_id == imp2

    # Guess fails -> Crew wins
    engine.submit_impostor_guess(imp2, "Wrong")
    assert engine.phase == Phase.ROUND_END
    assert engine.last_round_result.outcome == Outcome.CREW_WIN


def test_disconnect_and_rejoin():
    """Disconnected player can rejoin with token; voting auto-completes without them."""
    engine, players, _ = setup_4p_engine(seed=30, clue_rounds=1)
    host = players[0]
    p4 = players[3]
    engine.start_game(host.id)

    # P4 disconnects in ROLE_REVEAL
    engine.disconnect_player(p4.id)
    assert not engine.players[p4.id].connected

    # Remaining 3 confirm -> advances to CLUE_ROUND
    for p in players[:3]:
        engine.confirm_role_seen(p.id)
    assert engine.phase == Phase.CLUE_ROUND

    # P4 rejoins with token
    rejoined = engine.rejoin_player(p4.id, p4.token)
    assert rejoined.connected is True

    # Bad token fails
    with pytest.raises(ProtocolError) as exc:
        engine.rejoin_player(p4.id, "bad_token")
    assert exc.value.code == "INVALID_TOKEN"

    with pytest.raises(ProtocolError) as exc:
        engine.rejoin_player("non_existent_id", "tok")
    assert exc.value.code == "PLAYER_NOT_FOUND"


def test_wrong_phase_and_invalid_actions():
    """Verify strict protocol and state machine constraints."""
    engine, players, _ = setup_4p_engine()
    host, non_host = players[0], players[1]

    # Non-host cannot start game
    with pytest.raises(ProtocolError) as exc:
        engine.start_game(non_host.id)
    assert exc.value.code == "NOT_HOST"

    # Non-host cannot update settings
    with pytest.raises(ProtocolError) as exc:
        engine.update_settings(non_host.id, {"clue_rounds": 3})
    assert exc.value.code == "NOT_HOST"

    # Cannot submit clue in LOBBY
    with pytest.raises(ProtocolError) as exc:
        engine.submit_clue(host.id, "Clue")
    assert exc.value.code == "WRONG_PHASE"

    engine.start_game(host.id)

    # Cannot vote in ROLE_REVEAL
    with pytest.raises(ProtocolError) as exc:
        engine.cast_vote(host.id, non_host.id)
    assert exc.value.code == "WRONG_PHASE"

    for p in players:
        engine.confirm_role_seen(p.id)

    # In CLUE_ROUND: not your turn
    active_id = engine.current_turn_player_id
    inactive_id = [p.id for p in players if p.id != active_id][0]
    with pytest.raises(ProtocolError) as exc:
        engine.submit_clue(inactive_id, "Clue")
    assert exc.value.code == "NOT_YOUR_TURN"

    # In VOTING: cannot vote for self
    while engine.phase == Phase.CLUE_ROUND:
        engine.submit_clue(engine.current_turn_player_id, "Clue")
    engine.skip_discussion(host.id)

    with pytest.raises(ProtocolError) as exc:
        engine.cast_vote(host.id, host.id)
    assert exc.value.code == "INVALID_ACTION"


def test_timers_via_min_heap():
    """Verify turn timeout auto-skips AFK players via custom MinHeap."""
    engine, players, clock = setup_4p_engine(seed=55, clue_rounds=1)
    host = players[0]
    engine.start_game(host.id)
    for p in players:
        engine.confirm_role_seen(p.id)

    assert engine.phase == Phase.CLUE_ROUND
    first_player_id = engine.current_turn_player_id

    # Advance clock past turn timer (30s)
    clock.advance(35.0)
    fired = engine.tick()
    assert len(fired) >= 1

    # First player should have been auto-skipped with "[skipped]" clue
    assert engine.clues[0].word == "[skipped]"
    assert engine.clues[0].player_id == first_player_id
    # Turn rotated to next player in CircularLinkedList
    assert engine.current_turn_player_id != first_player_id


def test_discussion_and_voting_timeouts():
    """Discussion timer auto-starts voting; voting timer auto-concludes voting."""
    engine, players, clock = setup_4p_engine(seed=77, clue_rounds=1)
    host = players[0]
    engine.start_game(host.id)
    for p in players:
        engine.confirm_role_seen(p.id)

    # Complete all clues
    for _ in range(4):
        engine.submit_clue(engine.current_turn_player_id, "ClueWord")

    assert engine.phase == Phase.DISCUSSION

    # Advance clock past discussion timer (90s)
    clock.advance(95.0)
    fired = engine.tick()
    assert len(fired) >= 1
    assert engine.phase == Phase.VOTING

    # Advance clock past voting timer (60s) without votes
    clock.advance(65.0)
    fired_vote = engine.tick()
    assert len(fired_vote) >= 1
    # Nobody voted -> Tie -> Impostor win
    assert engine.phase == Phase.ROUND_END
    assert engine.last_round_result.outcome == Outcome.IMPOSTOR_WIN_TIE


def test_lobby_management_and_host_migration():
    """Test kicking players, host leaving, duplicate names, and room size limit."""
    engine = GameEngine()
    p1, _ = engine.add_player("HostUser")
    assert p1.is_host is True
    assert engine.host_id == p1.id

    p2, _ = engine.add_player("SecondUser")
    assert p2.is_host is False

    # Name taken check (case insensitive)
    with pytest.raises(ProtocolError) as exc:
        engine.add_player("hostuser")
    assert exc.value.code == "NAME_TAKEN"

    # Non-host cannot kick
    with pytest.raises(ProtocolError) as exc:
        engine.remove_player(p1.id, requester_id=p2.id)
    assert exc.value.code == "NOT_HOST"

    # Host kicks player
    engine.remove_player(p2.id, requester_id=p1.id)
    assert p2.id not in engine.players

    # Host leaves -> host migration to next player
    p3, _ = engine.add_player("ThirdUser")
    engine.remove_player(p1.id, requester_id=p1.id)
    assert p1.id not in engine.players
    assert engine.host_id == p3.id
    assert engine.players[p3.id].is_host is True

    # Room full at 10 players
    for i in range(9):
        engine.add_player(f"Fill_{i}")

    assert len(engine.players) == 10
    with pytest.raises(ProtocolError) as exc:
        engine.add_player("Extra")
    assert exc.value.code == "ROOM_FULL"


def test_game_settings_validation():
    """Validate settings limits."""
    s = GameSettings()
    s.validate(player_count=4)

    # Invalid rounds
    with pytest.raises(ValueError):
        GameSettings(clue_rounds=0).validate(4)
    with pytest.raises(ValueError):
        GameSettings(clue_rounds=4).validate(4)

    # 2 impostors with 4 players -> Error
    with pytest.raises(ValueError):
        GameSettings(impostor_count=2).validate(player_count=6)

    # 2 impostors with 7 players -> OK
    GameSettings(impostor_count=2).validate(player_count=7)

    # Turn timer too low
    with pytest.raises(ValueError):
        GameSettings(turn_timer_seconds=2).validate(4)


def test_word_repository():
    """Verify word repository loading and random picking."""
    repo = WordRepository()
    categories = repo.get_categories()
    assert len(categories) >= 12
    for cat in categories:
        words = repo.get_words(cat)
        assert len(words) >= 20

    # Pick word with specific category (case-insensitive)
    cat, word = repo.pick_word(category="animals", rng=random.Random(1))
    assert cat == "Animals"
    assert isinstance(word, str) and len(word) > 0

    # Invalid category
    with pytest.raises(KeyError):
        repo.get_words("FakeCategory")
    with pytest.raises(KeyError):
        repo.pick_word("FakeCategory")


def test_action_queue_execution():
    """Verify engine action queue executes tasks atomically."""
    engine = GameEngine()
    engine.enqueue_action("add", engine.add_player, "Alice")
    engine.enqueue_action("add", engine.add_player, "Bob")
    assert len(engine.players) == 2


def test_spoken_clues_mode():
    """Verify spoken_clues mode: end_turn advances turn, submit_clue rejected, rounds transition."""
    # 1. Test spoken_clues with no turn timers (turn_timer_seconds=0)
    engine, players, clock = setup_4p_engine(seed=42, clue_rounds=2)
    host = players[0]
    engine.update_settings(host.id, {
        "spoken_clues": True,
        "turn_timer_seconds": 0,
    })
    assert engine.settings.spoken_clues is True
    assert engine.settings.turn_timer_seconds == 0

    engine.start_game(host.id)
    for p in players:
        engine.confirm_role_seen(p.id)

    assert engine.phase == Phase.CLUE_ROUND
    assert engine.current_round_index == 1
    # Since turn_timer_seconds is 0, no turn timer should be scheduled
    assert engine._timer_heap.is_empty()

    current_id = engine.current_turn_player_id
    inactive_id = [p.id for p in players if p.id != current_id][0]

    # submit_clue must be rejected in spoken_clues mode
    with pytest.raises(ProtocolError) as exc_info:
        engine.submit_clue(current_id, "TypedClue")
    assert exc_info.value.code == "SPOKEN_CLUES_ENABLED"

    # end_turn by wrong player must be rejected
    with pytest.raises(ProtocolError) as exc_info:
        engine.end_turn(inactive_id)
    assert exc_info.value.code == "NOT_YOUR_TURN"

    # Valid end_turn by active player
    clue = engine.end_turn(current_id)
    assert clue.player_id == current_id
    assert clue.word == "[spoken]"
    assert clue.round_index == 1

    # Player rotated
    next_id = engine.current_turn_player_id
    assert next_id != current_id

    # Finish remaining 3 turns of round 1
    for _ in range(3):
        engine.end_turn(engine.current_turn_player_id)

    # Should now be round 2
    assert engine.phase == Phase.CLUE_ROUND
    assert engine.current_round_index == 2

    # Finish round 2 (4 turns)
    for _ in range(4):
        engine.end_turn(engine.current_turn_player_id)

    # After 2 rounds -> moves to DISCUSSION
    assert engine.phase == Phase.DISCUSSION
    assert len(engine.clues) == 8
    for c in engine.clues:
        assert c.word == "[spoken]"

    # 2. Test that end_turn is rejected when spoken_clues is False
    engine2, players2, _ = setup_4p_engine(seed=12, clue_rounds=1)
    engine2.start_game(players2[0].id)
    for p in players2:
        engine2.confirm_role_seen(p.id)
    assert engine2.settings.spoken_clues is False

    with pytest.raises(ProtocolError) as exc:
        engine2.end_turn(engine2.current_turn_player_id)
    assert exc.value.code == "SPOKEN_CLUES_DISABLED"
