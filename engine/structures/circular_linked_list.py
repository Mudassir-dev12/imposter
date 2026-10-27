"""Custom Circular Doubly-Linked List for seat order and clue-turn rotation.

This data structure is designed specifically for turn-based round-robin mechanics
in the Impostor game engine. Players sit in a circular arrangement, and clue turns
cycle continuously until all rounds are concluded.

Complexity:
- append(value): O(1) time, O(1) space
- prepend(value): O(1) time, O(1) space
- remove(value): O(n) search time, O(1) pointer updates, O(1) space
- next(): O(1) time, O(1) space
- peek(): O(1) time, O(1) space
- set_current(value): O(n) search time, O(1) space
- to_list(): O(n) time, O(n) space
- contains(value): O(n) time, O(1) space
- is_empty(): O(1) time, O(1) space
- __len__(): O(1) time, O(1) space
"""

from typing import Generic, TypeVar, Optional, Iterator, List

T = TypeVar("T")


class Node(Generic[T]):
    """Internal doubly-linked node."""

    def __init__(self, value: T) -> None:
        self.value: T = value
        self.next: Optional[Node[T]] = None
        self.prev: Optional[Node[T]] = None


class CircularLinkedList(Generic[T]):
    """A circular doubly-linked list with an active iteration cursor (`current`).

    Maintains `head`, `tail`, and a `current` turn pointer.
    Supports safe deletion while iterating: if the node currently pointed to by
    `current` is removed (e.g. a player disconnects on their turn), `current`
    automatically advances to the next player.
    """

    def __init__(self) -> None:
        self._head: Optional[Node[T]] = None
        self._current: Optional[Node[T]] = None
        self._size: int = 0

    @property
    def head_value(self) -> Optional[T]:
        """Return the head value, or None if empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._head.value if self._head else None

    @property
    def current_value(self) -> Optional[T]:
        """Return the current cursor value, or None if empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._current.value if self._current else None

    def is_empty(self) -> bool:
        """Check if the circular list contains no elements.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size == 0

    def __len__(self) -> int:
        """Return the number of elements in the list.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size

    def append(self, value: T) -> None:
        """Insert an element at the end of the circular list (after tail).

        If the list is empty, the new node becomes head, tail, and current.
        In circular structure, tail.next points to head, and head.prev points to tail.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        new_node = Node(value)
        if self._head is None:
            new_node.next = new_node
            new_node.prev = new_node
            self._head = new_node
            self._current = new_node
        else:
            tail = self._head.prev
            assert tail is not None
            tail.next = new_node
            new_node.prev = tail
            new_node.next = self._head
            self._head.prev = new_node

        self._size += 1

    def prepend(self, value: T) -> None:
        """Insert an element at the start of the circular list (new head).

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        self.append(value)
        # The newly appended node is at tail = head.prev; shift head to it
        assert self._head is not None and self._head.prev is not None
        self._head = self._head.prev

    def remove(self, value: T) -> bool:
        """Remove the first occurrence of value from the circular list.

        Handles:
        - Empty list
        - Single element list
        - Removal of head node
        - Removal of tail node
        - Removal of current cursor node (safely advances current to next node)

        Returns True if the value was found and removed, False otherwise.

        Time Complexity: O(n) search, O(1) pointer manipulation
        Space Complexity: O(1)
        """
        if self._head is None:
            return False

        target_node: Optional[Node[T]] = None
        curr = self._head
        for _ in range(self._size):
            if curr.value == value:
                target_node = curr
                break
            assert curr.next is not None
            curr = curr.next

        if target_node is None:
            return False

        # If list has only 1 element
        if self._size == 1:
            self._head = None
            self._current = None
            self._size = 0
            return True

        # If removing the node pointed to by current cursor, advance cursor first
        if self._current is target_node:
            self._current = target_node.next

        # If removing head, advance head
        if self._head is target_node:
            self._head = target_node.next

        # Unlink target_node
        prev_node = target_node.prev
        next_node = target_node.next
        assert prev_node is not None and next_node is not None
        prev_node.next = next_node
        next_node.prev = prev_node

        # Clean references on removed node
        target_node.next = None
        target_node.prev = None
        self._size -= 1
        return True

    def peek(self) -> T:
        """Return the value at the current cursor without advancing.

        Raises:
            IndexError: If the list is empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        if self._current is None:
            raise IndexError("peek from empty CircularLinkedList")
        return self._current.value

    def next(self) -> T:
        """Advance the current cursor to the next node and return its value.

        Raises:
            IndexError: If the list is empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        if self._current is None or self._current.next is None:
            raise IndexError("next from empty CircularLinkedList")
        self._current = self._current.next
        return self._current.value

    def reset_cursor(self) -> None:
        """Reset the current cursor back to the head node.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        self._current = self._head

    def set_current(self, value: T) -> bool:
        """Set the current cursor to the node containing the given value.

        Returns True if value was found and current was updated, False otherwise.

        Time Complexity: O(n)
        Space Complexity: O(1)
        """
        if self._head is None:
            return False

        curr = self._head
        for _ in range(self._size):
            if curr.value == value:
                self._current = curr
                return True
            assert curr.next is not None
            curr = curr.next
        return False

    def contains(self, value: T) -> bool:
        """Check if a value exists in the list.

        Time Complexity: O(n)
        Space Complexity: O(1)
        """
        if self._head is None:
            return False

        curr = self._head
        for _ in range(self._size):
            if curr.value == value:
                return True
            assert curr.next is not None
            curr = curr.next
        return False

    def to_list(self) -> List[T]:
        """Return a Python list of elements starting from head.

        Time Complexity: O(n)
        Space Complexity: O(n)
        """
        result: List[T] = []
        if self._head is None:
            return result

        curr = self._head
        for _ in range(self._size):
            result.append(curr.value)
            assert curr.next is not None
            curr = curr.next
        return result

    def clear(self) -> None:
        """Remove all elements from the list.

        Time Complexity: O(1) (Python GC handles unlinked nodes)
        Space Complexity: O(1)
        """
        self._head = None
        self._current = None
        self._size = 0

    def __iter__(self) -> Iterator[T]:
        """Iterate over all elements once, starting from head.

        Time Complexity: O(n)
        Space Complexity: O(1)
        """
        if self._head is None:
            return
        curr = self._head
        for _ in range(self._size):
            yield curr.value
            assert curr.next is not None
            curr = curr.next

    def __repr__(self) -> str:
        items = " -> ".join(str(x) for x in self.to_list())
        return f"CircularLinkedList([{items}], size={self._size})"
