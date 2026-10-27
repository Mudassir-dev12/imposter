"""Unit tests for custom data structures in engine/structures."""

import pytest
from engine.structures.circular_linked_list import CircularLinkedList
from engine.structures.min_heap import MinHeap
from engine.structures.queue import Queue
from engine.structures.hash_table import ChainedHashTable


# ============================================================================
# CircularLinkedList Tests
# ============================================================================

def test_circular_linked_list_empty():
    cll = CircularLinkedList[str]()
    assert len(cll) == 0
    assert cll.is_empty()
    assert cll.head_value is None
    assert cll.current_value is None
    assert cll.to_list() == []
    assert not cll.contains("Alice")
    assert not cll.remove("Alice")

    with pytest.raises(IndexError):
        cll.peek()

    with pytest.raises(IndexError):
        cll.next()


def test_circular_linked_list_single_element():
    cll = CircularLinkedList[str]()
    cll.append("Alice")

    assert len(cll) == 1
    assert not cll.is_empty()
    assert cll.head_value == "Alice"
    assert cll.current_value == "Alice"
    assert cll.peek() == "Alice"

    # In a circular list of 1 element, advancing next() stays on Alice
    assert cll.next() == "Alice"
    assert cll.next() == "Alice"
    assert cll.to_list() == ["Alice"]
    assert cll.contains("Alice")

    # Remove the single element
    assert cll.remove("Alice")
    assert len(cll) == 0
    assert cll.is_empty()
    assert cll.head_value is None
    assert cll.current_value is None
    assert cll.to_list() == []


def test_circular_linked_list_append_and_cycle():
    cll = CircularLinkedList[str]()
    for name in ["Alice", "Bob", "Charlie"]:
        cll.append(name)

    assert len(cll) == 3
    assert cll.to_list() == ["Alice", "Bob", "Charlie"]
    assert cll.peek() == "Alice"

    # Advance through circular turns
    assert cll.next() == "Bob"
    assert cll.next() == "Charlie"
    assert cll.next() == "Alice"  # Wraps around
    assert cll.next() == "Bob"

    # Reset cursor
    cll.reset_cursor()
    assert cll.peek() == "Alice"


def test_circular_linked_list_prepend():
    cll = CircularLinkedList[int]()
    cll.append(2)
    cll.append(3)
    cll.prepend(1)

    assert cll.to_list() == [1, 2, 3]
    assert cll.head_value == 1
    assert len(cll) == 3


def test_circular_linked_list_remove_head():
    cll = CircularLinkedList[str]()
    for name in ["Alice", "Bob", "Charlie"]:
        cll.append(name)

    assert cll.remove("Alice")
    assert len(cll) == 2
    assert cll.head_value == "Bob"
    assert cll.to_list() == ["Bob", "Charlie"]

    # Traversal still circular
    assert cll.peek() == "Bob"
    assert cll.next() == "Charlie"
    assert cll.next() == "Bob"


def test_circular_linked_list_remove_tail():
    cll = CircularLinkedList[str]()
    for name in ["Alice", "Bob", "Charlie"]:
        cll.append(name)

    assert cll.remove("Charlie")
    assert len(cll) == 2
    assert cll.to_list() == ["Alice", "Bob"]
    assert cll.next() == "Bob"
    assert cll.next() == "Alice"


def test_circular_linked_list_remove_middle():
    cll = CircularLinkedList[str]()
    for name in ["Alice", "Bob", "Charlie", "David"]:
        cll.append(name)

    assert cll.remove("Bob")
    assert len(cll) == 3
    assert cll.to_list() == ["Alice", "Charlie", "David"]


