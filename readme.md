# Epic Children

A sourced dataset of parent–child relationships and prayer or birth episodes
from selected epics, religious texts, mythological traditions, and historical
accounts. Use it to inspect recorded genealogies and compare how counts change
under different sources and analytical choices.

[Child records](data/epic_children.csv) ·
[Prayer and birth episodes](data/epic_prayer_for_children.csv) ·
[Analysis](scripts/analyze.py)

The collection is selected, not representative. Records mix named children,
unnamed enumerations, minimum counts, and overlapping biological, adoptive, or
household relationships. Totals describe these records, not unique births or
population sex ratios. An omitted daughter and an absent daughter cannot
consistently be distinguished; these counts alone do not identify son preference.

## Results

<!-- BEGIN GENERATED SUMMARY -->

The dataset contains 539 child records, 23 prayer and birth episodes, and 74 alternative codings. Sons predominate in the recorded counts; the magnitude depends on how much weight large records receive.

| Summary of recorded children | Male share |
|---|---:|
| Pooled counts, uncapped | 99.2% |
| Equal weight per record | 80.1% |
| Equal weight per source category | 76.6% |
| Total contribution capped at P90 (8 children) | 77.1% |
| Total contribution capped at P95 (13 children) | 77.3% |
| Total contribution capped at P99 (100 children) | 83.0% |

Male share is sons / (sons + daughters). The equal-record mean averages these shares; the equal-category mean averages pooled shares within nonempty `epic` categories. Records without sex-specified children do not enter either mean. These summaries describe different quantities.

### Percentiles and winsorization

| Measure across records | P10 | P25 | Median | P75 | P90 | P95 | P99 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Recorded sons | 1.00 | 1.00 | 1.00 | 3.00 | 6.00 | 10.00 | 100.00 |
| Recorded daughters | 0.00 | 0.00 | 0.00 | 1.00 | 2.00 | 3.00 | 11.25 |
| Recorded children, all sexes | 1.00 | 1.00 | 2.00 | 4.00 | 8.00 | 13.00 | 100.00 |
| Share of sons (%) | 33.33 | 66.67 | 100.00 | 100.00 | 100.00 | 100.00 | 100.00 |

