"""Word repository and selection logic for Impostor."""

import json
import os
import random
from typing import Dict, List, Optional, Tuple

DEFAULT_WORDS_PATH = os.path.join(os.path.dirname(__file__), "data", "words.json")


class WordRepository:
    """Manages word categories and provides deterministic or randomized word selection."""

    def __init__(self, data_path: Optional[str] = None, custom_words: Optional[Dict[str, List[str]]] = None) -> None:
        if custom_words is not None:
            self._categories = {k: list(v) for k, v in custom_words.items()}
        else:
            path = data_path or DEFAULT_WORDS_PATH
            with open(path, "r", encoding="utf-8") as f:
                self._categories = json.load(f)

        if not self._categories:
            raise ValueError("Word repository must contain at least one category.")

    def get_categories(self) -> List[str]:
        """Return a sorted list of all available category names."""
        return sorted(list(self._categories.keys()))

    def get_words(self, category: str) -> List[str]:
        """Return all words in the specified category (case-insensitive)."""
        cat_match = self._find_category_key(category)
        if not cat_match:
            raise KeyError(f"Category '{category}' not found.")
        return list(self._categories[cat_match])

    def _find_category_key(self, category_name: str) -> Optional[str]:
        """Case-insensitive category name resolver."""
        target = category_name.strip().lower()
        for k in self._categories.keys():
            if k.lower() == target:
                return k
        return None

    def pick_word(
        self,
        category: Optional[str] = None,
        rng: Optional[random.Random] = None,
    ) -> Tuple[str, str]:
        """Pick a secret word and return (category, word).

        If category is None or "random", picks an available category uniformly.
        Accepts an optional random.Random instance for deterministic test runs.
        """
        rand = rng if rng is not None else random

        if not category or category.strip().lower() == "random":
            chosen_cat_key = rand.choice(self.get_categories())
        else:
            cat_match = self._find_category_key(category)
            if not cat_match:
                raise KeyError(f"Category '{category}' not found.")
            chosen_cat_key = cat_match

        words = self._categories[chosen_cat_key]
        if not words:
            raise ValueError(f"Category '{chosen_cat_key}' has no words.")

        chosen_word = rand.choice(words)
        return chosen_cat_key, chosen_word