def test_circular_linked_list_remove_while_iterating():
    """Critical game scenario: player disconnects or leaves on their turn."""
    cll = CircularLinkedList[str]()
    for name in ["Alice", "Bob", "Charlie", "David"]:
        cll.append(name)

    # Current is Alice; advance to Bob
    assert cll.next() == "Bob"
    assert cll.current_value == "Bob"

    # Bob disconnects during Bob's turn!
    assert cll.remove("Bob")
    assert len(cll) == 3

    # Cursor should have safely advanced to Charlie
    assert cll.current_value == "Charlie"
    assert cll.peek() == "Charlie"

    # Next player in rotation is David
    assert cll.next() == "David"
    assert cll.next() == "Alice"
    assert cll.next() == "Charlie"


def test_circular_linked_list_set_current():
    cll = CircularLinkedList[str]()
    for name in ["Alice", "Bob", "Charlie"]:
        cll.append(name)

    assert cll.set_current("Charlie")
    assert cll.peek() == "Charlie"
    assert cll.next() == "Alice"
    assert not cll.set_current("Unknown")


def test_circular_linked_list_iteration_and_clear():
    cll = CircularLinkedList[int]()
    for i in range(5):
        cll.append(i)

    # Iteration yields each element once
    assert list(cll) == [0, 1, 2, 3, 4]

    cll.clear()
    assert len(cll) == 0
    assert cll.is_empty()
    assert cll.to_list() == []


# ============================================================================
# MinHeap Tests
# ============================================================================

def test_min_heap_empty():
    heap = MinHeap[str]()
    assert len(heap) == 0
    assert heap.is_empty()
    assert not heap.contains_id("timer1")
    assert not heap.remove("timer1")

    with pytest.raises(IndexError):
        heap.peek()

    with pytest.raises(IndexError):
        heap.pop_min()


def test_min_heap_single_element():
    heap = MinHeap[str]()
    heap.push(10.5, "turn_timeout", item_id="timer_turn")

    assert len(heap) == 1
    assert not heap.is_empty()
    assert heap.contains_id("timer_turn")
    assert heap.peek() == (10.5, "turn_timeout")

    key, val = heap.pop_min()
    assert key == 10.5
    assert val == "turn_timeout"
    assert len(heap) == 0
    assert not heap.contains_id("timer_turn")


def test_min_heap_ordering():
    heap = MinHeap[str]()
    entries = [(50.0, "e"), (10.0, "a"), (30.0, "c"), (20.0, "b"), (40.0, "d")]
    for key, val in entries:
        heap.push(key, val)

    assert len(heap) == 5
    result = []
    while not heap.is_empty():
        result.append(heap.pop_min())

    expected = [(10.0, "a"), (20.0, "b"), (30.0, "c"), (40.0, "d"), (50.0, "e")]
    assert result == expected


def test_min_heap_remove_by_id():
    heap = MinHeap[str]()
    heap.push(10.0, "t1", item_id="id1")
    heap.push(20.0, "t2", item_id="id2")
    heap.push(30.0, "t3", item_id="id3")
    heap.push(40.0, "t4", item_id="id4")
    heap.push(5.0, "t0", item_id="id0")

    # Remove root node (id0 with key 5.0)
    assert heap.remove("id0")
    assert len(heap) == 4
    assert heap.peek()[0] == 10.0

    # Remove internal node (id3 with key 30.0)
    assert heap.remove("id3")
    assert len(heap) == 3

    # Remove last node
    assert heap.remove("id4")
    assert len(heap) == 2

    # Remove non-existent
    assert not heap.remove("non_existent")

    # Verify remaining elements maintain min-heap ordering
    assert heap.pop_min() == (10.0, "t1")
    assert heap.pop_min() == (20.0, "t2")
    assert heap.is_empty()


def test_min_heap_update_existing_id():
    heap = MinHeap[str]()
    heap.push(50.0, "turn", item_id="active_timer")
    assert heap.peek() == (50.0, "turn")

    # Updating with smaller key
    heap.push(10.0, "turn_fast", item_id="active_timer")
    assert len(heap) == 1
    assert heap.peek() == (10.0, "turn_fast")


