"""Custom Chained Hash Table with dynamic resizing.

Used for the Room and Player registries in the Impostor server/engine.
Implements collision resolution via separate chaining and doubles capacity
when the load factor exceeds 0.75.

Complexity:
- put(key, value): Average O(1) time, Worst O(n) time, O(1) space amortized
- get(key, default): Average O(1) time, Worst O(n) time, O(1) space
- remove(key): Average O(1) time, Worst O(n) time, O(1) space
- contains(key): Average O(1) time, Worst O(n) time, O(1) space
- __len__(): O(1) time, O(1) space
- keys(), values(), items(): O(n + m) time where m is capacity, O(n) space
"""

from typing import Generic, TypeVar, Optional, Tuple, List, Iterator, Any

K = TypeVar("K")
V = TypeVar("V")


class HashEntry(Generic[K, V]):
    """Key-value entry stored within bucket chains."""

    def __init__(self, key: K, value: V) -> None:
        self.key: K = key
        self.value: V = value

    def __repr__(self) -> str:
        return f"HashEntry({self.key!r}: {self.value!r})"


class ChainedHashTable(Generic[K, V]):
    """A hash map implementation using separate chaining and dynamic rehashing."""

    INITIAL_CAPACITY: int = 16
    LOAD_FACTOR_THRESHOLD: float = 0.75

    def __init__(self, initial_capacity: int = INITIAL_CAPACITY) -> None:
        self._capacity: int = max(4, initial_capacity)
        self._size: int = 0
        self._buckets: List[List[HashEntry[K, V]]] = [[] for _ in range(self._capacity)]

    def _hash(self, key: K) -> int:
        """Compute bucket index for a given key.

        Time Complexity: O(k) where k is key length, effectively O(1) for strings/ints.
        Space Complexity: O(1)
        """
        return hash(key) % self._capacity

    def load_factor(self) -> float:
        """Return current load factor (size / capacity).

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size / self._capacity

    def _resize(self, new_capacity: int) -> None:
        """Resize bucket array and rehash all existing entries.

        Time Complexity: O(n + m) where n is size and m is capacity.
        Space Complexity: O(n + new_m)
        """
        old_buckets = self._buckets
        self._capacity = new_capacity
        self._buckets = [[] for _ in range(self._capacity)]
        self._size = 0

        for bucket in old_buckets:
            for entry in bucket:
                self.put(entry.key, entry.value)

    def put(self, key: K, value: V) -> None:
        """Insert or update a key-value pair.

        Resizes table if load factor exceeds LOAD_FACTOR_THRESHOLD (0.75).

        Time Complexity: Average O(1), Worst O(n)
        Space Complexity: O(1) amortized
        """
        index = self._hash(key)
        bucket = self._buckets[index]

        for entry in bucket:
            if entry.key == key:
                entry.value = value
                return

        bucket.append(HashEntry(key, value))
        self._size += 1

        if self.load_factor() > self.LOAD_FACTOR_THRESHOLD:
            self._resize(self._capacity * 2)

    def get(self, key: K, default: Optional[V] = None) -> Optional[V]:
        """Retrieve value for key, or return default if not found.

        Time Complexity: Average O(1), Worst O(n)
        Space Complexity: O(1)
        """
        index = self._hash(key)
        bucket = self._buckets[index]

        for entry in bucket:
            if entry.key == key:
                return entry.value

        return default

    def remove(self, key: K) -> bool:
        """Remove entry with given key. Returns True if found and removed, False otherwise.

        Time Complexity: Average O(1), Worst O(n)
        Space Complexity: O(1)
        """
        index = self._hash(key)
        bucket = self._buckets[index]

        for i, entry in enumerate(bucket):
            if entry.key == key:
                del bucket[i]
                self._size -= 1
                return True

        return False

    def contains(self, key: K) -> bool:
        """Check if key exists in hash table.

        Time Complexity: Average O(1), Worst O(n)
        Space Complexity: O(1)
        """
        index = self._hash(key)
        bucket = self._buckets[index]
        return any(entry.key == key for entry in bucket)

    def __getitem__(self, key: K) -> V:
        val = self.get(key)
        if val is None and not self.contains(key):
            raise KeyError(key)
        assert val is not None
        return val

    def __setitem__(self, key: K, value: V) -> None:
        self.put(key, value)

    def __delitem__(self, key: K) -> None:
        if not self.remove(key):
            raise KeyError(key)

    def __contains__(self, key: Any) -> bool:
        return self.contains(key)

    def __len__(self) -> int:
        """Return number of key-value pairs stored.

        Time Complexity: O(1)
        Space Complexity: O(1)
        """
        return self._size

    def keys(self) -> List[K]:
        """Return list of all keys.

        Time Complexity: O(n + m)
        Space Complexity: O(n)
        """
        result: List[K] = []
        for bucket in self._buckets:
            for entry in bucket:
                result.append(entry.key)
        return result

    def values(self) -> List[V]:
        """Return list of all values.

        Time Complexity: O(n + m)
        Space Complexity: O(n)
        """
        result: List[V] = []
        for bucket in self._buckets:
            for entry in bucket:
                result.append(entry.value)
        return result

    def items(self) -> List[Tuple[K, V]]:
        """Return list of (key, value) tuples.

        Time Complexity: O(n + m)
        Space Complexity: O(n)
        """
        result: List[Tuple[K, V]] = []
        for bucket in self._buckets:
            for entry in bucket:
                result.append((entry.key, entry.value))
        return result

    def clear(self) -> None:
        """Clear all entries and reset to initial capacity.

        Time Complexity: O(m)
        Space Complexity: O(1)
        """
        self._capacity = self.INITIAL_CAPACITY
        self._size = 0
        self._buckets = [[] for _ in range(self._capacity)]

    def __iter__(self) -> Iterator[K]:
        """Iterate over keys.

        Time Complexity: O(n + m)
        Space Complexity: O(1)
        """
        for bucket in self._buckets:
            for entry in bucket:
                yield entry.key

    def __repr__(self) -> str:
        items_str = ", ".join(f"{k!r}: {v!r}" for k, v in self.items())
        return f"ChainedHashTable({{{items_str}}})"
