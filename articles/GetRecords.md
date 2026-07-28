# GetRecords

## Search and Download Occurrence Records from GBIF

This vignette demonstrates how to programmatically search for and
download biodiversity occurrence records from the Global Biodiversity
Information Facility (GBIF) using the **rgbif** package (Chamberlain et
al. 2025), and how to import the downloaded GBIF file into **VasGBIF**
for downstream processing. All examples use the plant genus *Saxifraga*.

The workflow consists of three steps:

| Step | What | Requires password? |
|----|----|----|
| **1.** Account setup & package loading | Register a GBIF account and load required packages | Yes |
| **2.** Search & submit a download request | Use `rgbif` to find a taxon key and submit a download job | Yes |
| **3.** Download & import into VasGBIF | Retrieve the ZIP and feed it to [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md) | Only Path A (new request) |

Step 2 is the only place where your GBIF credentials are needed. If you
already possess a download key or DOI from a previous download, you can
skip directly to Step 3.

## Account Setup & Package Loading

### Registering a GBIF account

If you do not have a GBIF account, register at
<https://www.gbif.org/user/register>. You will need the credentials to
submit a new download request in Step 2.

### Loading the required packages

``` r

library(rgbif)
library(VasGBIF)
library(dplyr)
library(data.table)
```

### Setting your GBIF credentials

For this tutorial we set the credentials as plain R variables. The
password is only required in Step 2 when you submit a **new** download
request — it is not needed for downloading an existing download.

``` r

user  <- "your_username"
pwd   <- "your_password"
email <- "your_email@example.com"
```

> The user—pwd—email triplet is the **only** information that must be
> kept private. Never commit these values to a public repository.

## Searching & Submitting a Download Request

This step is needed when you are starting from scratch — you do not yet
have a download key or DOI for your taxon of interest. If you already
have a DOI or download key, skip to Step 3.

### Finding the taxon key

