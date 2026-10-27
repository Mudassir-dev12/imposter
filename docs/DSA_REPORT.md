# Data Structures and Algorithms (DSA) Report - Impostor

This report documents the custom data structures implemented for the **Impostor** game engine and server. In accordance with course requirements, these core structures are implemented from scratch in pure Python with no external library shortcuts (e.g. no use of standard library `heapq` or `collections.deque`).

---

## 1. Summary Matrix

| Data Structure | Implementation File | Primary Use Case in Impostor | Key Operations & Time Complexity | Space Complexity |
| :--- | :--- | :--- | :--- | :--- |
| **Circular Doubly-Linked List** | `engine/structures/circular_linked_list.py` | Seat order and clue-turn rotation | `append`: $O(1)$<br>`remove`: $O(n)$ search, $O(1)$ unlink<br>`next`: $O(1)$<br>`peek`: $O(1)$ | $O(n)$ total, $O(1)$ per node |
| **Min-Heap (Priority Queue)** | `engine/structures/min_heap.py` | Expiry timers for turn, discussion, and voting phases | `push`: $O(\log n)$<br>`pop_min`: $O(\log n)$<br>`peek`: $O(1)$<br>`remove(id)`: $O(\log n)$ | $O(n)$ array + $O(n)$ index map |
| **FIFO Queue (Linked List)** | `engine/structures/queue.py` | Per-room incoming message and action queue | `enqueue`: $O(1)$<br>`dequeue`: $O(1)$<br>`peek`: $O(1)$<br>`is_empty`: $O(1)$ | $O(n)$ total, $O(1)$ per node |
| **Chained Hash Table** | `engine/structures/hash_table.py` | Room registry (`room_code` $\rightarrow$ engine) & player lookup | `put`: Avg $O(1)$, Worst $O(n)$<br>`get`: Avg $O(1)$, Worst $O(n)$<br>`remove`: Avg $O(1)$, Worst $O(n)$ | $O(n + m)$ ($m$ buckets, $n$ entries) |

---

## 2. Structure Breakdown

### 2.1 Circular Doubly-Linked List (`CircularLinkedList[T]`)

- **File**: `engine/structures/circular_linked_list.py`
- **Why Chosen**: In Impostor, players sit around a table in a defined seating order. During clue rounds, turn progression cycles continuously from player to player for multiple rounds. If a standard linear array or singly-linked list were used, wraparound from the last player to the first player would require manual index modulo calculations and complex resizing during player disconnects.
- **Key Design Decisions**:
  - Doubly-linked (`prev` and `next` pointers) so that node deletion and circular wrapping are seamless.
  - An internal iteration cursor (`_current`) allows constant-time turn advancement (`next()`) and inspection (`peek()`).
  - **Remove-While-Iterating Guarantee**: If a player disconnects or leaves while it is currently their turn, `remove()` detects that `_current` matches the target node and automatically advances `_current` to `target.next` before unlinking the node. This guarantees that turn order is never corrupted and iterators do not crash on orphaned references.

#### Operations & Complexity
- `append(value)`: Inserts at tail (before head). Links updated in $O(1)$ time, $O(1)$ space.
- `prepend(value)`: Inserts at head. $O(1)$ time, $O(1)$ space.
- `remove(value)`: Locates the target node in $O(n)$ time, unlinks in $O(1)$ time. Safe removal on empty list, single element list, head, tail, and active cursor.
- `next()`: Advances cursor to `_current.next` and returns value. $O(1)$ time, $O(1)$ space.
- `peek()`: Returns value at current cursor without advancing. $O(1)$ time, $O(1)$ space.
- `set_current(value)`: Scans list to position cursor on a specific player. $O(n)$ time, $O(1)$ space.
- `to_list()`: Traverses circular list starting at head, completing exactly one cycle. $O(n)$ time, $O(n)$ space.

---

### 2.2 Binary Min-Heap (`MinHeap[T]`)