Percentiles give each record equal weight and use linear interpolation between ordered observations ([Python's inclusive method](https://docs.python.org/3/library/statistics.html#statistics.quantiles)). Count distributions exclude zero-total records, which can represent inactive accounts. Share distributions exclude records with no sex-specified children. A median share of 100% describes the middle record, not the pooled counts.

Winsorization is upper-only: estimate the size cutoff among positive-total records, then multiply each record's sons, daughters, and unspecified-sex counts by `min(1, cutoff / total)`. This preserves sex composition and retains records while limiting their contribution. Cutoffs are recomputed within each selection and coding version. Counts in the source CSV stay unchanged. Ties mean the fraction capped need not equal the nominal tail.

### Other sensitivity checks

Removing the most influential record (bhagavata_purana / Sagara and Sumati) gives 86.8% sons. Excluding the 7 inherited `mythical_count` records gives 77.5% sons. Also excluding `cross_tradition` records gives 77.6%; restricting further to records labelled historical gives 61.3%. These labels are not validated quality ratings: some other 100-son records are unflagged, and the historical subset differs in source composition.

Allowing the recorded alternatives to vary jointly gives 74.9–79.2% for the flag-filtered selection. This is a mechanical sensitivity range, not a confidence interval or necessarily a coherent textual edition. Full outputs also cover count thresholds, fixed contribution caps, record and category omissions, and allocation of unspecified-sex children.

The episode wording codes are 8 son, 0 daughter, 1 both, and 14 unspecified. The list includes announcements, unintended conception, and revival requests; these counts do not measure prospective parental preferences.

<!-- END GENERATED SUMMARY -->

## Use the data

Each child row represents a sourced family, parent, or enumerated group.
Read its `source` and `comments` before using the counts. Git tracks corrections;
source disagreements are retained alongside the working coding.

| Fields | Interpretation |
|---|---|
| `parents`, `husband`, `wife` | Parent labels; they do not consistently establish marriage or biological parenthood. `unknown`, `multiple`, and `none` are placeholders. |
| `husband_id`, `wife_id`, `family_id` | Inherited parent IDs and selected cross-tradition family links. Coverage and identity resolution are incomplete; these are not universal deduplication keys. |
| `n_sons`, `n_daughters`, `n_unknown_sex` | Recorded counts, including stated minimum counts. Zero does not necessarily mean an explicit assertion of absence. Unspecified sex does not measure omitted or unquantified children. |
| `sons`, `daughters` | Names or descriptions supporting the counts, not standardized lists. |
| `epic`, `row_type`, `historicity` | Source category, record type, and inherited historical classification. Categories vary in scope and are not independent sampled traditions. |
| `source`, `comments` | References, coding scope, and unresolved questions. Evidence includes primary passages, secondary summaries, and stated inferences. |
| `alternate_*` | One alternate account per row: complete counts, child descriptions, source, explanation, and `alternate_id`. Rows sharing an ID change together. Blank fields mean no recorded alternative, not agreement among sources. |

Alternatives **replace** affected records; they are never appended as additional
children. The analysis applies each alternative separately to the baseline;
only the joint sensitivity calculation combines choices. Other interpretation
and counting-scope choices live in [alternatives.json](data/alternatives.json).
The alternatives do not exhaust textual variation, and may change names or
attribution without changing counts.

The prayer CSV records `parent`, `epic`, `ritual_type`, `desired_gender`,
`sons_born`, `daughters_born`, `children_from_prayer`, `source`, and `comments`.
`desired_gender` reflects explicit wishes in the cited wording; neither a
promise nor the eventual child's sex establishes a wish. `unspecified` does
not mean indifference. Outcome fields associate children with episodes without
establishing that prayer caused a birth.

## Reproduce

Use Python 3.10 or later. Computation and validation use the standard library;
figures use matplotlib.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-dev.txt
make check PYTHON=python
make reproduce PYTHON=python
```

`make check` runs formatting, lint, tests, and data validation. `make reproduce`
regenerates all tables, alternative datasets, figures, and the results above.
To generate tables elsewhere without changing the README or figures:

```sh
python scripts/analyze.py --no-plots --output-dir /tmp/epic-children-results
```

| Output | Contents |
|---|---|
| [Distributions](results/distributions.csv) | Count and share percentiles for the baseline and each alternative, across three selections. |
| [Winsorization](results/winsorized.csv) | P90, P95, and P99 cutoffs, numbers of capped records, and weighted summaries. |
| [Robustness](results/robustness.csv) | Seventeen selection and weighting rules for every version. |
| [Influence](results/influence.csv) | Omit one record, source category, or supplied linked-family group at a time. |
| [Joint coding ranges](results/coding_envelope.csv) | Extreme pooled shares and the alternative IDs producing them. |
| [Count summaries](results/summary.csv), [group summaries](results/group_summary.csv) | Counting policies overall and by source, row type, or historicity. The legacy `sons_cap_200` policy caps sons alone. |
| [Alternative datasets](results/alternatives/) | Complete datasets with each alternative applied separately. |
| [Episode summaries](results/prayer_summary.csv) | Wording codes overall and by source category. |

The [robustness figure](figs/plot_robustness.png) compares inclusion and weighting
rules. Sensitivity checks describe coding and analytical choices. They do not
resolve selection or source dependence; no population significance tests or
sampling confidence intervals are reported.

## Correct or extend a record

Check the exact passage and translation, then update `source` and `comments`
with the coding rationale. Correct errors directly. Preserve reasonable
alternative accounts in `alternate_*`, using a shared `alternate_id` when
parentage changes affect several rows. Do not allocate children to unnamed
spouses, treat an unquantified plural as an exact count, or combine incompatible
accounts. Run `make check` and `make reproduce` after edits.

Unresolved identities and source limits belong in the record's notes. Validation
checks structure and internal consistency; it does not certify every source or
make the collection exhaustive.