GBIF identifies taxa with integer keys. Use
[`rgbif::name_backbone()`](https://docs.ropensci.org/rgbif/reference/name_backbone.html)
to look up the key for your target taxon:

``` r

genus <- "Saxifraga"
gbif_key <- name_backbone(genus, rank = "genus")
cat(paste(genus,":",gbif_key$usageKey))
```

    ## Saxifraga : 2987833

### Building predicates

The
[`pred()`](https://docs.ropensci.org/rgbif/reference/download_predicate_dsl.html)
family of functions lets you construct GBIF download queries. Common
predicates include:

| Function | Meaning | Example |
|----|----|----|
| `pred("taxonKey", key)` | Match a taxon | `pred("taxonKey", gbif_key$usageKey)` |
| `pred("basisOfRecord", "PRESERVED_SPECIMEN")` | Filter by basis of record | Only physical specimens |
| `pred("hasCoordinate", TRUE)` | Require coordinates | Exclude non-georeferenced records |
| `pred("occurrenceStatus", "PRESENT")` | Exclude absence records | Only presence data |

Combine them inside
[`occ_download()`](https://docs.ropensci.org/rgbif/reference/occ_download.html)
or with
[`pred_and()`](https://docs.ropensci.org/rgbif/reference/download_predicate_dsl.html)
/
[`pred_or()`](https://docs.ropensci.org/rgbif/reference/download_predicate_dsl.html):

``` r

pred_and(
  pred("taxonKey", gbif_key$usageKey),
  pred("basisOfRecord", "PRESERVED_SPECIMEN"),
  pred("hasCoordinate", TRUE)
)
```

### Submitting the request

Pass the predicates to
[`occ_download()`](https://docs.ropensci.org/rgbif/reference/occ_download.html)
together with your credentials:

``` r

download <- occ_download(
  pred("taxonKey", gbif_key$usageKey),
  pred("basisOfRecord", "PRESERVED_SPECIMEN"),
  pred("hasCoordinate", TRUE),
  pred("occurrenceStatus", "PRESENT"),
  user  = user,
  pwd   = pwd,
  email = email,
  format = 'SIMPLE_CSV'
)

download_key <- download$key
print(download_key)## Building predicates
```

The
[`pred()`](https://docs.ropensci.org/rgbif/reference/download_predicate_dsl.html)
family of functions lets you construct GBIF download queries. For a
complete reference, see

``` r

?rgbif::pred 
```

in R or the online documentation at
<https://docs.ropensci.org/rgbif/reference/download_predicate_dsl.html>.

### On limiting to preserved specimens

In this manual, we restrict the download to `PRESERVED_SPECIMEN`
**solely for practical reasons** — it keeps the download size manageable
for a demonstration. This is not a limitation of VasGBIF. VasGBIF is
able to process occurrence records of **all basis-of-record types** for
vascular plants, including but not limited to:

- `PRESERVED_SPECIMEN` — a physical specimen stored in a collection
- `HUMAN_OBSERVATION` — a record of an organism observed in the field
- `OBSERVATION` — a generic observation record
- `MACHINE_OBSERVATION` — an observation made by an automated device
- `MATERIAL_SAMPLE` — a physical sample (e.g., tissue, DNA)
- `LIVING_SPECIMEN` — a living organism maintained in cultivation or
  captivity
- `FOSSIL_SPECIMEN` — a fossilised specimen

For the full controlled vocabulary, see the Darwin Core term definition
at <http://rs.tdwg.org/dwc/terms/basisOfRecord> and the GBIF data-use
guide at
<https://docs.gbif.org/course-data-use/en/basis-of-record.html>.

### Waiting for completion

GBIF processes downloads asynchronously. Use
[`occ_download_wait()`](https://docs.ropensci.org/rgbif/reference/occ_download_wait.html)
to block until the job finishes:

``` r

occ_download_wait(download_key)
```

You can inspect the download metadata at any time — the response
includes the download status, record count, and a DOI:

``` r

meta <- occ_download_meta(download_key)
print(meta$status)  # "SUCCEEDED"
print(meta$doi)      # e.g. "10.15468/dl.xxxxx"## Web download (recommended for very large datasets)
```

For downloads with lots of records (\> 50 MB ZIP),
[`occ_download_get()`](https://docs.ropensci.org/rgbif/reference/occ_download_get.html)
can be slow because it downloads through R’s HTTP client. A much faster
alternative is to use the DOI link — which you can obtain from the
previous step via `meta$doi` after calling
`occ_download_meta(download_key)` — and download manually:

1.  Open the DOI link (e.g. <https://doi.org/10.15468/dl.4ty3ap>) in
    your browser.
2.  Click the **Download archive** button and fetch the ZIP file.
3.  Use a download manager (IDM, aria2, `wget`, `curl`) to.
4.  Point
    [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
    to the downloaded file.

gbif_file \<- “path/to/your/downloaded_file.zip”

## Downloading & Importing into VasGBIF

Once the download has succeeded (or if you already have a key or DOI),
you can retrieve the ZIP archive and import it into VasGBIF. This step
does **not** require your GBIF password.

### Download with rgbif (still in R)

Three entry points lead to the same result:

| Path | Starting point | Code | Need Authentication? |
|----|----|----|----|
| **A** (from Step 2) | `download_key` | `occ_download_get(download_key, path)` | No |
| **B** (from DOI) | `"10.15468/dl.xxxxx"` | `occ_download_doi(DOI)$key %>% occ_download_get(path)` | No |
| **C** (known key) | `"0021523-250402121839773"` | `occ_download_get(key, path)` | No |

Here we demonstrate Path B — downloading by DOI — which is the most
portable approach for sharing reproducible workflows:

``` r

library(rgbif)
library(dplyr)

DOI <- "10.15468/dl.4ty3ap"
gbif_file <- occ_download_doi(DOI)$key |>
  occ_download_get(path = tempdir()) |>
  as.character()
```

> **Path A reminder:** If you follow this vignette sequentially and
> completed Step 2, replace the DOI line with
> `occ_download_get(download_key, path = tempdir()) %>% as.character()`.

### Web download (recommended for very large datasets)

For downloads with lots of records (\> 50 MB ZIP),
[`occ_download_get()`](https://docs.ropensci.org/rgbif/reference/occ_download_get.html)
can be slow because it downloads through R’s HTTP client. A much faster
alternative is to:

1.  Open the DOI link (e.g. <https://doi.org/10.15468/dl.4ty3ap>) in
    your browser.
2.  Click the **Download archive** button to get the direct ZIP URL.
3.  Use a download manager (IDM, aria2, `wget`, `curl`) to fetch the
    ZIP.
4.  Point
    [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
    to the downloaded file.

``` r

gbif_file <- "path/to/your/downloaded_file.zip"
```

### Importing with VasGBIF

Feed the ZIP path to
[`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md).
The function reads the Darwin Core Archive, selects the fields required
by VasGBIF, and parses GBIF issue flags into record-level logical
indicators.

``` r

library(VasGBIF)
library(data.table)

occ_import <- import_records(path = gbif_file)
```

The returned `import` object is a list of class `"import"` with four
elements:

- **`occ`** — the occurrence records (`data.table`) with core GBIF
  fields
- **`occ_issue`** — a binary matrix of GBIF issue flags per record
- **`summary`** — frequency table of detected issues (sorted by
  decreasing count)
- **`runtime`** — elapsed import time

For the *Saxifraga* example used here, this imports tens of thousands of
records spanning over a thousand unique scientific names — ready for
downstream processing.

### Next steps

The `import` object is the entry point to the full VasGBIF pipeline.
Continue with:

- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  to resolve names against WCVP via TNRS
- [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md)
  and
  [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md)
  for duplicate detection
- [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
  for coordinate validation and native-status annotation

See the **Example** vignette
([`vignette("Example", package = "VasGBIF")`](https://wyx619.github.io/VasGBIF/articles/Example.md))
for a complete walk-through of all four stages.

## References

Chamberlain, Scott, Vijay Barve, Dan Mcglinn, et al. 2025. *Rgbif:
Interface to the Global Biodiversity Information Facility API*.
<https://CRAN.R-project.org/package=rgbif>.
