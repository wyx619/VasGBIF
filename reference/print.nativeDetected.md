# Print a `nativeDetected` object

Displays a compact summary of a native status classification: the number
of records, and the counts by `native_status` and by
`native_status_source`. The records themselves are not shown; use
[`head()`](https://rdrr.io/r/utils/head.html) or
[`View()`](https://rdrr.io/r/utils/View.html) to inspect them.

## Usage

``` r
# S3 method for class 'nativeDetected'
print(x, ...)
```

## Arguments

- x:

  An object of class `"nativeDetected"` returned by
  [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md).

- ...:

  Additional arguments (unused, retained for S3 compatibility).

## Value

Invisibly returns `x`.
