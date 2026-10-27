"""Unit tests for protocol message validation and secrecy views."""

import random
import pytest

from engine.game import GameEngine
from engine.models import GameSettings, Outcome, Phase, Role
from engine.protocol import (
    ProtocolError,
    ALLOWED_ROOM_CODE_CHARS,
    build_player_view,
    generate_room_code,
    matches_secret_word,
    sanitize_name,
    validate_clue,
)
from engine.words import WordRepository


def test_sanitize_name():
    assert sanitize_name("  Alice  ") == "Alice"
    assert sanitize_name("Bob") == "Bob"

    with pytest.raises(ProtocolError) as exc:
        sanitize_name("")
    assert exc.value.code == "INVALID_NAME"

    with pytest.raises(ProtocolError) as exc:
        sanitize_name("   ")
    assert exc.value.code == "INVALID_NAME"

    with pytest.raises(ProtocolError) as exc:
        sanitize_name("A" * 17)
    assert exc.value.code == "INVALID_NAME"


def test_validate_clue():
    secret = "Elephant"
    assert validate_clue("Trunk", secret) == "Trunk"
    assert validate_clue("  gray  ", secret) == "gray"

    # Must not equal secret word
    with pytest.raises(ProtocolError) as exc:
        validate_clue("elephant", secret)
    assert exc.value.code == "INVALID_CLUE"

    with pytest.raises(ProtocolError) as exc:
        validate_clue("ELEPHANT", secret)
    assert exc.value.code == "INVALID_CLUE"

    # Single word, no spaces
    with pytest.raises(ProtocolError) as exc:
        validate_clue("big animal", secret)
    assert exc.value.code == "INVALID_CLUE"

    # Length boundary
    with pytest.raises(ProtocolError) as exc:
        validate_clue("A" * 21, secret)
    assert exc.value.code == "INVALID_CLUE"


def test_matches_secret_word():
    # Exact
    assert matches_secret_word("Elephant", "Elephant")
    assert matches_secret_word("elephant", "Elephant")
    assert matches_secret_word("  ELEPHANT  ", "Elephant")

    # Plural -s
    assert matches_secret_word("elephants", "Elephant")
    assert matches_secret_word("panda", "Pandas")
    assert matches_secret_word("pandas", "Panda")

    # Plural -es
    assert matches_secret_word("sandwiches", "Sandwich")
    assert matches_secret_word("sandwich", "Sandwiches")
    assert matches_secret_word("foxes", "Fox")

    # Non-match
    assert not matches_secret_word("Giraffe", "Elephant")
    assert not matches_secret_word("Ele", "Elephant")


def test_generate_room_code():
    rng = random.Random(42)
    code = generate_room_code(rng, 4)
    assert len(code) == 4
    for ch in code:
        assert ch in ALLOWED_ROOM_CODE_CHARS
        # Verify ambiguous chars are absent
        assert ch not in "OI01"


# ============================================================================
# Secrecy View Tests (CRITICAL)
# ============================================================================

def create_started_game():
    rng = random.Random(123)
    custom_words = {"Animals": ["Tiger", "Lion", "Bear", "Elephant"]}
    repo = WordRepository(custom_words=custom_words)
    engine = GameEngine(
        settings=GameSettings(clue_rounds=1, impostor_count=1, impostor_sees_category=True),
        word_repo=repo,
        rng=rng,
    )
    p1, _ = engine.add_player("Alice")
    p2, _ = engine.add_player("Bob")
    p3, _ = engine.add_player("Charlie")
    engine.start_game(p1.id)
    return engine


