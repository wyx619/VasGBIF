# Print an `issue` object

Displays a compact summary of a GBIF issue parse: the number of records,
the number of recognised issue codes, the issues flagged on the most
records, and the distribution of per-record issue counts. The full
per-code table is available in the `summary` element; use
[`head()`](https://rdrr.io/r/utils/head.html) or
[`View()`](https://rdrr.io/r/utils/View.html) to inspect it.

## Usage

``` r
# S3 method for class 'issue'
print(x, ...)
```

## Arguments

- x:

  An object of class `"issue"` returned by
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md).

- ...:

  Additional arguments (unused, retained for S3 compatibility).

## Value

Invisibly returns `x`.