- **File**: `engine/structures/min_heap.py`
- **Why Chosen**: Multiplayer games rely heavily on time limits (turn timeouts, discussion timers, voting countdowns). Multiple timers may be scheduled concurrently. A priority queue ordered by expiry timestamp ($\text{epoch\_seconds}$) allows the engine/server loop to immediately know which timer expires next in $O(1)$ time (`peek()`), and process expired events in $O(\log n)$ time (`pop_min()`).
- **Key Design Decisions**:
  - Implemented completely from scratch using a flat 0-indexed array with explicit `_sift_up` and `_sift_down` algorithms.
  - **Index-Tracked Arbitrary Deletion**: Standard heaps require $O(n)$ to find and delete an item that has not yet reached the root (e.g. when a player submits a clue early, cancelling their turn timer). Our `MinHeap` maintains an internal `_id_to_index: dict[str, int]` hash map. Whenever elements are swapped during sift operations, their indices in the map are updated in $O(1)$. This allows any scheduled timer to be cancelled by its ID in strict $O(\log n)$ time.

#### Operations & Complexity
- `push(key, value, item_id)`: Appends to end of array and calls `_sift_up`. If `item_id` already exists, replaces the existing entry. Time: $O(\log n)$, Space: $O(1)$.
- `peek()`: Inspects root node at index 0. Time: $O(1)$, Space: $O(1)$.
- `pop_min()`: Swaps root with last element, pops last element, and calls `_sift_down(0)`. Time: $O(\log n)$, Space: $O(1)$.
- `remove(item_id)`: Looks up index in $O(1)$, swaps with last element, pops, and restores heap property via sift up/down. Time: $O(\log n)$, Space: $O(1)$.

---

### 2.3 FIFO Queue (`Queue[T]`)

- **File**: `engine/structures/queue.py`
- **Why Chosen**: In a real-time WebSocket party game, players submit clues, votes, and join requests asynchronously. To guarantee deterministic state transitions and prevent race conditions, each game room processes actions sequentially through a dedicated incoming message queue.
- **Key Design Decisions**:
  - Node-based singly-linked list with dedicated `_head` (front) and `_tail` (rear) pointers.
  - Avoids Python `list.pop(0)` which is an $O(n)$ shift operation.
  - Every `enqueue` appends to tail in $O(1)$, and every `dequeue` removes from head in $O(1)$.

#### Operations & Complexity
- `enqueue(item)`: Adds new node at tail. Time: $O(1)$, Space: $O(1)$.
- `dequeue()`: Removes node at head. Time: $O(1)$, Space: $O(1)$.
- `peek()`: Returns head value without removing. Time: $O(1)$, Space: $O(1)$.
- `size()` / `len(q)`: Maintains atomic integer count. Time: $O(1)$, Space: $O(1)$.

---

### 2.4 Chained Hash Table (`ChainedHashTable[K, V]`)

- **File**: `engine/structures/hash_table.py`
- **Why Chosen**: The game server must register active rooms by a 4-letter room code (e.g., `"ABCD"`) and map player IDs to player connection records.
- **Key Design Decisions**:
  - Employs separate chaining: an array of buckets, where each bucket is a chain of `HashEntry(key, value)` objects.
  - Dynamically resizes (doubles capacity and rehashes all elements) whenever the load factor $\alpha = \frac{n}{m}$ exceeds $0.75$.
  - Python dictionary syntax support (`ht[key] = val`, `key in ht`, `del ht[key]`).

#### Operations & Complexity
- `put(key, value)`: Computes hash bucket index, updates existing key or appends. Triggers rehash if load factor $> 0.75$. Time: Average $O(1)$, Worst $O(n)$, Space: $O(1)$ amortized.
- `get(key, default)`: Computes hash bucket index and traverses chain. Time: Average $O(1)$, Worst $O(n)$, Space: $O(1)$.
- `remove(key)`: Unlinks entry from bucket chain. Time: Average $O(1)$, Worst $O(n)$, Space: $O(1)$.
- `_resize(new_capacity)`: Allocates new bucket array of size $2m$ and re-hashes all $n$ entries. Time: $O(n + m)$, Space: $O(n + m)$.

---

## 3. Data Structure Integration in Game Engine (`engine/game.py`)

In Milestone 2, the custom data structures were embedded directly into `GameEngine`:

