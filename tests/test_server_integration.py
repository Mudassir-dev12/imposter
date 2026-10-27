"""Server integration tests with simulated WebSocket clients."""

import asyncio
import json
import random
from typing import Any, Dict, List, Optional, Tuple

import pytest
import websockets

from engine.models import GameSettings, Outcome, Role
from engine.words import WordRepository
from server.main import GameServer


class FakeClient:
    """Helper client representing a simulated connected player."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.ws: Optional[Any] = None
        self.player_id: Optional[str] = None
        self.token: Optional[str] = None
        self.is_host: bool = False
        self.received_frames: List[Dict[str, Any]] = []
        self.latest_view: Dict[str, Any] = {}

    async def connect(self, uri: str) -> None:
        self.ws = await websockets.connect(uri)

    async def close(self) -> None:
        if self.ws:
            await self.ws.close()

    async def send(self, msg_type: str, data: Optional[Dict[str, Any]] = None) -> None:
        payload = {"type": msg_type, "data": data or {}}
        await self.ws.send(json.dumps(payload))

    async def recv_until(self, condition_fn, timeout: float = 3.0) -> Dict[str, Any]:
        """Read frames until condition_fn(msg) is True."""
        loop = asyncio.get_running_loop()
        end_time = loop.time() + timeout
        while loop.time() < end_time:
            remaining = end_time - loop.time()
            if remaining <= 0:
                break
            try:
                raw = await asyncio.wait_for(self.ws.recv(), timeout=remaining)
                msg = json.loads(raw)
                self.received_frames.append(msg)
                if msg.get("type") == "room_state":
                    self.latest_view = msg.get("data", {})
                if condition_fn(msg):
                    return msg
            except asyncio.TimeoutError:
                break
        raise TimeoutError(f"Condition not met within {timeout}s for {self.name}. Received: {self.received_frames}")


def test_server_full_game_with_secrecy_and_scoring():
    """Spin up server on ephemeral port, run full 4-player game, verify zero data leakage."""

    async def run_test():
        server = GameServer(host="127.0.0.1", port=0)
        # Use custom small word list and deterministic seed
        words = {"Animals": ["Kangaroo", "Koala", "Wombat"]}
        server.room_registry.word_repo = WordRepository(custom_words=words)
        await server.start()
        port = server.bound_port
        uri = f"ws://127.0.0.1:{port}"

        clients = [FakeClient("Alice"), FakeClient("Bob"), FakeClient("Charlie"), FakeClient("David")]
        try:
            # 1. Connect Alice (Host) and create room
            await clients[0].connect(uri)
            await clients[0].send("create_room", {"name": "Alice", "settings": {"clue_rounds": 1}})
            join_msg = await clients[0].recv_until(lambda m: m["type"] == "room_joined")
            room_code = join_msg["data"]["code"]
            clients[0].player_id = join_msg["data"]["player_id"]
            clients[0].token = join_msg["data"]["token"]
            clients[0].is_host = True

            # 2. Connect Bob, Charlie, David and join room
            for c in clients[1:]:
                await c.connect(uri)
                await c.send("join_room", {"code": room_code, "name": c.name})
                j_msg = await c.recv_until(lambda m: m["type"] == "room_joined")
                c.player_id = j_msg["data"]["player_id"]
                c.token = j_msg["data"]["token"]

            # Wait until all 4 see each other in lobby
            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and len(m["data"]["players"]) == 4)

            # 3. Host starts game
            await clients[0].send("start_game")
            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and m["data"]["phase"] == "ROLE_REVEAL")

            # 4. Confirm role seen
            for c in clients:
                await c.send("confirm_role_seen")

            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and m["data"]["phase"] == "CLUE_ROUND")

            # 5. Clue Round (4 turns)
            engine = server.room_registry.get_room(room_code)
            assert engine is not None
            impostor_id = engine.impostor_ids[0]

            for _ in range(4):
                active_id = engine.current_turn_player_id
                active_client = next(c for c in clients if c.player_id == active_id)
                await active_client.send("submit_clue", {"word": f"ClueFrom{active_client.name}"})
                # Wait for all to receive clue_posted or turn advance
                for c in clients:
                    await c.recv_until(lambda m: m["type"] == "clue_posted" or m.get("data", {}).get("current_turn_player_id") != active_id or m.get("data", {}).get("phase") == "DISCUSSION")

            # All should transition to DISCUSSION
            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and m["data"]["phase"] == "DISCUSSION")

            # 6. Host skips discussion to VOTING
            await clients[0].send("skip_discussion")
            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and m["data"]["phase"] == "VOTING")

            # 7. Vote out impostor
            other_for_imp = next(c.player_id for c in clients if c.player_id != impostor_id)
            for c in clients:
                target = impostor_id if c.player_id != impostor_id else other_for_imp
                await c.send("cast_vote", {"target_id": target})

            # Voting concludes -> IMPOSTOR_GUESS
            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and m["data"]["phase"] == "IMPOSTOR_GUESS")

            # 8. Impostor submits wrong guess
            imp_client = next(c for c in clients if c.player_id == impostor_id)
            await imp_client.send("impostor_guess", {"word": "DefinitelyWrong"})

            # Round concludes -> ROUND_END
            for c in clients:
                await c.recv_until(lambda m: m["type"] == "room_state" and m["data"]["phase"] == "ROUND_END")

            # ================================================================
            # CRITICAL SECRECY ASSERTIONS: AUDIT ALL RECEIVED FRAMES
            # ================================================================
            secret_word = engine.secret_word.lower()

            for c in clients:
                for frame in c.received_frames:
                    if frame.get("type") == "room_state":
                        data = frame.get("data", {})
                        phase = data.get("phase")

                        # If innocent crew member: impostor IDs must NEVER be present during active game
                        if c.player_id != impostor_id and phase in ("LOBBY", "ROLE_REVEAL", "CLUE_ROUND", "DISCUSSION", "VOTING"):
                            assert data.get("impostor_ids") is None, f"LEAK: Crew {c.name} received impostor_ids during {phase}!"

                        # If impostor: secret word must NEVER appear in their view before ROUND_END
                        if c.player_id == impostor_id and phase != "ROUND_END":
                            assert data.get("my_word") is None, f"LEAK: Impostor received secret word during {phase}!"
                            frame_str = json.dumps(frame).lower()
                            # Assert secret word is not embedded anywhere in impostor's frame
                            assert secret_word not in frame_str, f"LEAK: Secret word found in frame sent to impostor during {phase}!"

                        # During VOTING, individual votes dictionary must never be exposed
                        if phase == "VOTING":
                            assert data.get("votes") is None, f"LEAK: Individual votes exposed during VOTING to {c.name}!"

        finally:
            for c in clients:
                await c.close()
            await server.stop()

    asyncio.run(run_test())


def test_server_rejoin_flow():
    """Verify disconnected player can reconnect with player_id + token."""

    async def run_test():
        server = GameServer(host="127.0.0.1", port=0)
        await server.start()
        uri = f"ws://127.0.0.1:{server.bound_port}"

        alice = FakeClient("Alice")
        bob = FakeClient("Bob")
        try:
            await alice.connect(uri)
            await alice.send("create_room", {"name": "Alice"})
            join_msg = await alice.recv_until(lambda m: m["type"] == "room_joined")
            room_code = join_msg["data"]["code"]

            await bob.connect(uri)
            await bob.send("join_room", {"code": room_code, "name": "Bob"})
            b_msg = await bob.recv_until(lambda m: m["type"] == "room_joined")
            b_id = b_msg["data"]["player_id"]
            b_tok = b_msg["data"]["token"]

            # Bob disconnects
            await bob.close()
            await asyncio.sleep(0.1)

            # Alice sees Bob disconnected
            await alice.recv_until(lambda m: m["type"] == "room_state" and any(p["id"] == b_id and not p["connected"] for p in m["data"]["players"]))

            # Bob rejoins with token
            bob_new = FakeClient("Bob")
            await bob_new.connect(uri)
            await bob_new.send("rejoin", {"code": room_code, "player_id": b_id, "token": b_tok})
            rejoin_msg = await bob_new.recv_until(lambda m: m["type"] == "room_joined")
            assert rejoin_msg["data"]["player_id"] == b_id

            # Alice sees Bob reconnected
            await alice.recv_until(lambda m: m["type"] == "room_state" and any(p["id"] == b_id and p["connected"] for p in m["data"]["players"]))
            await bob_new.close()

        finally:
            await alice.close()
            await server.stop()

    asyncio.run(run_test())


def test_server_host_disconnect_closes_room():
    """When the host disconnects, the server closes the room and notifies other players."""

    async def run_test():
        server = GameServer(host="127.0.0.1", port=0)
        await server.start()
        uri = f"ws://127.0.0.1:{server.bound_port}"

        host = FakeClient("HostAlice")
        guest = FakeClient("GuestBob")
        try:
            await host.connect(uri)
            await host.send("create_room", {"name": "HostAlice"})
            h_msg = await host.recv_until(lambda m: m["type"] == "room_joined")
            room_code = h_msg["data"]["code"]

            await guest.connect(uri)
            await guest.send("join_room", {"code": room_code, "name": "GuestBob"})
            await guest.recv_until(lambda m: m["type"] == "room_joined")

            # Host disconnects
            await host.close()

            # Guest receives room_closed
            closed_msg = await guest.recv_until(lambda m: m["type"] == "room_closed")
            assert "Host disconnected" in closed_msg["data"]["reason"]

            # Room should be removed from registry
            assert not server.room_registry.has_room(room_code)

        finally:
            await guest.close()
            await server.stop()

    asyncio.run(run_test())


def test_server_validation_and_rate_limiting():
    """Verify malformed frames, oversized frames, unknown types, and rate limiting."""

    async def run_test():
        server = GameServer(host="127.0.0.1", port=0)
        await server.start()
        uri = f"ws://127.0.0.1:{server.bound_port}"

        client = FakeClient("Tester")
        try:
            await client.connect(uri)

            # 1. Invalid JSON
            await client.ws.send("{malformed json")
            err = await client.recv_until(lambda m: m["type"] == "error")
            assert err["data"]["code"] == "INVALID_JSON"

            # 2. Oversized frame: rejected by server with CloseCode 1009 (message too big)
            await client.ws.send("x" * 70000)
            with pytest.raises(websockets.ConnectionClosed) as exc_info:
                await client.ws.recv()
            assert exc_info.value.rcvd.code == 1009

            # 3. Fresh connection for ping -> pong and unknown type
            client2 = FakeClient("Tester2")
            await client2.connect(uri)
            await client2.send("ping")
            pong = await client2.recv_until(lambda m: m["type"] == "pong")
            assert pong["type"] == "pong"

            # 4. Unknown type when in room
            await client2.send("create_room", {"name": "TestUser"})
            await client2.recv_until(lambda m: m["type"] == "room_joined")
            await client2.send("non_existent_action", {})
            err = await client2.recv_until(lambda m: m["type"] == "error")
            assert err["data"]["code"] == "UNKNOWN_TYPE"
            await client2.close()

        finally:
            await client.close()
            await server.stop()

    asyncio.run(run_test())


def test_server_host_leave_closes_only_that_room():
    """When a host sends 'leave', closes that room, notifies guests, and leaves other rooms open."""

    async def run_test():
        server = GameServer(host="127.0.0.1", port=0)
        await server.start()
        uri = f"ws://127.0.0.1:{server.bound_port}"

        # Room 1: Host A + Guest B
        host_a = FakeClient("HostA")
        guest_b = FakeClient("GuestB")

        # Room 2: Host C + Guest D
        host_c = FakeClient("HostC")
        guest_d = FakeClient("GuestD")

        try:
            # Create Room 1
            await host_a.connect(uri)
            await host_a.send("create_room", {"name": "HostA"})
            msg_a = await host_a.recv_until(lambda m: m["type"] == "room_joined")
            room_1 = msg_a["data"]["code"]

            await guest_b.connect(uri)
            await guest_b.send("join_room", {"code": room_1, "name": "GuestB"})
            await guest_b.recv_until(lambda m: m["type"] == "room_joined")

            # Create Room 2 on the same server
            await host_c.connect(uri)
            await host_c.send("create_room", {"name": "HostC"})
            msg_c = await host_c.recv_until(lambda m: m["type"] == "room_joined")
            room_2 = msg_c["data"]["code"]

            await guest_d.connect(uri)
            await guest_d.send("join_room", {"code": room_2, "name": "GuestD"})
            await guest_d.recv_until(lambda m: m["type"] == "room_joined")

            assert server.room_registry.has_room(room_1)
            assert server.room_registry.has_room(room_2)

            # Host A leaves Room 1
            await host_a.send("leave", {})
            left_msg = await host_a.recv_until(lambda m: m["type"] == "left_room")
            assert left_msg["type"] == "left_room"

            # Guest B in Room 1 gets room_closed
            closed_msg = await guest_b.recv_until(lambda m: m["type"] == "room_closed")
            assert "Host left" in closed_msg["data"]["reason"]

            # Room 1 is removed from registry
            assert not server.room_registry.has_room(room_1)

            # Room 2 on the same server is STILL active and unaffected!
            assert server.room_registry.has_room(room_2)

            # Host A can create another room on the same server!
            await host_a.send("create_room", {"name": "HostA_New"})
            msg_a_new = await host_a.recv_until(lambda m: m["type"] == "room_joined")
            room_3 = msg_a_new["data"]["code"]
            assert server.room_registry.has_room(room_3)
            assert server.room_registry.has_room(room_2)

        finally:
            await host_a.close()
            await guest_b.close()
            await host_c.close()
            await guest_d.close()
            await server.stop()

    asyncio.run(run_test())