def test_secrecy_crew_view_never_reveals_impostor_during_game():
    """An innocent player's view must NEVER contain impostor IDs before round ends."""
    engine = create_started_game()
    impostor_id = engine.impostor_ids[0]
    crew_ids = [p_id for p_id in engine.players if p_id != impostor_id]

    # In ROLE_REVEAL phase
    for c_id in crew_ids:
        view = build_player_view(engine, c_id)
        assert view["my_role"] == Role.CREW.value
        assert view["my_word"] == engine.secret_word
        assert view["category"] == engine.category
        # Crucial: impostor identity must be hidden!
        assert view["impostor_ids"] is None

    # Confirm and transition to CLUE_ROUND
    for p_id in engine.players:
        engine.confirm_role_seen(p_id)
    assert engine.phase == Phase.CLUE_ROUND

    for c_id in crew_ids:
        view = build_player_view(engine, c_id)
        assert view["impostor_ids"] is None


def test_secrecy_impostor_view_never_reveals_secret_word_before_round_end():
    """An impostor's view must NEVER contain the secret word until ROUND_END."""
    engine = create_started_game()
    impostor_id = engine.impostor_ids[0]

    # In ROLE_REVEAL phase
    imp_view = build_player_view(engine, impostor_id)
    assert imp_view["my_role"] == Role.IMPOSTOR.value
    # Crucial: secret word MUST be None!
    assert imp_view["my_word"] is None
    # Category hint shown per settings
    assert imp_view["category"] == engine.category

    # In CLUE_ROUND
    for p_id in engine.players:
        engine.confirm_role_seen(p_id)

    imp_view = build_player_view(engine, impostor_id)
    assert imp_view["my_word"] is None

    # In DISCUSSION
    # Submit all clues to reach discussion
    while engine.phase == Phase.CLUE_ROUND:
        curr = engine.current_turn_player_id
        engine.submit_clue(curr, "ClueWord")

    assert engine.phase == Phase.DISCUSSION
    imp_view = build_player_view(engine, impostor_id)
    assert imp_view["my_word"] is None

    # In VOTING
    engine.skip_discussion(engine.host_id)
    assert engine.phase == Phase.VOTING
    imp_view = build_player_view(engine, impostor_id)
    assert imp_view["my_word"] is None


def test_voting_progress_privacy():
    """During VOTING, individual votes must remain hidden; only progress count is shown."""
    engine = create_started_game()
    for p_id in engine.players:
        engine.confirm_role_seen(p_id)

    while engine.phase == Phase.CLUE_ROUND:
        engine.submit_clue(engine.current_turn_player_id, "Clue")

    engine.skip_discussion(engine.host_id)
    assert engine.phase == Phase.VOTING

    p_ids = list(engine.players.keys())
    # One player votes
    engine.cast_vote(p_ids[0], p_ids[1])

    for p_id in p_ids:
        view = build_player_view(engine, p_id)
        # Individual vote dictionary must be hidden
        assert view["votes"] is None
        # Aggregate progress visible
        assert view["vote_progress"] == {"voted_count": 1, "total": 3}


def test_round_end_reveals_all():
    """At ROUND_END, the secret word, votes, and impostor identities are revealed."""
    engine = create_started_game()
    for p_id in engine.players:
        engine.confirm_role_seen(p_id)
    while engine.phase == Phase.CLUE_ROUND:
        engine.submit_clue(engine.current_turn_player_id, "Clue")
    engine.skip_discussion(engine.host_id)

    # Vote out impostor
    imp_id = engine.impostor_ids[0]
    other_for_imp = [p_id for p_id in engine.players if p_id != imp_id][0]
    for p_id in engine.players:
        target = imp_id if p_id != imp_id else other_for_imp
        engine.cast_vote(p_id, target)

    assert engine.phase == Phase.IMPOSTOR_GUESS
    # Impostor guesses wrong word
    engine.submit_impostor_guess(imp_id, "WrongGuess")

    assert engine.phase == Phase.ROUND_END

    for p_id in engine.players:
        view = build_player_view(engine, p_id)
        assert view["my_word"] == engine.secret_word
        assert view["impostor_ids"] == [imp_id]
        assert view["votes"] is not None
        assert view["round_result"] is not None
        assert view["round_result"]["outcome"] == Outcome.CREW_WIN.value