1. **`self._turn_order: CircularLinkedList[str]`**:
   - Initialized in `start_game()`: player IDs are placed into a random seat order and appended to the circular list in $O(1)$ per player.
   - Polled in `current_turn_player_id`: calls `_turn_order.peek()` in $O(1)$ time to determine which player is currently eligible to submit a clue.
   - Rotated in `_record_clue()`: advances turn rotation via `_turn_order.next()` in $O(1)$ time.
   - Cleaned up in `remove_player()`: unlinks leaving/kicked players in $O(n)$ search, $O(1)$ unlink without disrupting current iteration.

2. **`self._timer_heap: MinHeap[TimerEvent]`**:
   - `_schedule_timer()`: pushes deadline events into the heap in $O(\log n)$ time.
   - `_cancel_timer()`: cancels active timers by unique identifier in $O(\log n)$ time via the index-tracking map.
   - `tick(now)`: checks the earliest deadline in $O(1)$ with `peek()`, and extracts expired timer events in $O(\log n)$ with `pop_min()`. Automatically triggers phase transitions:
     - `ROLE_REVEAL_TIMEOUT` $\rightarrow$ begins clue round.
     - `TURN_TIMEOUT` $\rightarrow$ auto-skips AFK player and advances turn (bypassed when `turn_timer_seconds == 0` in Pass & Play).
     - `DISCUSSION_TIMEOUT` $\rightarrow$ transitions to voting phase.
     - `VOTING_TIMEOUT` $\rightarrow$ tallies votes and resolves round.

3. **`self._action_queue: Queue[Tuple[...]]`**:
   - `enqueue_action()`: places incoming client requests into the FIFO queue in $O(1)$ time and drains the queue sequentially to eliminate race conditions.

4. **`ChainedHashTable[str, GameEngine]` (`server/room_registry.py`)**:
   - Manages active game rooms keyed by 4-letter room code (e.g., `"ABCD"`).
   - `create_room()`: inserts new room mapping in $O(1)$ amortized time.
   - `get_room()`: resolves incoming client requests to their target `GameEngine` in $O(1)$ average lookup time.
   - `remove_room()`: cleans up room data in $O(1)$ average time when the host disconnects or session concludes.
   - `all_rooms()`: traverses hash buckets in $O(n + m)$ time for the server ticker loop.

5. **Milestone 6 (Pass & Play) DSA Utilization**:
   - **`CircularLinkedList` in Spoken Clues**: When `spoken_clues` is enabled, turn advancement is triggered by `end_turn(player_id)` instead of `submit_clue`. The engine advances `_turn_order.next()` in $O(1)$ time, logging `[spoken]` and maintaining cyclic turn order across rounds without string clue storage.
   - **`MinHeap` Zero-Timer Invariant**: In Pass & Play, `turn_timer_seconds` is set to `0` by default. The engine verifies `settings.turn_timer_seconds > 0` before inserting into `MinHeap`, eliminating timer overhead during oral clue-giving while still tracking discussion and voting timeouts when configured.

---

## 4. Verification & Test Suite

The repository includes comprehensive tests across `tests/test_structures.py`, `tests/test_protocol.py`, `tests/test_engine_flow.py`, `tests/test_supervisor.py`, and `tests/test_server_integration.py`:
- **Total Python Tests**: **55 passed** in 0.74s.
- **Coverage**:
  - Full happy path with 4 players and 2 clue rounds.
  - Spoken clues mode (`spoken_clues: true`, `end_turn`, rejection of typed clues).
  - Impostor steal-win via secret word guess (including case-insensitive and plural matching).
  - Plurality tie vote handling (no ejection, impostor team wins).
  - Innocent player ejection (impostor team wins).
  - 2-impostor flow with sequential catch and guess phase.
  - Player disconnect and token-based rejoining.
  - Out-of-turn actions, unauthorized commands, and wrong-phase operations.
  - Min-heap deadline expiry and AFK auto-skip.
  - Supervisor lifecycle: port binding, control channel token auth, clean teardown, and port release.
  - **Server Integration & Audit**:
    - Live WebSocket integration on ephemeral port with 4 simulated clients.
    - Host-disconnect room closure and broadcast.
    - Player rejoin after abrupt socket closure.
    - Rate limit and oversized frame rejection.
    - **Exhaustive Frame Audit**: Captures all outgoing frames to every client and confirms zero data leakage of impostor identity to crew or secret word to impostor.

