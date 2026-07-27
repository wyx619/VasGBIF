# Enumeration GBIF issue

An enumeration of validation rules for single occurrence records.

## Usage

``` r
EnumOccurrenceIssue
```

## Format

A data.table with 69 rows and 9 columns

- constant:

  GBIF issue constant

- description:

  GBIF issue description

- definition:

  Our definition for classifying geographic issues

- type:

  Type issue

- priority:

  Impact of the issue for the use of geospatial information

- score:

  Impact, in number, of the issue for the use of geospatial information

- selection_score:

  Value used to calculate the quality of the geospatial information
  according to the classification of the issue

- reasoning:

  Reasoning of the impact of the theme for the use of geospatial
  information

- notes:

  Notes

## Source

- [GBIF Infrastructure: Data
  processing](https://www.gbif.org/article/5i3CQEZ6DuWiycgMaaakCo/gbif-infrastructure-data-processing)

- [An enumeration of validation rules for single occurrence
  records](https://gbif.github.io/gbif-api/apidocs/org/gbif/api/vocabulary/OccurrenceIssue.html)

## Details

There are many things that can go wrong and we continously encounter
unexpected data. In order to help us and publishers improve the data, we
flag records with various issues that we have encountered. This is also
very useful for data consumers as you can include these issues as
filters in occurrence searches. Not all issues indicate bad data. Some
are merley flagging the fact that GBIF has altered values during
processing. On the details page of any occurrence record you will see
the list of issues in the notice at the bottom.
