# set_threads rejects invalid inputs

    Code
      set_threads("2")
    Condition
      Error in `set_threads()`:
      ! input must be numeric

---

    Code
      set_threads(0)
    Condition
      Error in `set_threads()`:
      ! illegal !!!

---

    Code
      set_threads(total + 1)
    Condition
      Error in `set_threads()`:
      ! more than all available threads!

