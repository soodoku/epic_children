readme_results <- function(tables) {
  current <- subset(tables$robustness, version == "current")
  base <- subset(current, specification == "all")
  filtered <- subset(current, specification == "flag_filtered")
  historical <- subset(current, specification == "historical_filtered")
  without <- subset(tables$summary, version == "current" & policy == "exclude_mythical")
  prayers <- subset(tables$prayer_summary, source_category == "all")
  variants <- length(unique(tables$robustness$version)) - 1L
  pct <- function(x) sprintf("%.1f%%", x)
  caps <- subset(tables$winsorized, version == "current" & scope == "all")
  summary_table <- paste(c(
    "| Summary | Share of sons |", "|---|---:|",
    paste0("| Pooled counts, uncapped | ", pct(base$male_pct), " |"),
    paste0("| Equal weight per record | ", pct(base$equal_record_pct), " |"),
    paste0("| Equal weight per source category | ", pct(base$equal_category_pct), " |"),
    sprintf(
      "| Total contribution capped at P%d (%g children) | %.1f%% |",
      caps$upper_percentile,
      caps$cap_total,
      caps$male_pct
    )
  ), collapse = "\n")
  distributions <- subset(tables$distributions, version == "current" & scope == "all")
  labels <- c(
    sons = "Recorded sons",
    daughters = "Recorded daughters",
    total_children = "Recorded children, all sexes",
    male_share_pct = "Share of sons (%)"
  )
  percentile_table <- paste(c(
    "| Measure | Records | P10 | P25 | Median | P75 | P90 | P95 | P99 |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    vapply(seq_len(nrow(distributions)), function(i) {
      row <- distributions[i, ]
      values <- unlist(row[sprintf("p%02d", c(10, 25, 50, 75, 90, 95, 99))], use.names = FALSE)
      paste0(
        "| ",
        labels[row$measure],
        " | ",
        row$observations,
        " | ",
        paste(sprintf("%.2f", values), collapse = " | "),
        " |"
      )
    }, character(1))
  ), collapse = "\n")
  influence <- subset(tables$influence, scope == "all" & unit == "record")
  strongest <- influence[which.max(abs(influence$change_pp)), ]
  strongest_name <- sub("^.*? / ", "", strongest$omitted)
  bounds <- subset(tables$coding_envelope, specification == "flag_filtered")
  minimum <- bounds$male_pct[bounds$direction == "minimum"]
  maximum <- bounds$male_pct[bounds$direction == "maximum"]
  as.character(glue::glue('
## What we did

We assembled {base$rows} records of families, parents, or groups of children
from selected texts and accounts. Counts include named children, explicit
enumerations, and stated minimum counts. We retained {variants} alternative
codings covering source differences, attribution, and counting scope, and
separately coded {prayers$episodes} prayer and birth episodes.

We compare pooled counts with summaries that give equal weight to each record
or source category. We also examine percentiles, limit the contribution of
large records, omit records and source categories in turn, and vary the recorded
source choices. These checks show which features of the collection drive the results.

## What we found

Sons make up a majority under each weighting below, but the size of the imbalance
changes substantially. The uncapped total is especially sensitive to extraordinary
enumerations.

{summary_table}

The share is sons / (sons + daughters). The equal-record mean averages these
shares; the equal-category mean averages pooled shares within nonempty `epic`
categories. Records without sex-specified children do not enter either mean.
These summaries describe different quantities.

![Recorded shares of sons under alternative selection and weighting rules](figs/plot_robustness.png)

Each row applies a selection or contribution rule to the baseline coding. Points
compare pooled, equal-record, and equal-category summaries; the dotted line marks
50%. These are descriptive comparisons, without sampling intervals.

### Distribution across records

{percentile_table}

Percentiles give each record equal weight and use linear interpolation between
ordered observations (R\'s `quantile(type = 7)`). Count distributions exclude
zero-total records, which can represent inactive accounts. Share distributions
exclude records with no sex-specified children. A median share of 100% describes
the middle record, not the pooled counts.

Winsorization is upper-only: estimate the size cutoff among positive-total records,
then multiply each record\'s sons, daughters, and unspecified-sex counts by
`min(1, cutoff / total)`. This preserves sex composition and retains records while
limiting their contribution. Cutoffs are recomputed within each selection and
coding version. Counts in the source CSV stay unchanged. Ties mean the fraction
capped need not equal the nominal tail.

### Other sensitivity checks

Removing the most influential record, {strongest_name}, gives {pct(strongest$male_pct)}
sons. Excluding the {base$rows - without$rows} inherited `mythical_count` records
gives {pct(without$male_pct)} sons. Also excluding `cross_tradition` records gives
{pct(filtered$male_pct)}; restricting further to records labelled historical gives
{pct(historical$male_pct)}. The flags are inherited classifications, not quality
ratings; some other 100-son records are unflagged. The historical subset also
differs in source composition.

Allowing the recorded alternatives to vary jointly gives {sprintf("%.1f", minimum)}–{pct(maximum)}
for the flag-filtered selection. This is a mechanical sensitivity range, not a
confidence interval or necessarily a coherent textual edition. Full outputs also
cover count thresholds, fixed contribution caps, record and category omissions,
and allocation of unspecified-sex children.

The episode wording codes are {prayers$son} son, {prayers$daughter} daughter,
{prayers$son_and_daughter} both, and {prayers$unspecified} unspecified. The list
includes announcements, unintended conception, and revival requests; these counts
do not measure prospective parental preferences.

### Variation across source categories

![Pooled shares of sons by source category after the inherited flag exclusions](figs/plot_by_tradition.png)

Bars show sons / (sons + daughters) after excluding `mythical_count` and
`cross_tradition` records. Categories with at least five retained rows are shown;
labels give row counts. These compare selected records under inherited source
labels, not populations or independent samples of traditions.

The collection is selected rather than representative. Records can overlap, and
sources can omit or leave children unnumbered. The checks establish sensitivity
within this collection; they do not separate selective recording from differences
in family composition. No population significance tests or sampling confidence
intervals are reported.
'))
}

update_readme <- function(tables, path = "readme.md") {
  text <- readLines(path, warn = FALSE, encoding = "UTF-8")
  start <- which(text == "<!-- BEGIN GENERATED SUMMARY -->")
  end <- which(text == "<!-- END GENERATED SUMMARY -->")
  if (length(start) != 1L || length(end) != 1L || start >= end) {
    stop("README must contain exactly one generated summary block")
  }
  result <- c(text[seq_len(start)], "", readme_results(tables), "", text[seq.int(end, length(text))])
  writeLines(result, path, useBytes = TRUE)
  invisible(result)
}
