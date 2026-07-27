# import_records rejects invalid paths

    Code
      import_records(path = 1)
    Condition
      Error in `import_records()`:
      ! set path to the downloaded SIMPLE_CSV zip!

---

    Code
      import_records(path = "")
    Condition
      Error in `import_records()`:
      ! require path to the downloaded SIMPLE_CSV zip!

---

    Code
      import_records(path = "records.csv")
    Condition
      Error in `import_records()`:
      ! should be the SIMPLE_CSV zip from GBIF!

