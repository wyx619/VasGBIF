# Print a `CoordinateRefined` object

Displays a compact summary of a coordinate-refinement result: the number
of records in each output table and the elapsed runtime. The records
themselves are not shown; use
[`head()`](https://rdrr.io/r/utils/head.html) or
[`View()`](https://rdrr.io/r/utils/View.html) to inspect them.

## Usage

``` r
# S3 method for class 'CoordinateRefined'
print(x, ...)
```

## Arguments

- x:

  An object of class `"CoordinateRefined"` returned by
  [`clean_coordinates()`](https://wyx619.github.io/VasGBIF/reference/clean_coordinates.md).

- ...:

  Additional arguments (unused, retained for S3 compatibility).

## Value

Invisibly returns `x`.
