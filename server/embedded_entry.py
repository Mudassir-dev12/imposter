"""Embedded entry point and supervisor for running the Impostor server inside serious_python."""

import asyncio
import json
import logging
import os
import secrets
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# Configure unbuffered stdout logging for Android logcat visibility
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [embedded_entry] %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("embedded_entry")

# Ensure app root and __pypackages__ are on sys.path
current_dir = Path(__file__).resolve().parent
app_root = current_dir.parent if current_dir.name == "server" else current_dir
for candidate in [app_root, app_root / "__pypackages__", current_dir / "__pypackages__"]:
    candidate_str = str(candidate)
    if candidate.is_dir() and candidate_str not in sys.path:
        sys.path.insert(0, candidate_str)

from server.main import GameServer


class ServerSupervisor:
    """Long-lived supervisor hosting an asyncio event loop and a loopback-only control channel."""

    def __init__(
        self,
        token: str,
        control_host: str = "127.0.0.1",
        control_port: int = 8766,
    ) -> None:
        # Strictly enforce loopback-only binding
        if control_host != "127.0.0.1":
            logger.warning("[supervisor] Non-loopback control_host '%s' requested. Enforcing 127.0.0.1 for security.", control_host)
            control_host = "127.0.0.1"

        self.token: str = token
        self.control_host: str = control_host
        self.control_port: int = control_port
        self.actual_control_port: Optional[int] = None

        self.game_server: Optional[GameServer] = None
        self._server: Optional[asyncio.Server] = None
        self._stop_event: asyncio.Event = asyncio.Event()
        self._lock: asyncio.Lock = asyncio.Lock()

    async def start(self) -> None:
        """Start the loopback control channel server."""
        self._server = await asyncio.start_server(
            self._handle_client,
            self.control_host,
            self.control_port,
        )

        if self._server.sockets:
            self.actual_control_port = self._server.sockets[0].getsockname()[1]
        else:
            self.actual_control_port = self.control_port

        logger.info(
            "[supervisor] Control channel listening on %s:%d (auth required)",
            self.control_host,
            self.actual_control_port,
        )

    async def stop(self) -> None:
        """Stop supervisor control channel and any active game server."""
        async with self._lock:
            if self.game_server is not None:
                try:
                    await self.game_server.stop()
                except Exception as e:
                    logger.error("[supervisor] Error stopping GameServer during supervisor shutdown: %s", e)
                finally:
                    self.game_server = None

            if self._server is not None:
                self._server.close()
                try:
                    await asyncio.wait_for(self._server.wait_closed(), timeout=0.5)
                except Exception:
                    pass
                self._server = None

            self._stop_event.set()
        logger.info("[supervisor] Supervisor stopped.")

    async def wait_stopped(self) -> None:
        """Wait until supervisor is requested to quit."""
        await self._stop_event.wait()

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        """Handle incoming control channel connection with authentication and command dispatch."""
        peer = writer.get_extra_info("peername")
        logger.debug("[supervisor] Control connection accepted from %s", peer)
        authenticated = False

        try:
            while True:
                line_bytes = await reader.readline()
                if not line_bytes:
                    break
                line = line_bytes.decode("utf-8", errors="replace").strip()
                if not line:
                    continue

                # 1. Support JSON frames: {"token": "...", "command": "...", "port": ...}
                if line.startswith("{"):
                    try:
                        payload = json.loads(line)
                        req_token = payload.get("token", "")
                        cmd = str(payload.get("command", "")).upper()
                        port_arg = payload.get("port")
                    except Exception:
                        writer.write(b'{"status": "error", "message": "INVALID_JSON"}\n')
                        await writer.drain()
                        continue

                    if not secrets.compare_digest(req_token, self.token):
                        logger.warning("[supervisor] Unauthorized control attempt with invalid token from %s", peer)
                        writer.write(b'{"status": "error", "message": "UNAUTHORIZED"}\n')
                        await writer.drain()
                        break

                    res = await self._execute_command(cmd, port_arg)
                    writer.write((json.dumps(res) + "\n").encode("utf-8"))
                    await writer.drain()
                    if cmd == "QUIT":
                        break
                    continue

                # 2. Support line-based text commands
                parts = line.split()
                cmd = parts[0].upper()

                if cmd == "AUTH":
                    if len(parts) < 2:
                        writer.write(b"ERROR MISSING_TOKEN\n")
                        await writer.drain()
                        break
                    token_candidate = parts[1]
                    if not secrets.compare_digest(token_candidate, self.token):
                        logger.warning("[supervisor] Unauthorized control attempt with invalid token from %s", peer)
                        writer.write(b"ERROR UNAUTHORIZED\n")
                        await writer.drain()
                        break

                    authenticated = True
                    # Check for inline command after AUTH: e.g. AUTH <token> START 8765
                    if len(parts) > 2:
                        sub_cmd = parts[2].upper()
                        sub_arg = parts[3] if len(parts) > 3 else None
                        resp_text = await self._execute_text_command(sub_cmd, sub_arg)
                        writer.write((resp_text + "\n").encode("utf-8"))
                        await writer.drain()
                        if sub_cmd == "QUIT":
                            break
                    else:
                        writer.write(b"OK AUTHENTICATED\n")
                        await writer.drain()
                    continue

                if not authenticated:
                    logger.warning("[supervisor] Command '%s' rejected: client not authenticated (%s)", cmd, peer)
                    writer.write(b"ERROR UNAUTHORIZED\n")
                    await writer.drain()
                    break

                port_arg = parts[1] if len(parts) > 1 else None
                resp_text = await self._execute_text_command(cmd, port_arg)
                writer.write((resp_text + "\n").encode("utf-8"))
                await writer.drain()
                if cmd == "QUIT":
                    break

        except Exception as e:
            logger.error("[supervisor] Error handling control connection: %s", e, exc_info=True)
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _execute_text_command(self, cmd: str, port_arg: Optional[Any]) -> str:
        """Execute command and return formatted text line response."""
        res = await self._execute_command(cmd, port_arg)
        if res.get("status") == "ok":
            if cmd == "STATUS":
                return f"OK STATUS {json.dumps(res.get('data', {}))}"
            return f"OK {res.get('message', 'SUCCESS')}"
        return f"ERROR {res.get('message', 'UNKNOWN')}"

    async def _execute_command(self, cmd: str, port_arg: Optional[Any]) -> Dict[str, Any]:
        """Execute command under synchronization lock."""
        async with self._lock:
            if cmd == "START":
                target_port = 8765
                if port_arg is not None:
                    try:
                        target_port = int(port_arg)
                    except ValueError:
                        return {"status": "error", "message": "INVALID_PORT"}

                if self.game_server is not None and self.game_server._is_running:
                    if self.game_server.bound_port == target_port:
                        logger.info("[supervisor] START: GameServer already running on port %d", target_port)
                        return {
                            "status": "ok",
                            "message": f"ALREADY_RUNNING {target_port}",
                            "data": self._get_status_data(),
                        }
                    # Restart on different port
                    logger.info("[supervisor] Restarting GameServer on new port %d (was %s)", target_port, self.game_server.bound_port)
                    await self.game_server.stop()
                    self.game_server = None

                try:
                    self.game_server = GameServer(host="0.0.0.0", port=target_port)
                    await self.game_server.start()
                    bound = self.game_server.bound_port or target_port
                    logger.info("[supervisor] GameServer started successfully on 0.0.0.0:%d", bound)
                    return {
                        "status": "ok",
                        "message": f"STARTED {bound}",
                        "data": self._get_status_data(),
                    }
                except Exception as e:
                    logger.error("[supervisor] Failed to start GameServer on port %d: %s", target_port, e, exc_info=True)
                    self.game_server = None
                    return {"status": "error", "message": f"START_FAILED: {e}"}

            elif cmd == "STOP":
                if self.game_server is None or not self.game_server._is_running:
                    logger.info("[supervisor] STOP: GameServer already stopped (idempotent)")
                    return {
                        "status": "ok",
                        "message": "ALREADY_STOPPED",
                        "data": self._get_status_data(),
                    }

                try:
                    logger.info("[supervisor] Stopping GameServer ...")
                    await self.game_server.stop()
                    self.game_server = None
                    logger.info("[supervisor] GameServer stopped cleanly and port released.")
                    return {
                        "status": "ok",
                        "message": "STOPPED",
                        "data": self._get_status_data(),
                    }
                except Exception as e:
                    logger.error("[supervisor] Error stopping GameServer: %s", e, exc_info=True)
                    self.game_server = None
                    return {"status": "error", "message": f"STOP_FAILED: {e}"}

            elif cmd == "STATUS":
                return {
                    "status": "ok",
                    "data": self._get_status_data(),
                }

            elif cmd == "QUIT":
                logger.info("[supervisor] QUIT command received. Shutting down supervisor...")
                if self.game_server is not None:
                    try:
                        await self.game_server.stop()
                    except Exception as e:
                        logger.error("[supervisor] Error stopping GameServer during QUIT: %s", e)
                    self.game_server = None
                self._stop_event.set()
                return {"status": "ok", "message": "BYE"}

            else:
                return {"status": "error", "message": f"UNKNOWN_COMMAND '{cmd}'"}

    def _get_status_data(self) -> Dict[str, Any]:
        """Collect current game server status metrics."""
        if self.game_server is not None and self.game_server._is_running:
            return {
                "running": True,
                "port": self.game_server.bound_port or self.game_server.port,
                "rooms": len(self.game_server.room_registry),
                "connections": len(self.game_server.connection_manager._ws_to_player),
            }
        return {
            "running": False,
            "port": None,
            "rooms": 0,
            "connections": 0,
        }


