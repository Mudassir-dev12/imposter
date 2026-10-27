"""Custom Min-Heap (Priority Queue) implementation from scratch without heapq.

Used in the Impostor game engine to manage active timers (turn deadlines,
discussion timers, voting deadlines) keyed by expiry timestamp.

Complexity:
- push(key, value, item_id): O(log n) time, O(1) space
- pop_min(): O(log n) time, O(1) space
- peek(): O(1) time, O(1) space
- remove(item_id): O(log n) time, O(1) space (via index tracking)
- is_empty(): O(1) time, O(1) space
- __len__(): O(1) time, O(1) space
"""

from typing import Generic, TypeVar, Optional, Tuple, List, Dict

T = TypeVar("T")


class HeapNode(Generic[T]):
    """Internal heap node storing priority key, payload value, and optional identifier."""

    def __init__(self, key: float, value: T, item_id: Optional[str] = None) -> None:
        self.key: float = key
        self.value: T = value
        self.item_id: Optional[str] = item_id

    def __repr__(self) -> str:
        return f"HeapNode(key={self.key}, value={self.value!r}, id={self.item_id!r})"


class MinHeap(Generic[T]):
    """A binary min-heap supporting key-based priority and O(log n) removal by item_id.

    Maintains a 0-indexed binary tree stored as an array, where:
    - Parent of index i is (i - 1) // 2
    - Left child of index i is 2 * i + 1
    - Right child of index i is 2 * i + 2

    Maintains a dictionary mapping item_id -> index to achieve O(log n) arbitrary removals
    when timers are cancelled or refreshed.
    """

    def __init__(self) -> None:
        self._heap: List[HeapNode[T]] = []
        self._id_to_index: Dict[str, int] = {}

    def is_empty(self) -> bool:
        """Check if the heap has no elements.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return len(self._heap) == 0

    def __len__(self) -> int:
        """Return the number of elements in the heap.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return len(self._heap)

    def _swap(self, i: int, j: int) -> None:
        """Swap two nodes in the heap array and update their tracked indices.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        node_i = self._heap[i]
        node_j = self._heap[j]

        self._heap[i], self._heap[j] = node_j, node_i

        if node_i.item_id is not None:
            self._id_to_index[node_i.item_id] = j
        if node_j.item_id is not None:
            self._id_to_index[node_j.item_id] = i

    def _sift_up(self, index: int) -> None:
        """Move node at `index` up until the heap property is restored.

        Time Complexity: O(log n)
        Space Complexity: O(1)
        """
        curr = index
        while curr > 0:
            parent = (curr - 1) // 2
            if self._heap[curr].key < self._heap[parent].key:
                self._swap(curr, parent)
                curr = parent
            else:
                break

    def _sift_down(self, index: int) -> None:
        """Move node at `index` down until the heap property is restored.

        Time Complexity: O(log n)
        Space Complexity: O(1)
        """
        size = len(self._heap)
        curr = index

        while True:
            left = 2 * curr + 1
            right = 2 * curr + 2
            smallest = curr

            if left < size and self._heap[left].key < self._heap[smallest].key:
                smallest = left

            if right < size and self._heap[right].key < self._heap[smallest].key:
                smallest = right

            if smallest != curr:
                self._swap(curr, smallest)
                curr = smallest
            else:
                break

    def push(self, key: float, value: T, item_id: Optional[str] = None) -> None:
        """Insert a new element with a priority key and optional unique identifier.

        If `item_id` is provided and already exists in the heap, the existing entry
        is removed first before inserting the updated key/value.

        Time Complexity: O(log n)
        Space Complexity: O(1)
        """
        if item_id is not None and item_id in self._id_to_index:
            self.remove(item_id)

        node = HeapNode(key, value, item_id)
        index = len(self._heap)
        self._heap.append(node)
        if item_id is not None:
            self._id_to_index[item_id] = index

        self._sift_up(index)

    def peek(self) -> Tuple[float, T]:
        """Return the minimum element (key, value) without removing it.

        Raises:
            IndexError: If the heap is empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        if not self._heap:
            raise IndexError("peek from empty MinHeap")
        node = self._heap[0]
        return node.key, node.value

    def peek_node(self) -> HeapNode[T]:
        """Return the root HeapNode without removing it.

        Raises:
            IndexError: If the heap is empty.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        if not self._heap:
            raise IndexError("peek_node from empty MinHeap")
        return self._heap[0]

    def pop_min(self) -> Tuple[float, T]:
        """Remove and return the minimum element (key, value).

        Raises:
            IndexError: If the heap is empty.

        Time Complexity: O(log n)
        Space Complexity: O(1)
        """
        if not self._heap:
            raise IndexError("pop_min from empty MinHeap")

        root = self._heap[0]
        if root.item_id is not None:
            self._id_to_index.pop(root.item_id, None)

        last_node = self._heap.pop()

        if self._heap:
            self._heap[0] = last_node
            if last_node.item_id is not None:
                self._id_to_index[last_node.item_id] = 0
            self._sift_down(0)

        return root.key, root.value

    def remove(self, item_id: str) -> bool:
        """Remove an item identified by `item_id` in O(log n) time.

        Returns True if item was found and removed, False otherwise.

        Time Complexity: O(log n)
        Space Complexity: O(1)
        """
        index = self._id_to_index.get(item_id)
        if index is None:
            return False

        last_index = len(self._heap) - 1

        # If it's already the last element
        if index == last_index:
            self._id_to_index.pop(item_id, None)
            self._heap.pop()
            return True

        # Swap with last element, then pop last
        target_node = self._heap[index]
        self._swap(index, last_index)

        self._id_to_index.pop(item_id, None)
        self._heap.pop()

        # The element moved into `index` may need to sift down or sift up
        if index < len(self._heap):
            parent = (index - 1) // 2
            if index > 0 and self._heap[index].key < self._heap[parent].key:
                self._sift_up(index)
            else:
                self._sift_down(index)

        return True

    def contains_id(self, item_id: str) -> bool:
        """Check if an item with the given ID exists in the heap.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return item_id in self._id_to_index

    def clear(self) -> None:
        """Clear all elements from the heap.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        self._heap.clear()
        self._id_to_index.clear()
