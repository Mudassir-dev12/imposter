"""Connection Manager for tracking WebSockets, rate limiting, and privacy-preserving broadcasts."""

import asyncio
import json
import logging
import time
from typing import Any, Dict, Optional, Set, Tuple

from engine.game import GameEngine
from engine.protocol import build_player_view

logger = logging.getLogger("impostor.connection_manager")


class ConnectionManager:
    """Manages active WebSocket connections, player associations, rate limiting, and room broadcasts."""

    RATE_LIMIT_REQUESTS_PER_SEC: int = 25

    def __init__(self) -> None:
        # ws -> (room_code, player_id)
        self._ws_to_player: Dict[Any, Tuple[str, str]] = {}
        # (room_code, player_id) -> ws
        self._player_to_ws: Dict[Tuple[str, str], Any] = {}
        # room_code -> set of ws
        self._room_sockets: Dict[str, Set[Any]] = {}
        # ws -> (count, current_second_timestamp)
        self._rate_limits: Dict[Any, Tuple[int, int]] = {}

    def register(self, ws: Any, room_code: str, player_id: str) -> None:
        """Associate a WebSocket with a room and player ID."""
        normalized_code = room_code.upper()
        # If player had previous connection, replace it
        prev_ws = self._player_to_ws.get((normalized_code, player_id))
        if prev_ws is not None and prev_ws != ws:
            self.unregister(prev_ws)

        self._ws_to_player[ws] = (normalized_code, player_id)
        self._player_to_ws[(normalized_code, player_id)] = ws

        if normalized_code not in self._room_sockets:
            self._room_sockets[normalized_code] = set()
        self._room_sockets[normalized_code].add(ws)

    def unregister(self, ws: Any) -> Optional[Tuple[str, str]]:
        """Remove a WebSocket and return its former (room_code, player_id), or None."""
        self._rate_limits.pop(ws, None)
        mapping = self._ws_to_player.pop(ws, None)
        if not mapping:
            return None

        room_code, player_id = mapping
        self._player_to_ws.pop((room_code, player_id), None)

        if room_code in self._room_sockets:
            self._room_sockets[room_code].discard(ws)
            if not self._room_sockets[room_code]:
                self._room_sockets.pop(room_code, None)

        return room_code, player_id

    def get_info(self, ws: Any) -> Optional[Tuple[str, str]]:
        """Return (room_code, player_id) for the socket."""
        return self._ws_to_player.get(ws)

    def get_player_ws(self, room_code: str, player_id: str) -> Optional[Any]:
        """Return WebSocket for a specific player."""
        return self._player_to_ws.get((room_code.upper(), player_id))

    def get_room_sockets(self, room_code: str) -> Set[Any]:
        """Return all active WebSockets in a room."""
        return set(self._room_sockets.get(room_code.upper(), set()))

    def check_rate_limit(self, ws: Any) -> bool:
        """Check if incoming request exceeds rate limit. Returns True if allowed, False if rate limited."""
        now_sec = int(time.time())
        count, current_sec = self._rate_limits.get(ws, (0, now_sec))
        if current_sec == now_sec:
            if count >= self.RATE_LIMIT_REQUESTS_PER_SEC:
                return False
            self._rate_limits[ws] = (count + 1, now_sec)
        else:
            self._rate_limits[ws] = (1, now_sec)
        return True

    async def send_json(self, ws: Any, message_type: str, data: Any, req_id: Optional[str] = None) -> bool:
        """Send a formatted JSON message frame over WebSocket."""
        payload: Dict[str, Any] = {
            "type": message_type,
            "data": data,
        }
        if req_id is not None:
            payload["id"] = req_id

        try:
            await ws.send(json.dumps(payload))
            return True
        except Exception as e:
            logger.debug(f"Failed to send to {ws}: {e}")
            return False

    async def send_error(self, ws: Any, code: str, message: str, req_id: Optional[str] = None) -> bool:
        """Send an error frame to a client."""
        return await self.send_json(
            ws,
            "error",
            {"code": code, "message": message},
            req_id=req_id,
        )

    async def broadcast_room_views(self, engine: GameEngine) -> None:
        """Broadcast privacy-preserving views to each player in the room.

        CRITICAL SECRECY IMPLEMENTATION:
        Each connected client receives an independently constructed view
        via `build_player_view(engine, p_id)` ensuring no client receives
        unauthorized data (e.g. impostor IDs or secret word).
        """
        room_code = engine.room_code
        for player_id, player in engine.players.items():
            ws = self.get_player_ws(room_code, player_id)
            if ws is not None:
                view = build_player_view(engine, player_id)
                await self.send_json(ws, "room_state", view)

    async def broadcast_to_room(self, room_code: str, message_type: str, data: Any) -> None:
        """Broadcast a generic message frame to all sockets in a room."""
        sockets = self.get_room_sockets(room_code)
        for ws in sockets:
            await self.send_json(ws, message_type, data)

    async def close_all(self, reason: str = "Host closed the room. Server stopped.") -> None:
        """Notify all connected clients that the room/server is closed, close sockets, and clear state."""
        all_sockets: Set[Any] = set(self._ws_to_player.keys())
        for sockets in self._room_sockets.values():
            all_sockets.update(sockets)
        for ws in self._rate_limits.keys():
            all_sockets.add(ws)

        # Broadcast room_closed concurrently
        send_coros = [self.send_json(ws, "room_closed", {"reason": reason}) for ws in all_sockets]
        if send_coros:
            await asyncio.gather(*send_coros, return_exceptions=True)

        # Close all sockets concurrently with a short timeout
        async def _safe_close(w: Any) -> None:
            try:
                await asyncio.wait_for(w.close(), timeout=0.5)
            except Exception:
                pass

        close_coros = [_safe_close(ws) for ws in all_sockets]
        if close_coros:
            await asyncio.gather(*close_coros, return_exceptions=True)

        self._ws_to_player.clear()
        self._player_to_ws.clear()
        self._room_sockets.clear()
        self._rate_limits.clear()
