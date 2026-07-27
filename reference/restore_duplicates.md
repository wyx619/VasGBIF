# Restore missing metadata from duplicate records

Internal helper that fills missing metadata fields in usable voucher
records using values from their associated duplicate records that share
the same collection event key.

## Usage

``` r
restore_duplicates(occ_digital_voucher = NULL)
```

## Arguments

- occ_digital_voucher:

  A `data.table` of digital voucher records, as produced by internal
  vouchering steps. Must contain the columns listed in `fields_to_parse`
  as well as `VasGBIF_dataset_result` and `collection_key`.

## Value

A `data.table` containing only the usable records, with missing metadata
fields filled from duplicates where possible and a logical flag
`VasGBIF_restored_from_duplicate` indicating whether restoration
occurred for each row.

## Details

The function operates on two subsets of the input: records marked
`"usable"` and those marked `"duplicate"`. For each metadata field
listed in `fields_to_merge` (`eventDate`, `year`, `month`, `day`,
`identifiedBy`, `countryCode`, `stateProvince`, `locality`), it:

- Identifies usable records whose value for that field is missing,
  empty, or `"NA"`.

- Searches the duplicate records with the same `collection_key` for a
  non-missing candidate value of reasonable length (no more than 10,000
  characters).

- Copies the first valid candidate into the usable record and sets
  `VasGBIF_restored_from_duplicate = TRUE`.

The `year` field receives special treatment: after cleaning, the
candidate text is coerced to integer.

Only the usable records (with restored fields) are returned.
