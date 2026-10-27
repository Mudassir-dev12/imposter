"""Asyncio WebSocket Server entry point and request router for Impostor."""

import argparse
import asyncio
import json
import logging
import signal
import sys
from typing import Any, Dict, Optional

import websockets

from engine.game import GameEngine
from engine.models import GameSettings
from engine.protocol import ProtocolError
from server.connection_manager import ConnectionManager
from server.room_registry import RoomRegistry

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s [%(name)s]: %(message)s",
)
logger = logging.getLogger("impostor.server")

MAX_FRAME_SIZE = 65536  # 64 KB limit for security


class GameServer:
    """Asyncio WebSocket server hosting multiplayer Impostor rooms."""

    def __init__(self, host: str = "0.0.0.0", port: int = 8765) -> None:
        self.host: str = host
        self.port: int = port
        self.bound_port: Optional[int] = None
        self.room_registry: RoomRegistry = RoomRegistry()
        self.connection_manager: ConnectionManager = ConnectionManager()

        self._room_locks: Dict[str, asyncio.Lock] = {}
        self._server: Optional[Any] = None
        self._ticker_task: Optional[asyncio.Task[None]] = None
        self._connection_tasks: set[asyncio.Task[Any]] = set()
        self._is_running: bool = False

    def _get_room_lock(self, room_code: str) -> asyncio.Lock:
        """Get or create an asyncio.Lock for the room to ensure serialized processing."""
        normalized = room_code.upper()
        if normalized not in self._room_locks:
            self._room_locks[normalized] = asyncio.Lock()
        return self._room_locks[normalized]

    async def start(self) -> None:
        """Start the WebSocket server and background ticker task."""
        self._is_running = True
        self._server = await websockets.serve(
            self.handle_connection,
            self.host,
            self.port,
            max_size=MAX_FRAME_SIZE,
            close_timeout=0.5,
        )

        # Retrieve actual bound port (crucial for ephemeral port 0 in tests)
        server_sockets = self._server.sockets
        if server_sockets:
            self.bound_port = server_sockets[0].getsockname()[1]
        else:
            self.bound_port = self.port

        self._ticker_task = asyncio.create_task(self._ticker_loop())
        logger.info(f"Impostor server running on ws://{self.host}:{self.bound_port}")

    async def stop(self) -> None:
        """Gracefully stop server, disconnect all clients, cancel tasks, and release port."""
        if not self._is_running and self._server is None:
            return
        self._is_running = False

        if self._ticker_task is not None:
            self._ticker_task.cancel()
            try:
                await self._ticker_task
            except asyncio.CancelledError:
                pass
            self._ticker_task = None

        # Notify all clients and close websockets
        await self.connection_manager.close_all(reason="Host closed the room. Server stopped.")

        # Cancel any lingering connection handler tasks
        for task in list(self._connection_tasks):
            if not task.done():
                task.cancel()
        self._connection_tasks.clear()

        # Purge room registry and room locks
        self.room_registry.clear()
        self._room_locks.clear()

        # Close listening socket
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

        self.bound_port = None
        logger.info("Impostor server stopped and port released.")

    async def _ticker_loop(self) -> None:
        """Background task ticking rooms every 500ms to fire expired timers."""
        while self._is_running:
            try:
                await asyncio.sleep(0.5)
                # Iterate over active rooms
                for engine in list(self.room_registry.all_rooms()):
                    lock = self._get_room_lock(engine.room_code)
                    async with lock:
                        fired = engine.tick()
                        if fired:
                            await self.connection_manager.broadcast_room_views(engine)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in ticker loop: {e}", exc_info=True)

    async def handle_connection(self, ws: Any) -> None:
        """Handle lifecycle and incoming frames for a connected WebSocket client."""
        logger.debug(f"New client connection from {ws.remote_address}")
        current_task = asyncio.current_task()
        if current_task is not None:
            self._connection_tasks.add(current_task)

        try:
            async for raw_msg in ws:
                # 1. Enforce frame size limit
                if isinstance(raw_msg, str) and len(raw_msg) > MAX_FRAME_SIZE:
                    await self.connection_manager.send_error(ws, "FRAME_TOO_LARGE", "Frame size exceeds limit.")
                    continue

                # 2. Enforce rate limiting
                if not self.connection_manager.check_rate_limit(ws):
                    await self.connection_manager.send_error(
                        ws, "RATE_LIMITED", "Too many requests. Please slow down."
                    )
                    continue

                # 3. Parse JSON frame
                try:
                    payload = json.loads(raw_msg)
                except Exception:
                    await self.connection_manager.send_error(ws, "INVALID_JSON", "Message must be valid JSON.")
                    continue

                if not isinstance(payload, dict):
                    await self.connection_manager.send_error(ws, "INVALID_PAYLOAD", "Payload must be a JSON object.")
                    continue

                msg_type = payload.get("type")
                req_id = payload.get("id")
                data = payload.get("data", {})
                if not isinstance(data, dict):
                    data = {}

                if not isinstance(msg_type, str):
                    await self.connection_manager.send_error(
                        ws, "INVALID_TYPE", "Message 'type' must be a string.", req_id=req_id
                    )
                    continue

                # 4. Dispatch message
                await self._dispatch_message(ws, msg_type, data, req_id)

        except (websockets.ConnectionClosed, asyncio.CancelledError):
            logger.debug(f"Connection closed for {ws.remote_address}")
        except Exception as e:
            logger.error(f"Unhandled error in connection handler: {e}", exc_info=True)
        finally:
            if current_task is not None:
                self._connection_tasks.discard(current_task)
            await self._handle_disconnect(ws)

    async def _handle_disconnect(self, ws: Any) -> None:
        """Handle client disconnection."""
        mapping = self.connection_manager.unregister(ws)
        if not mapping:
            return

        room_code, player_id = mapping
        engine = self.room_registry.get_room(room_code)
        if not engine:
            return

        lock = self._get_room_lock(room_code)
        async with lock:
            # If host disconnects, close room
            if player_id == engine.host_id:
                logger.info(f"Host {player_id} disconnected. Closing room {room_code}.")
                await self.connection_manager.broadcast_to_room(
                    room_code,
                    "room_closed",
                    {"reason": "Host disconnected. Room has closed."},
                )
                self.room_registry.remove_room(room_code)
                self._room_locks.pop(room_code, None)
            else:
                logger.info(f"Player {player_id} disconnected from room {room_code}.")
                engine.disconnect_player(player_id)
                await self.connection_manager.broadcast_room_views(engine)

    async def _dispatch_message(self, ws: Any, msg_type: str, data: Dict[str, Any], req_id: Optional[str]) -> None:
        """Route message to appropriate handler."""
        if msg_type == "ping":
            await self.connection_manager.send_json(ws, "pong", {}, req_id=req_id)
            return

        if msg_type == "create_room":
            await self._handle_create_room(ws, data, req_id)
            return

        if msg_type == "join_room":
            await self._handle_join_room(ws, data, req_id)
            return

        if msg_type == "rejoin":
            await self._handle_rejoin(ws, data, req_id)
            return

        # Room-specific actions require the client to be registered in a room
        mapping = self.connection_manager.get_info(ws)
        if not mapping:
            await self.connection_manager.send_error(ws, "NOT_IN_ROOM", "Must join a room first.", req_id=req_id)
            return

        room_code, player_id = mapping
        engine = self.room_registry.get_room(room_code)
        if not engine:
            await self.connection_manager.send_error(ws, "ROOM_NOT_FOUND", "Room not found.", req_id=req_id)
            return

        lock = self._get_room_lock(room_code)
        async with lock:
            try:
                await self._execute_room_action(ws, engine, player_id, msg_type, data, req_id)
            except ProtocolError as pe:
                await self.connection_manager.send_error(ws, pe.code, pe.message, req_id=req_id)
            except ValueError as ve:
                await self.connection_manager.send_error(ws, "INVALID_VALUE", str(ve), req_id=req_id)
            except Exception as e:
                logger.error(f"Error executing action {msg_type}: {e}", exc_info=True)
                await self.connection_manager.send_error(ws, "SERVER_ERROR", "Internal server error.", req_id=req_id)

    async def _handle_create_room(self, ws: Any, data: Dict[str, Any], req_id: Optional[str]) -> None:
        """Create room and add creating player as host."""
        name = data.get("name")
        if not name:
            await self.connection_manager.send_error(ws, "INVALID_NAME", "Player name is required.", req_id=req_id)
            return

        raw_settings = data.get("settings", {})
        settings = GameSettings()
        for k, v in raw_settings.items():
            if hasattr(settings, k):
                setattr(settings, k, v)

        engine = self.room_registry.create_room(settings=settings)
        try:
            player, token = engine.add_player(name)
        except ProtocolError as pe:
            self.room_registry.remove_room(engine.room_code)
            await self.connection_manager.send_error(ws, pe.code, pe.message, req_id=req_id)
            return

        self.connection_manager.register(ws, engine.room_code, player.id)

        # Send room_joined confirmation
        await self.connection_manager.send_json(
            ws,
            "room_joined",
            {
                "code": engine.room_code,
                "player_id": player.id,
                "token": token,
                "is_host": True,
            },
            req_id=req_id,
        )

        # Broadcast initial room state
        await self.connection_manager.broadcast_room_views(engine)

    async def _handle_join_room(self, ws: Any, data: Dict[str, Any], req_id: Optional[str]) -> None:
        """Join an existing room."""
        code = data.get("code", "")
        name = data.get("name", "")

        if not code or not isinstance(code, str):
            await self.connection_manager.send_error(ws, "INVALID_CODE", "Room code is required.", req_id=req_id)
            return
        if not name or not isinstance(name, str):
            await self.connection_manager.send_error(ws, "INVALID_NAME", "Player name is required.", req_id=req_id)
            return

        engine = self.room_registry.get_room(code)
        if not engine:
            await self.connection_manager.send_error(
                ws, "ROOM_NOT_FOUND", f"Room '{code.upper()}' does not exist.", req_id=req_id
            )
            return

        lock = self._get_room_lock(engine.room_code)
        async with lock:
            try:
                player, token = engine.add_player(name)
            except ProtocolError as pe:
                await self.connection_manager.send_error(ws, pe.code, pe.message, req_id=req_id)
                return

            self.connection_manager.register(ws, engine.room_code, player.id)

            await self.connection_manager.send_json(
                ws,
                "room_joined",
                {
                    "code": engine.room_code,
                    "player_id": player.id,
                    "token": token,
                    "is_host": player.is_host,
                },
                req_id=req_id,
            )
            await self.connection_manager.broadcast_room_views(engine)

    async def _handle_rejoin(self, ws: Any, data: Dict[str, Any], req_id: Optional[str]) -> None:
        """Rejoin after disconnect with player_id and token."""
        code = data.get("code", "")
        player_id = data.get("player_id", "")
        token = data.get("token", "")

        engine = self.room_registry.get_room(code)
        if not engine:
            await self.connection_manager.send_error(ws, "ROOM_NOT_FOUND", "Room not found.", req_id=req_id)
            return

        lock = self._get_room_lock(engine.room_code)
        async with lock:
            try:
                player = engine.rejoin_player(player_id, token)
            except ProtocolError as pe:
                await self.connection_manager.send_error(ws, pe.code, pe.message, req_id=req_id)
                return

            self.connection_manager.register(ws, engine.room_code, player.id)

            await self.connection_manager.send_json(
                ws,
                "room_joined",
                {
                    "code": engine.room_code,
                    "player_id": player.id,
                    "token": token,
                    "is_host": player.is_host,
                },
                req_id=req_id,
            )
            await self.connection_manager.broadcast_room_views(engine)

    async def _execute_room_action(
        self,
        ws: Any,
        engine: GameEngine,
        player_id: str,
        msg_type: str,
        data: Dict[str, Any],
        req_id: Optional[str],
    ) -> None:
        """Execute an action on the GameEngine."""
        if msg_type == "update_settings":
            new_settings = data.get("settings", {})
            engine.update_settings(player_id, new_settings)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "start_game":
            engine.start_game(player_id)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "confirm_role_seen":
            engine.confirm_role_seen(player_id)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "submit_clue":
            word = data.get("word", "")
            clue = engine.submit_clue(player_id, word)
            # Send clue_posted notification
            await self.connection_manager.broadcast_to_room(
                engine.room_code,
                "clue_posted",
                clue.to_dict(),
            )
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "end_turn":
            clue = engine.end_turn(player_id)
            await self.connection_manager.broadcast_to_room(
                engine.room_code,
                "clue_posted",
                clue.to_dict(),
            )
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "skip_discussion":
            engine.skip_discussion(player_id)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "cast_vote":
            target_id = data.get("target_id")
            engine.cast_vote(player_id, target_id)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "impostor_guess":
            word = data.get("word", "")
            engine.submit_impostor_guess(player_id, word)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "play_again":
            engine.play_again(player_id)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "kick_player":
            target_id = data.get("player_id", "")
            engine.remove_player(target_id, requester_id=player_id)
            # If target has a socket, notify and unregister
            target_ws = self.connection_manager.get_player_ws(engine.room_code, target_id)
            if target_ws is not None:
                await self.connection_manager.send_error(target_ws, "KICKED", "You have been kicked by the host.")
                self.connection_manager.unregister(target_ws)
            await self.connection_manager.broadcast_room_views(engine)

        elif msg_type == "leave":
            is_host = (player_id == engine.host_id)
            engine.remove_player(player_id, requester_id=player_id)
            self.connection_manager.unregister(ws)
            await self.connection_manager.send_json(ws, "left_room", {}, req_id=req_id)
            if is_host:
                await self.connection_manager.broadcast_to_room(
                    engine.room_code, "room_closed", {"reason": "Host left the game."}
                )
                self.room_registry.remove_room(engine.room_code)
                self._room_locks.pop(engine.room_code, None)
            else:
                await self.connection_manager.broadcast_room_views(engine)

        else:
            await self.connection_manager.send_error(
                ws, "UNKNOWN_TYPE", f"Unknown message type '{msg_type}'.", req_id=req_id
            )


def main() -> None:
    """CLI Entry point for python -m server.main."""
    parser = argparse.ArgumentParser(description="Impostor WebSocket Server")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Host address to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8765, help="Port to bind (default: 8765)")
    args = parser.parse_args()

    server = GameServer(host=args.host, port=args.port)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def shutdown() -> None:
        logger.info("Shutdown signal received.")
        loop.create_task(server.stop())

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, shutdown)
        except NotImplementedError:
            pass

    try:
        loop.run_until_complete(server.start())
        logger.info(f"Server started on ws://{args.host}:{args.port}. Press Ctrl+C to terminate.")
        loop.run_forever()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        loop.run_until_complete(server.stop())
        loop.close()


if __name__ == "__main__":
    main()