async def _run_supervisor() -> None:
    token = os.environ.get("EMBEDDED_CONTROL_TOKEN")
    if not token or not token.strip():
        token = secrets.token_hex(16)
        logger.info("[supervisor] Generated ephemeral control token: %s", token)
    else:
        token = token.strip()

    port_env = os.environ.get("EMBEDDED_CONTROL_PORT")
    control_port = int(port_env.strip()) if (port_env and port_env.strip().isdigit()) else 8766

    supervisor = ServerSupervisor(token=token, control_host="127.0.0.1", control_port=control_port)
    await supervisor.start()

    # If AUTO_START is requested via environment variable, start GameServer immediately
    auto_game_port_env = os.environ.get("EMBEDDED_SERVER_PORT")
    if auto_game_port_env and auto_game_port_env.strip().isdigit() and os.environ.get("EMBEDDED_AUTO_START") == "1":
        auto_port = int(auto_game_port_env.strip())
        logger.info("[supervisor] Auto-starting GameServer on port %d...", auto_port)
        await supervisor._execute_command("START", auto_port)

    try:
        await supervisor.wait_stopped()
    except (asyncio.CancelledError, KeyboardInterrupt):
        logger.info("[supervisor] Supervisor cancelled. Cleaning up...")
    finally:
        await supervisor.stop()


def main() -> None:
    logger.info("Embedded Python supervisor main() started. Python version: %s", sys.version)
    try:
        asyncio.run(_run_supervisor())
    except Exception as e:
        logger.critical("Fatal error in embedded supervisor: %s", e, exc_info=True)
        raise


# SeriousPython on Android loads this file via PyImport_ImportModule(),
# which sets __name__ to the module name (e.g. 'server.embedded_entry' or 'embedded_entry'), NOT '__main__'.
# To ensure the supervisor starts when launched by SeriousPython, check RUN_SUPERVISOR_ON_IMPORT or __name__ == '__main__':
if __name__ == "__main__" or os.environ.get("RUN_SUPERVISOR_ON_IMPORT") == "1":
    main()
