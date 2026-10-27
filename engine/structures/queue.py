"""Custom Linked-List FIFO Queue for incoming message processing.

Used in the Impostor game engine and server to queue incoming player actions
and messages per room, ensuring strictly ordered, race-free processing.

Complexity:
- enqueue(item): O(1) time, O(1) space
- dequeue(): O(1) time, O(1) space
- peek(): O(1) time, O(1) space
- is_empty(): O(1) time, O(1) space
- size(): O(1) time, O(1) space
- __len__(): O(1) time, O(1) space
- to_list(): O(n) time, O(n) space
"""

from typing import Generic, TypeVar, Optional, List, Iterator

T = TypeVar("T")


class QueueNode(Generic[T]):
    """Internal singly-linked node for the queue."""

    def __init__(self, value: T) -> None:
        self.value: T = value
        self.next: Optional[QueueNode[T]] = None


class Queue(Generic[T]):
    """A FIFO (First-In, First-Out) Queue implemented with a singly linked list.

    Maintains pointers to both `_head` (for O(1) dequeue) and `_tail` (for O(1) enqueue),
    as well as an atomic size counter.
    """

    def __init__(self) -> None:
        self._head: Optional[QueueNode[T]] = None
        self._tail: Optional[QueueNode[T]] = None
        self._size: int = 0

    def is_empty(self) -> bool:
        """Check if the queue contains no elements.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size == 0

    def size(self) -> int:
        """Return the current number of elements in the queue.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size

    def __len__(self) -> int:
        """Return the current number of elements in the queue.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size

    def enqueue(self, item: T) -> None:
        """Add an item to the rear (tail) of the queue.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        new_node = QueueNode(item)
        if self._tail is None:
            self._head = new_node
            self._tail = new_node
        else:
            self._tail.next = new_node
            self._tail = new_node
        self._size += 1

    def dequeue(self) -> T:
        """Remove and return the item from the front (head) of the queue.

        Raises:
            IndexError: If the queue is empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        if self._head is None:
            raise IndexError("dequeue from empty Queue")

        removed_node = self._head
        self._head = self._head.next
        if self._head is None:
            self._tail = None

        self._size -= 1
        return removed_node.value

    def peek(self) -> T:
        """Return the item at the front of the queue without removing it.

        Raises:
            IndexError: If the queue is empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        if self._head is None:
            raise IndexError("peek from empty Queue")
        return self._head.value

    def clear(self) -> None:
        """Remove all items from the queue.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        self._head = None
        self._tail = None
        self._size = 0

    def to_list(self) -> List[T]:
        """Convert queue elements from front to rear into a Python list.

        Time Complexity: O(n)
        Space Complexity: O(n)
        """
        result: List[T] = []
        curr = self._head
        while curr is not None:
            result.append(curr.value)
            curr = curr.next
        return result

    def __iter__(self) -> Iterator[T]:
        """Iterate over items from front to rear.

        Time Complexity: O(n)
        Space Complexity: O(1)
        """
        curr = self._head
        while curr is not None:
            yield curr.value
            curr = curr.next

    def __repr__(self) -> str:
        return f"Queue({self.to_list()!r})"