def test_min_heap_clear():
    heap = MinHeap[str]()
    heap.push(1.0, "a", "id_a")
    heap.push(2.0, "b", "id_b")
    heap.clear()

    assert len(heap) == 0
    assert heap.is_empty()
    assert not heap.contains_id("id_a")


# ============================================================================
# Queue Tests
# ============================================================================

def test_queue_empty():
    q = Queue[str]()
    assert q.is_empty()
    assert q.size() == 0
    assert len(q) == 0
    assert q.to_list() == []

    with pytest.raises(IndexError):
        q.peek()

    with pytest.raises(IndexError):
        q.dequeue()


def test_queue_enqueue_dequeue_fifo():
    q = Queue[int]()
    for i in range(1, 4):
        q.enqueue(i)

    assert q.size() == 3
    assert not q.is_empty()
    assert q.peek() == 1
    assert q.to_list() == [1, 2, 3]

    assert q.dequeue() == 1
    assert q.dequeue() == 2
    assert q.dequeue() == 3

    assert q.is_empty()
    assert q.size() == 0


def test_queue_interleaved():
    q = Queue[str]()
    q.enqueue("msg1")
    q.enqueue("msg2")
    assert q.dequeue() == "msg1"

    q.enqueue("msg3")
    assert q.peek() == "msg2"
    assert q.dequeue() == "msg2"
    assert q.dequeue() == "msg3"
    assert q.is_empty()


def test_queue_iteration_and_clear():
    q = Queue[str]()
    items = ["a", "b", "c"]
    for it in items:
        q.enqueue(it)

    assert list(q) == items
    q.clear()
    assert q.is_empty()
    assert q.size() == 0


# ============================================================================
# ChainedHashTable Tests
# ============================================================================

def test_hash_table_empty():
    ht = ChainedHashTable[str, int]()
    assert len(ht) == 0
    assert ht.get("key") is None
    assert ht.get("key", default=42) == 42
    assert not ht.contains("key")
    assert "key" not in ht
    assert not ht.remove("key")

    with pytest.raises(KeyError):
        _ = ht["key"]


def test_hash_table_put_get():
    ht = ChainedHashTable[str, str]()
    ht.put("ROOM_ABCD", "RoomState1")
    ht["ROOM_WXYZ"] = "RoomState2"

    assert len(ht) == 2
    assert ht.get("ROOM_ABCD") == "RoomState1"
    assert ht["ROOM_WXYZ"] == "RoomState2"
    assert "ROOM_ABCD" in ht
    assert ht.contains("ROOM_WXYZ")

    # Overwrite existing key
    ht["ROOM_ABCD"] = "RoomState1_Updated"
    assert len(ht) == 2
    assert ht["ROOM_ABCD"] == "RoomState1_Updated"


def test_hash_table_deletion():
    ht = ChainedHashTable[str, int]()
    ht["p1"] = 100
    ht["p2"] = 200

    assert ht.remove("p1")
    assert len(ht) == 1
    assert "p1" not in ht
    assert ht["p2"] == 200

    # __delitem__
    del ht["p2"]
    assert len(ht) == 0
    assert not ht.remove("p2")

    with pytest.raises(KeyError):
        del ht["p2"]


def test_hash_table_dynamic_resizing():
    ht = ChainedHashTable[int, str](initial_capacity=4)
    # Insert 20 items to force multiple rehash resizes
    for i in range(20):
        ht[i] = f"val_{i}"

    assert len(ht) == 20
    for i in range(20):
        assert ht[i] == f"val_{i}"

    assert len(ht.keys()) == 20
    assert len(ht.values()) == 20
    assert len(ht.items()) == 20


def test_hash_table_clear_and_iteration():
    ht = ChainedHashTable[str, int]()
    data = {"a": 1, "b": 2, "c": 3}
    for k, v in data.items():
        ht[k] = v

    assert sorted(list(ht)) == ["a", "b", "c"]
    ht.clear()
    assert len(ht) == 0
    assert ht.keys() == []
