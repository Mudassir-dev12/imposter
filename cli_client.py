"""Interactive Terminal Client for the Impostor Game.

Allows 3+ players to play a complete game of Impostor across separate terminal windows.
Usage:
    python cli_client.py --url ws://localhost:8765
"""

import argparse
import asyncio
import json
import sys
from typing import Any, Dict, Optional

import websockets

# ANSI Colors
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
MAGENTA = "\033[95m"
DIM = "\033[2m"


class ImpostorCliClient:
    """Terminal client handling bidirectional WebSocket communication and interactive UI."""

    def __init__(self, server_url: str) -> None:
        self.server_url: str = server_url
        self.ws: Optional[Any] = None
        self.room_code: Optional[str] = None
        self.player_id: Optional[str] = None
        self.token: Optional[str] = None
        self.is_host: bool = False
        self.current_view: Dict[str, Any] = {}
        self.running: bool = True

    async def run(self) -> None:
        """Connect to the server and run concurrent receiver and input loops."""
        print(f"\n{BOLD}{CYAN}=== Welcome to IMPOSTOR ==={RESET}")
        print(f"Connecting to {self.server_url} ...")

        try:
            async with websockets.connect(self.server_url) as ws:
                self.ws = ws
                print(f"{GREEN}Connected!{RESET}\n")

                # Concurrently run receiver and input handler
                receiver_task = asyncio.create_task(self.receive_loop())
                input_task = asyncio.create_task(self.input_loop())

                done, pending = await asyncio.wait(
                    [receiver_task, input_task],
                    return_when=asyncio.FIRST_COMPLETED,
                )
                for task in pending:
                    task.cancel()

        except ConnectionRefusedError:
            print(f"{RED}Error: Could not connect to {self.server_url}. Is the server running?{RESET}")
        except Exception as e:
            print(f"{RED}Connection error: {e}{RESET}")

    async def send_json(self, msg_type: str, data: Optional[Dict[str, Any]] = None) -> None:
        """Send a JSON text frame to the server."""
        if self.ws:
            payload = {"type": msg_type, "data": data or {}}
            await self.ws.send(json.dumps(payload))

    async def receive_loop(self) -> None:
        """Continuously listen for incoming messages from the server."""
        assert self.ws is not None
        try:
            async for raw_message in self.ws:
                try:
                    msg = json.loads(raw_message)
                    await self.handle_message(msg)
                except json.JSONDecodeError:
                    print(f"{RED}Received malformed message: {raw_message}{RESET}")
        except websockets.ConnectionClosed:
            print(f"\n{YELLOW}Connection to server closed.{RESET}")
            self.running = False

    async def handle_message(self, msg: Dict[str, Any]) -> None:
        """Process and print server message frames."""
        msg_type = msg.get("type")
        data = msg.get("data", {})

        if msg_type == "room_joined":
            self.room_code = data.get("code")
            self.player_id = data.get("player_id")
            self.token = data.get("token")
            self.is_host = data.get("is_host", False)
            print(f"\n{BOLD}{GREEN}✓ Room Joined!{RESET}")
            print(f"Room Code: {BOLD}{CYAN}{self.room_code}{RESET} | Player ID: {self.player_id} | Host: {self.is_host}")
            print(f"{DIM}Keep your token for rejoining: {self.token}{RESET}\n")

        elif msg_type == "room_state":
            prev_phase = self.current_view.get("phase")
            self.current_view = data
            curr_phase = data.get("phase")

            if prev_phase != curr_phase:
                self.render_phase_change(curr_phase, data)
            else:
                self.render_state_update(data)

        elif msg_type == "clue_posted":
            author = data.get("player_id")
            word = data.get("word")
            rnd = data.get("round_index")
            print(f"  {CYAN}▸ [Round {rnd}] {author}: {BOLD}{word}{RESET}")

        elif msg_type == "room_closed":
            reason = data.get("reason", "Room was closed.")
            print(f"\n{BOLD}{RED}✖ {reason}{RESET}\n")
            self.running = False

        elif msg_type == "error":
            code = data.get("code")
            message = data.get("message")
            print(f"\n{RED}Error [{code}]: {message}{RESET}")

        elif msg_type == "pong":
            print(f"{DIM}pong{RESET}")

    def render_phase_change(self, phase: str, view: Dict[str, Any]) -> None:
        """Render major phase transitions."""
        print(f"\n{BOLD}{MAGENTA}{'=' * 50}{RESET}")
        print(f"{BOLD}{MAGENTA}PHASE: {phase}{RESET}")
        print(f"{BOLD}{MAGENTA}{'=' * 50}{RESET}")

        if phase == "ROLE_REVEAL":
            role = view.get("my_role")
            category = view.get("category")
            word = view.get("my_word")

            if role == "IMPOSTOR":
                print(f"{BOLD}{RED}YOU ARE THE IMPOSTOR! 🕵️{RESET}")
                if category:
                    print(f"Category Hint: {BOLD}{YELLOW}{category}{RESET}")
                else:
                    print(f"{DIM}(Category hint disabled in settings){RESET}")
                print("Blend in, listen carefully, and don't get caught!")
            else:
                print(f"{BOLD}{GREEN}YOU ARE CREW! 👨‍🚀{RESET}")
                print(f"Category: {BOLD}{YELLOW}{category}{RESET}")
                print(f"Secret Word: {BOLD}{GREEN}{word}{RESET}")

            print(f"\n{CYAN}Type {BOLD}'c'{RESET}{CYAN} to confirm you've seen your role.{RESET}")

        elif phase == "CLUE_ROUND":
            curr_turn = view.get("current_turn_player_id")
            rnd = view.get("round_index")
            print(f"{BOLD}Clue Round {rnd}{RESET}")
            if curr_turn == self.player_id:
                print(f"{BOLD}{YELLOW}★ IT IS YOUR TURN! Type your one-word clue below.{RESET}")
            else:
                print(f"Waiting for {curr_turn} to submit a clue...")

        elif phase == "DISCUSSION":
            print(f"{BOLD}{YELLOW}Discussion time! Free talk in real life.{RESET}")
            clues = view.get("clues", [])
            print("Clues posted:")
            for c in clues:
                print(f"  - {c['player_id']}: {c['word']}")
            if self.is_host:
                print(f"{CYAN}As host, type {BOLD}'skip'{RESET}{CYAN} to jump straight to voting.{RESET}")

        elif phase == "VOTING":
            print(f"{BOLD}{YELLOW}VOTING PHASE{RESET}")
            print("Vote for who you believe is the impostor (or abstain).")
            print("Players:")
            for p in view.get("players", []):
                if p["id"] != self.player_id:
                    print(f"  [{p['id']}] {p['name']}")
            print(f"{CYAN}Type: {BOLD}vote <player_id>{RESET}{CYAN} or {BOLD}abstain{RESET}")

        elif phase == "IMPOSTOR_GUESS":
            caught_id = view.get("caught_impostor_id")
            if caught_id == self.player_id:
                print(f"\n{BOLD}{RED}YOU WERE CAUGHT! 🚨{RESET}")
                print(f"You have ONE chance to steal the win.")
                print(f"{BOLD}{YELLOW}Guess the secret word! Type: {BOLD}guess <word>{RESET}")
            else:
                print(f"\n{YELLOW}Impostor {caught_id} was caught! They are now guessing the secret word...{RESET}")

        elif phase == "ROUND_END":
            result = view.get("round_result", {})
            outcome = result.get("outcome")
            secret = result.get("secret_word")
            impostors = result.get("impostor_ids", [])
            print(f"\n{BOLD}{CYAN}=== ROUND RESULT: {outcome} ==={RESET}")
            print(f"Secret Word: {BOLD}{GREEN}{secret}{RESET}")
            print(f"Impostor(s): {BOLD}{RED}{', '.join(impostors)}{RESET}")
            print("\nLeaderboard:")
            scores = result.get("scores", {})
            for p in view.get("players", []):
                p_id = p["id"]
                delta = result.get("score_delta", {}).get(p_id, 0)
                delta_str = f"(+{delta})" if delta > 0 else ""
                print(f"  {p['name']} ({p_id}): {scores.get(p_id, 0)} pts {GREEN}{delta_str}{RESET}")

            if self.is_host:
                print(f"\n{CYAN}Host: Type {BOLD}'again'{RESET}{CYAN} to play again or {BOLD}'leave'{RESET}.")

    def render_state_update(self, view: Dict[str, Any]) -> None:
        """Render minor status updates within the same phase."""
        phase = view.get("phase")
        if phase == "LOBBY":
            players = view.get("players", [])
            print(f"\rLobby: {len(players)} players connected: {', '.join(p['name'] for p in players)}", end="", flush=True)

        elif phase == "CLUE_ROUND":
            curr_turn = view.get("current_turn_player_id")
            if curr_turn == self.player_id:
                print(f"\n{BOLD}{YELLOW}★ It is your turn! Type your clue:{RESET} ", end="", flush=True)

        elif phase == "VOTING":
            prog = view.get("vote_progress", {})
            print(f"\rVotes cast: {prog.get('voted_count', 0)} of {prog.get('total', 0)}", end="", flush=True)

    async def input_loop(self) -> None:
        """Read line inputs from stdin asynchronously and send corresponding commands."""
        loop = asyncio.get_running_loop()

        while self.running:
            if not self.room_code:
                # Initial menu
                print("\nOptions:")
                print("  1. Create Room")
                print("  2. Join Room")
                print("  3. Rejoin Room")
                print("  4. Quit")
                choice = await loop.run_in_executor(None, input, "Select [1-4]: ")
                choice = choice.strip()

                if choice == "1":
                    name = await loop.run_in_executor(None, input, "Enter your name: ")
                    await self.send_json("create_room", {"name": name.strip()})
                    await asyncio.sleep(0.5)

                elif choice == "2":
                    code = await loop.run_in_executor(None, input, "Enter 4-letter room code: ")
                    name = await loop.run_in_executor(None, input, "Enter your name: ")
                    await self.send_json("join_room", {"code": code.strip().upper(), "name": name.strip()})
                    await asyncio.sleep(0.5)

                elif choice == "3":
                    code = await loop.run_in_executor(None, input, "Enter 4-letter room code: ")
                    p_id = await loop.run_in_executor(None, input, "Enter your player ID: ")
                    tok = await loop.run_in_executor(None, input, "Enter your token: ")
                    await self.send_json("rejoin", {"code": code.strip().upper(), "player_id": p_id.strip(), "token": tok.strip()})
                    await asyncio.sleep(0.5)

                elif choice == "4":
                    self.running = False
                    break

            else:
                # In-game interactive commands
                cmd_line = await loop.run_in_executor(None, input)
                cmd_line = cmd_line.strip()
                if not cmd_line:
                    continue

                phase = self.current_view.get("phase")

                if cmd_line.lower() == "ping":
                    await self.send_json("ping")

                elif cmd_line.lower() == "leave":
                    await self.send_json("leave")
                    self.room_code = None

                elif phase == "LOBBY":
                    if cmd_line.lower() == "start":
                        await self.send_json("start_game")
                    elif cmd_line.lower().startswith("kick "):
                        target = cmd_line.split(" ", 1)[1].strip()
                        await self.send_json("kick_player", {"player_id": target})
                    elif cmd_line.lower() == "help":
                        print("Lobby commands: 'start' (host only), 'kick <id>', 'leave'")
                    else:
                        print(f"Unknown lobby command '{cmd_line}'. Type 'start' to begin.")

                elif phase == "ROLE_REVEAL":
                    if cmd_line.lower() in ("c", "confirm", "ok"):
                        await self.send_json("confirm_role_seen")
                    else:
                        print("Type 'c' to confirm you saw your role.")

                elif phase == "CLUE_ROUND":
                    # Submitting a clue
                    await self.send_json("submit_clue", {"word": cmd_line})

                elif phase == "DISCUSSION":
                    if cmd_line.lower() == "skip" and self.is_host:
                        await self.send_json("skip_discussion")
                    else:
                        print("Waiting for discussion timer. Host can type 'skip'.")

                elif phase == "VOTING":
                    if cmd_line.lower() == "abstain":
                        await self.send_json("cast_vote", {"target_id": None})
                    elif cmd_line.lower().startswith("vote "):
                        target = cmd_line.split(" ", 1)[1].strip()
                        await self.send_json("cast_vote", {"target_id": target})
                    else:
                        # Direct target ID entry
                        await self.send_json("cast_vote", {"target_id": cmd_line})

                elif phase == "IMPOSTOR_GUESS":
                    if cmd_line.lower().startswith("guess "):
                        guess_word = cmd_line.split(" ", 1)[1].strip()
                        await self.send_json("impostor_guess", {"word": guess_word})
                    else:
                        await self.send_json("impostor_guess", {"word": cmd_line})

                elif phase == "ROUND_END":
                    if cmd_line.lower() == "again":
                        await self.send_json("play_again")
                    else:
                        print("Type 'again' (host only) to play another round or 'leave'.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Impostor Interactive Terminal Client")
    parser.add_argument("--url", type=str, default="ws://127.0.0.1:8765", help="Server WebSocket URL")
    args = parser.parse_args()

    client = ImpostorCliClient(server_url=args.url)
    try:
        asyncio.run(client.run())
    except KeyboardInterrupt:
        print("\nExiting. Goodbye!")


if __name__ == "__main__":
    main()
