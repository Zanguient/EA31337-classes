//+------------------------------------------------------------------+
//|                                                EA31337 framework |
//|                       Copyright 2016-2019, 31337 Investments Ltd |
//|                                       https://github.com/EA31337 |
//+------------------------------------------------------------------+

/*
 * This file is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

// Prevents processing this includes file for the second time.
#ifndef DICT_STRUCT_MQH
#define DICT_STRUCT_MQH

#include "DictBase.mqh"

// DictIterator could be used as DictStruct iterator.
#define DictStructIterator DictIteratorBase

/**
 * Hash-table based dictionary.
 */
template <typename K, typename V>
class DictStruct : public DictBase<K, V> {
 public:
  /**
   * Constructor. You may specifiy intial number of DictSlots that holds values or just leave it as it is.
   */
  DictStruct(unsigned int _initial_size = 0) {
    if (_initial_size > 0) {
      Resize(_initial_size);
    }
  }

  DictStructIterator<K, V> Begin() {
    // Searching for first item index.
    for (unsigned int i = 0; i < (unsigned int)ArraySize(_DictSlots_ref.DictSlots); ++i) {
      if (_DictSlots_ref.DictSlots[i].IsValid() && _DictSlots_ref.DictSlots[i].IsUsed()) {
        DictStructIterator<K, V> iter(this, i);
        return iter;
      }
    }
    // No items found.
    static DictStructIterator<K, V> invalid;
    return invalid;
  }

  /**
   * Inserts value using hashless key.
   */
  bool Push(V& value) {
    if (!InsertInto(_DictSlots_ref, value)) return false;

    ++_num_used;
    return true;
  }

  /**
   * Inserts or replaces value for a given key.
   */
  bool Set(K key, V& value) {
    if (!InsertInto(_DictSlots_ref, key, value)) return false;

    ++_num_used;
    return true;
  }

  V operator[](K key) {
    DictSlot<K, V>* slot;

    if (_mode == DictMode::LIST)
      slot = GetSlot((unsigned int)key);
    else
      slot = GetSlotByKey(key);

    if (slot == NULL || !slot.IsUsed()) {
      Alert("Invalid DictStruct key \"", key, "\" (called by [] operator). Returning empty structure.");
      static V _empty;
      return _empty;
    }

    return slot.value;
  }

  /**
   * Returns value for a given key.
   */
  V GetByKey(const K _key) {
    DictSlot<K, V>* slot = GetSlotByKey(_key);

    if (!slot) {
      Alert("Invalid DictStruct key \"", _key, "\" (called by GetByKey()). Returning empty structure.");
      static V _empty;
      return _empty;
    }

    return slot.value;
  }

  /**
   * Checks whether dictionary contains given key => value pair.
   */
  bool Contains(const K key, V& value) {
    DictSlot<K, V>* slot = GetSlotByKey(key);

    if (!slot) return false;

    return slot.value == value;
  }

 protected:
  /**
   * Inserts value into given array of DictSlots.
   */
  bool InsertInto(DictSlotsRef<K, V>& dictSlotsRef, const K key, V& value) {
    if (_mode == DictMode::UNKNOWN)
      _mode = DictMode::DICT;
    else if (_mode != DictMode::DICT) {
      Alert("Warning: Dict already operates as a dictionary, not a list!");
      return false;
    }

    if (_num_used == ArraySize(dictSlotsRef.DictSlots)) {
      // No DictSlots available, we need to expand array of DictSlots (by 25%).
      if (!Resize(MathMax(10, (int)((float)ArraySize(dictSlotsRef.DictSlots) * 1.25)))) return false;
    }

    unsigned int position = Hash(key) % ArraySize(dictSlotsRef.DictSlots);

    // Searching for empty DictSlot<K, V> or used one with the matching key. It skips used, hashless DictSlots.
    while (dictSlotsRef.DictSlots[position].IsUsed() &&
           (!dictSlotsRef.DictSlots[position].HasKey() || dictSlotsRef.DictSlots[position].key != key)) {
      // Position may overflow, so we will start from the beginning.
      position = (position + 1) % ArraySize(dictSlotsRef.DictSlots);
    }

    dictSlotsRef.DictSlots[position].key = key;
    dictSlotsRef.DictSlots[position].value = value;
    dictSlotsRef.DictSlots[position].SetFlags(DICT_SLOT_HAS_KEY | DICT_SLOT_IS_USED | DICT_SLOT_WAS_USED);
    return true;
  }

  /**
   * Inserts hashless value into given array of DictSlots.
   */
  bool InsertInto(DictSlotsRef<K, V>& dictSlotsRef, V& value) {
    if (_mode == DictMode::UNKNOWN)
      _mode = DictMode::LIST;
    else if (_mode != DictMode::LIST) {
      Alert("Warning: Dict already operates as a dictionary, not a list!");
      return false;
    }

    if (_num_used == ArraySize(dictSlotsRef.DictSlots)) {
      // No DictSlots available, we need to expand array of DictSlots (by 25%).
      if (!Resize(MathMax(10, (int)((float)ArraySize(dictSlotsRef.DictSlots) * 1.25)))) return false;
    }

    unsigned int position = Hash((unsigned int)dictSlotsRef._list_index) % ArraySize(dictSlotsRef.DictSlots);

    // Searching for empty DictSlot<K, V>.
    while (dictSlotsRef.DictSlots[position].IsUsed()) {
      // Position may overflow, so we will start from the beginning.
      position = (position + 1) % ArraySize(dictSlotsRef.DictSlots);
    }

    dictSlotsRef.DictSlots[position].value = value;
    dictSlotsRef.DictSlots[position].SetFlags(DICT_SLOT_IS_USED | DICT_SLOT_WAS_USED);

    ++dictSlotsRef._list_index;
    return true;
  }

  /**
   * Shrinks or expands array of DictSlots.
   */
  bool Resize(unsigned int new_size) {
    if (new_size < _num_used) {
      // We can't shrink to less than number of already used DictSlots.
      // It is okay to return true.
      return true;
    }

    DictSlotsRef<K, V> new_DictSlots;

    if (ArrayResize(new_DictSlots.DictSlots, new_size) == -1) return false;

    // Copies entire array of DictSlots into new array of DictSlots. Hashes will be rehashed.
    for (unsigned int i = 0; i < (unsigned int)ArraySize(_DictSlots_ref.DictSlots); ++i) {
      if (_DictSlots_ref.DictSlots[i].HasKey()) {
        if (!InsertInto(new_DictSlots, _DictSlots_ref.DictSlots[i].key, _DictSlots_ref.DictSlots[i].value))
          return false;
      } else {
        if (!InsertInto(new_DictSlots, _DictSlots_ref.DictSlots[i].value)) return false;
      }
    }
    // Freeing old DictSlots array.
    ArrayFree(_DictSlots_ref.DictSlots);

    _DictSlots_ref = new_DictSlots;

    return true;
  }
};

#endif