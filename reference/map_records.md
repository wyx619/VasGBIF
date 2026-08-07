# Visualize refined records on interactive maps

Renders refined occurrence records on interactive maps for spatial
exploration and quality assessment. Records are deduplicated with
geohashes and color-coded by their native status.

## Usage

``` r
map_records(native_detected_coord = NA, precision = 3, cex = 3)
```

## Arguments

- native_detected_coord:

  A `nativeDetected` object returned by
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
  containing records with validated coordinates.

- precision:

  Positive integer controlling the spatial resolution of geohash-based
  deduplication. Higher values produce finer-grained cells. For
  reference, precision values of 4, 3, and 2 represent approximately 20
  km, 156 km, and 1,250 km resolution, respectively. Defaults to `3`.

- cex:

  Numeric value controlling the point size of occurrence records on the
  map. Defaults to `3`.

## Value

A `mapview` interactive map object displaying refined occurrence records
color-coded by `native_status`. The map contains a native-status legend,
three switchable basemap layers, and clickable popups with record
metadata.

## Details

The function works in four steps:

- **Record selection:** Reads the classified records from
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
  keeping those whose `native_status` is not `"unknown"`.

- **Geohash deduplication:** Encodes coordinates at the requested
  precision and retains one representative record per species, geohash
  cell, and native status.

- **Interactive visualization:** Builds a multi-layer map with records
  color-coded by `native_status`.

- **Basemap selection:** Provides OpenStreetMap, Esri World Imagery, and
  Stadia Stamen Watercolor basemaps.

### Record selection

Both the classification and the coordinates are read from
`native_detected_coord`, which carries every column of the input
records. Records with `native_status = "unknown"` are excluded. Records
with missing longitude or latitude are excluded as a guard;
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
only classifies records with validated coordinates, so none are
expected, and inputs that carry missing coordinates (such as the output
of
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md))
are rejected outright.

### Geohash deduplication

Geohash encoding converts latitude-longitude pairs into alphanumeric
strings representing grid cells of varying sizes. The function groups
records by species name, geohash cell, and native status, then retains
the first record from each group. This reduces visual overplotting while
preserving the broad spatial distribution pattern, which is useful for
densely sampled regions.

### Map layers and interactivity

The generated map includes:

- A color-coded legend based on `native_status` categories.

- Popups displaying record attributes such as GBIF ID, GBIF issues, and
  taxon name.

- Toggleable basemap layers for different visualization contexts.

- Point transparency set to `alpha.regions = 0.6` to improve density
  perception.

## See also

[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
for the object consumed by this function;
[`gh_encode()`](https://rdrr.io/pkg/geohashTools/man/gh_encode.html) for
geohash encoding and
[`mapView()`](https://r-spatial.github.io/mapview/reference/mapView.html)
for interactive map construction.

## Examples

``` r
if (FALSE) { # interactive() && exists("native_detected_coord")
map_records(
  native_detected_coord = native_detected_coord,
  precision = 3,
  cex = 3
)
}
```
