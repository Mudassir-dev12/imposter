"""Tests for ServerSupervisor control channel, graceful shutdown, and port release."""

import asyncio
import json
import socket
from typing import Any, Dict

import pytest
import websockets

from server.embedded_entry import ServerSupervisor


class SupervisorTestClient:
    """Helper client for communicating with the loopback supervisor control channel."""

    def __init__(self, port: int, token: str) -> None:
        self.port: int = port
        self.token: str = token
        self.reader: asyncio.StreamReader = None  # type: ignore
        self.writer: asyncio.StreamWriter = None  # type: ignore

    async def connect(self) -> None:
        self.reader, self.writer = await asyncio.open_connection("127.0.0.1", self.port)

    async def close(self) -> None:
        if self.writer:
            try:
                self.writer.close()
                await asyncio.wait_for(self.writer.wait_closed(), timeout=0.5)
            except Exception:
                pass

    async def send_line(self, line: str) -> str:
        self.writer.write((line + "\n").encode("utf-8"))
        await self.writer.drain()
        resp = await self.reader.readline()
        return resp.decode("utf-8").strip()

    async def send_json(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        self.writer.write((json.dumps(payload) + "\n").encode("utf-8"))
        await self.writer.drain()
        resp = await self.reader.readline()
        return json.loads(resp.decode("utf-8"))


def is_port_open(port: int, host: str = "127.0.0.1") -> bool:
    """Check if TCP port accepts connections."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex((host, port)) == 0


def test_control_channel_authentication_and_loopback_only():
    """Verify wrong token is rejected and supervisor only binds to 127.0.0.1."""
    async def run_test():
        token = "secret_test_token_12345"
        supervisor = ServerSupervisor(token=token, control_host="127.0.0.1", control_port=0)
        await supervisor.start()
        control_port = supervisor.actual_control_port
        assert control_port is not None and control_port > 0

        try:
            # 1. Assert control channel is NOT bound to 0.0.0.0
            sock = supervisor._server.sockets[0]
            bound_ip = sock.getsockname()[0]
            assert bound_ip == "127.0.0.1"

            # 2. Test wrong token rejected (line protocol)
            client = SupervisorTestClient(control_port, token)
            await client.connect()
            try:
                resp = await client.send_line("AUTH wrong_token")
                assert resp == "ERROR UNAUTHORIZED"
            finally:
                await client.close()

            # 3. Test wrong token rejected (JSON protocol)
            client_json = SupervisorTestClient(control_port, token)
            await client_json.connect()
            try:
                json_resp = await client_json.send_json({"token": "bad_token", "command": "STATUS"})
                assert json_resp["status"] == "error"
                assert json_resp["message"] == "UNAUTHORIZED"
            finally:
                await client_json.close()

            # 4. Test command without AUTH is rejected
            client_unauth = SupervisorTestClient(control_port, token)
            await client_unauth.connect()
            try:
                resp_unauth = await client_unauth.send_line("STATUS")
                assert resp_unauth == "ERROR UNAUTHORIZED"
            finally:
                await client_unauth.close()

            # 5. Test successful AUTH
            client_ok = SupervisorTestClient(control_port, token)
            await client_ok.connect()
            try:
                resp_ok = await client_ok.send_line(f"AUTH {token}")
                assert resp_ok == "OK AUTHENTICATED"

                status_resp = await client_ok.send_line("STATUS")
                assert status_resp.startswith("OK STATUS")
                status_data = json.loads(status_resp.replace("OK STATUS ", ""))
                assert status_data["running"] is False
                assert status_data["port"] is None
                assert status_data["rooms"] == 0
                assert status_data["connections"] == 0
            finally:
                await client_ok.close()
        finally:
            await supervisor.stop()

    asyncio.run(run_test())


def test_supervisor_start_connect_stop_and_port_release():
    """Verify start, connecting clients, STOP releasing port and notifying clients with room_closed."""
    async def run_test():
        token = "test_lifecycle_token_xyz"
        supervisor = ServerSupervisor(token=token, control_host="127.0.0.1", control_port=0)
        await supervisor.start()
        control_port = supervisor.actual_control_port

        client = SupervisorTestClient(control_port, token)
        await client.connect()

        try:
            auth_resp = await client.send_line(f"AUTH {token}")
            assert auth_resp == "OK AUTHENTICATED"

            # 1. START game server on ephemeral/available port
            with socket.socket() as s:
                s.bind(("127.0.0.1", 0))
                game_port = s.getsockname()[1]

            start_resp = await client.send_line(f"START {game_port}")
            assert f"OK STARTED {game_port}" in start_resp
            assert is_port_open(game_port) is True

            # 2. Connect 2 WebSocket clients and create a room
            ws1 = await websockets.connect(f"ws://127.0.0.1:{game_port}")
            ws2 = await websockets.connect(f"ws://127.0.0.1:{game_port}")

            try:
                await ws1.send(json.dumps({"type": "create_room", "data": {"name": "Alice"}}))
                raw1 = await ws1.recv()
                msg1 = json.loads(raw1)
                assert msg1["type"] == "room_joined"
                room_code = msg1["data"]["code"]

                await ws2.send(json.dumps({"type": "join_room", "data": {"name": "Bob", "code": room_code}}))
                raw2 = await ws2.recv()
                msg2 = json.loads(raw2)
                assert msg2["type"] == "room_joined"

                # Check STATUS while running
                status_resp = await client.send_line("STATUS")
                status_data = json.loads(status_resp.replace("OK STATUS ", ""))
                assert status_data["running"] is True
                assert status_data["port"] == game_port
                assert status_data["rooms"] == 1
                assert status_data["connections"] == 2

                # 3. Issue STOP command
                stop_resp = await client.send_line("STOP")
                assert stop_resp == "OK STOPPED"

                # 4. Assert clients received room_closed
                async def drain_until_closed(ws):
                    frames = []
                    try:
                        while True:
                            f = await asyncio.wait_for(ws.recv(), timeout=1.0)
                            frames.append(json.loads(f))
                    except (websockets.ConnectionClosed, asyncio.TimeoutError):
                        pass
                    return frames

                frames1 = await drain_until_closed(ws1)
                frames2 = await drain_until_closed(ws2)

                types1 = [f.get("type") for f in frames1]
                types2 = [f.get("type") for f in frames2]
                assert "room_closed" in types1
                assert "room_closed" in types2
            finally:
                try:
                    await ws1.close()
                except Exception:
                    pass
                try:
                    await ws2.close()
                except Exception:
                    pass

            # 5. Assert the game port refuses new connections immediately
            await asyncio.sleep(0.1)
            assert is_port_open(game_port) is False

            with pytest.raises((ConnectionRefusedError, OSError, websockets.WebSocketException)):
                await asyncio.wait_for(websockets.connect(f"ws://127.0.0.1:{game_port}"), timeout=0.5)

            # 6. Assert STOP is idempotent (calling STOP again is safe and returns OK)
            stop_again = await client.send_line("STOP")
            assert "OK" in stop_again

            # Status shows stopped
            status_after = await client.send_line("STATUS")
            data_after = json.loads(status_after.replace("OK STATUS ", ""))
            assert data_after["running"] is False
            assert data_after["rooms"] == 0
            assert data_after["connections"] == 0

            # 7. Issue START again on same port and play a quick game / verify room creation
            start_again = await client.send_line(f"START {game_port}")
            assert f"OK STARTED {game_port}" in start_again
            assert is_port_open(game_port) is True

            ws3 = await websockets.connect(f"ws://127.0.0.1:{game_port}")
            try:
                await ws3.send(json.dumps({"type": "create_room", "data": {"name": "Charlie"}}))
                raw3 = await ws3.recv()
                msg3 = json.loads(raw3)
                assert msg3["type"] == "room_joined"
                assert msg3["data"]["code"] is not None
            finally:
                try:
                    await ws3.close()
                except Exception:
                    pass

            # Stop once more
            await client.send_line("STOP")
            await asyncio.sleep(0.1)
            assert is_port_open(game_port) is False

        finally:
            await client.close()
            await supervisor.stop()

    asyncio.run(run_test())


def test_supervisor_json_interface_and_quit():
    """Verify JSON protocol support and QUIT command."""
    async def run_test():
        token = "json_token_999"
        supervisor = ServerSupervisor(token=token, control_host="127.0.0.1", control_port=0)
        await supervisor.start()
        control_port = supervisor.actual_control_port

        client = SupervisorTestClient(control_port, token)
        await client.connect()

        try:
            # Status check via JSON
            res = await client.send_json({"token": token, "command": "STATUS"})
            assert res["status"] == "ok"
            assert res["data"]["running"] is False

            # START on port via JSON
            with socket.socket() as s:
                s.bind(("127.0.0.1", 0))
                port = s.getsockname()[1]

            res = await client.send_json({"token": token, "command": "START", "port": port})
            assert res["status"] == "ok"
            assert is_port_open(port) is True

            # STOP via JSON
            res = await client.send_json({"token": token, "command": "STOP"})
            assert res["status"] == "ok"
            await asyncio.sleep(0.1)
            assert is_port_open(port) is False

            # QUIT via JSON
            res = await client.send_json({"token": token, "command": "QUIT"})
            assert res["status"] == "ok"
        finally:
            await client.close()
            await supervisor.stop()

        # Wait for supervisor stop event
        await asyncio.wait_for(supervisor.wait_stopped(), timeout=2.0)

    asyncio.run(run_test())
