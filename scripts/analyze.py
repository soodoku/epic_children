"""Validate current data and reproduce descriptive tables and figures."""

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import quantiles

ROOT = Path(__file__).resolve().parents[1]
CHILDREN = "epic_children.csv"
PRAYERS = "epic_prayer_for_children.csv"
DATASETS = (CHILDREN, PRAYERS)
ALTERNATE_FIELDS = (
    "n_sons",
    "sons",
    "n_daughters",
    "daughters",
    "n_unknown_sex",
    "source",
    "comments",
)
ROW_TYPES = {
    "couple",
    "spouse_unnamed",
    "avg_from_aggregate",
    "cross_tradition",
    "single_divine",
    "mythical_count",
    "multi_wife_agg",
}
POLICIES = {
    "uncapped": "All rows, uncapped",
    "sons_cap_200": "All rows, sons capped at 200 per row",
    "exclude_mythical": "Exclude mythical_count rows",
    "exclude_mythical_and_cross": "Exclude mythical_count and cross_tradition rows",
    "direct_parent_rows": "Only couple and spouse_unnamed rows",
}


def read_rows(path):
    with Path(path).open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or len(set(reader.fieldnames)) != len(
            reader.fieldnames
        ):
            raise ValueError(f"Missing or duplicate column names: {path}")
        rows = list(reader)
    if not rows:
        raise ValueError(f"Empty dataset: {path}")
    if any(None in row or None in row.values() for row in rows):
        raise ValueError(f"Ragged CSV record: {path}")
    return rows


def row_key(row):
    return row["epic"], row.get("parents", row.get("parent"))


def number(row, column):
    raw = row[column]
    if not str(raw).strip():
        raise ValueError(f"Missing {column}: {row_key(row)}")
    value = float(raw)
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"Invalid {column}: {row_key(row)}: {raw}")
    return value


def validate_rows(rows, dataset):
    keys = [row_key(row) for row in rows]
    if len(set(keys)) != len(keys):
        raise ValueError(f"Duplicate record keys in {dataset}")
    columns = (
        ("n_sons", "n_daughters", "n_unknown_sex")
        if dataset == CHILDREN
        else ("sons_born", "daughters_born")
    )
    schema = set(rows[0])
    if dataset == CHILDREN:
        source_alternatives(rows)
    for row in rows:
        if set(row) != schema or any(value is None for value in row.values()):
            raise ValueError(f"Inconsistent schema in {dataset}")
        if not all(row_key(row)) or not row["source"].strip():
            raise ValueError(f"Missing key/source: {row_key(row)}")
        for column in columns:
            value = number(row, column)
            if not value.is_integer():
                raise ValueError(f"Fractional child count: {row_key(row)}")
        if dataset == CHILDREN:
            if row["row_type"] not in ROW_TYPES:
                raise ValueError(f"Unknown row type: {row_key(row)}")
            if row["historicity"] not in {"historical", "legendary", "mythological"}:
                raise ValueError(f"Unknown historicity: {row_key(row)}")
            for column, names in (("n_sons", "sons"), ("n_daughters", "daughters")):
                if number(row, column) > 0 and not row[names].strip():
                    raise ValueError(
                        f"Positive count without description: {row_key(row)}"
                    )


def source_alternatives(rows):
    """Read complete alternative source accounts stored beside current counts."""
    alternatives = {}
    columns = {"alternate_id"} | {f"alternate_{f}" for f in ALTERNATE_FIELDS}
    for row in rows:
        if not columns <= row.keys():
            raise ValueError(f"Missing alternate source columns: {row_key(row)}")
        if not any(row[c].strip() for c in columns):
            continue
        for field in ("id", "source", "comments"):
            if not row[f"alternate_{field}"].strip():
                raise ValueError(f"Incomplete alternate source: {row_key(row)}")
        for field, names in (
            ("n_sons", "sons"),
            ("n_daughters", "daughters"),
            ("n_unknown_sex", None),
        ):
            count = number(row, f"alternate_{field}")
            if not count.is_integer():
                raise ValueError(f"Fractional alternate count: {row_key(row)}")
            if count > 0 and names and not row[f"alternate_{names}"].strip():
                raise ValueError(f"Alternate count without names: {row_key(row)}")
        changes = alternatives.setdefault(row["alternate_id"], [])
        changes.append(
            {
                "epic": row["epic"],
                "parent": row["parents"],
                "values": {f: row[f"alternate_{f}"] for f in ALTERNATE_FIELDS},
            }
        )
    return [
        {"id": identifier, "changes": changes}
        for identifier, changes in sorted(alternatives.items())
    ]


def apply_alternative(rows, alternative):
    """Apply all linked changes in a source account to the same baseline."""
    if not alternative["changes"]:
        raise ValueError(f"Empty alternative: {alternative['id']}")
    updates = {}
    for change in alternative["changes"]:
        key = change["epic"], change["parent"]
        matches = [row for row in rows if row_key(row) == key]
        if len(matches) != 1 or key in updates:
            raise ValueError(f"Alternative target is missing or duplicated: {key}")
        if not set(change["values"]) <= set(matches[0]):
            raise ValueError(f"Unknown alternative columns: {alternative['id']}")
        updates[key] = change["values"]
    result = [dict(row, **updates.get(row_key(row), {})) for row in rows]
    validate_rows(result, CHILDREN)
    return sorted(result, key=row_key)


def load_repository(root=ROOT):
    current = {dataset: read_rows(root / "data" / dataset) for dataset in DATASETS}
    for dataset, rows in current.items():
        validate_rows(rows, dataset)
    alternatives = json.loads(
        (root / "data/alternatives.json").read_text(encoding="utf-8")
    )
    alternatives.extend(source_alternatives(current[CHILDREN]))
    alternatives.sort(key=lambda item: item["id"])
    if len({item["id"] for item in alternatives}) != len(alternatives):
        raise ValueError("Duplicate alternative IDs")
    for alternative in alternatives:
        apply_alternative(current[CHILDREN], alternative)
    return current, alternatives


def select_rows(rows, policy):
    if policy not in POLICIES:
        raise ValueError(f"Unknown policy: {policy}")
    if policy == "exclude_mythical":
        return [r for r in rows if r["row_type"] != "mythical_count"]
    if policy == "exclude_mythical_and_cross":
        return [
            r
            for r in rows
            if r["row_type"] not in {"mythical_count", "cross_tradition"}
        ]
    if policy == "direct_parent_rows":
        return [r for r in rows if r["row_type"] in {"couple", "spouse_unnamed"}]
    return list(rows)


def summarize(rows, policy="uncapped"):
    selected = select_rows(rows, policy)
    sons = sum(
        (
            min(number(row, "n_sons"), 200)
            if policy == "sons_cap_200"
            else number(row, "n_sons")
        )
        for row in selected
    )
    daughters = sum(number(row, "n_daughters") for row in selected)
    unknown = sum(number(row, "n_unknown_sex") for row in selected)
    total = sons + daughters
    return {
        "rows": len(selected),
        "sons": sons,
        "daughters": daughters,
        "unknown_sex": unknown,
        "male_pct": 100 * sons / total if total else None,
    }


def write_csv(path, rows, fieldnames=None):
    if fieldnames is None:
        fieldnames = list(rows[0])
    with Path(path).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def plots(current, summary, destination):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    policy = "exclude_mythical_and_cross"
    groups = defaultdict(list)
    for row in select_rows(current, policy):
        groups[row["epic"]].append(row)
    values = [
        (name, summarize(rows)) for name, rows in groups.items() if len(rows) >= 5
    ]
    values.sort(key=lambda pair: pair[1]["male_pct"] or 0)
    fig, ax = plt.subplots(figsize=(10, 8))
    labels = [f"{name} (rows={s['rows']})" for name, s in values]
    ax.barh(labels, [s["male_pct"] or 0 for _, s in values], color="#456987")
    ax.set(xlim=(0, 105), xlabel="Sons / (sons + daughters), percent")
    ax.set_title("Recorded child counts by dataset source category", pad=15)
    fig.text(
        0.5,
        0.015,
        "Excludes mythical_count and cross_tradition; source ambiguities remain.\n"
        "Categories with at least 5 retained rows; "
        "source categories are inherited labels.",
        ha="center",
        fontsize=9,
    )
    fig.tight_layout(rect=(0, 0.065, 1, 1))
    fig.savefig(destination / "plot_by_tradition.png", dpi=180)
    plt.close(fig)
    values = [row for row in summary if row["version"] == "current"]
    fig, ax = plt.subplots(figsize=(11, 5))
    ax.barh(
        [POLICIES[row["policy"]] for row in values],
        [row["male_pct"] or 0 for row in values],
        color="#456987",
    )
    ax.set(xlim=(0, 105), xlabel="Sons / (sons + daughters), percent")
    ax.set_title("Counting policies applied to the working dataset", pad=15)
    for i, row in enumerate(values):
        if row["male_pct"] is not None:
            ax.text(
                row["male_pct"] - 1,
                i,
                f"{row['male_pct']:.1f}%",
                va="center",
                ha="right",
                color="white",
            )
    fig.text(
        0.5,
        0.015,
        "Source ambiguities remain. Policies change weights or included rows.",
        ha="center",
        fontsize=9,
    )
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    fig.savefig(destination / "plot_counting_policies.png", dpi=180)
    plt.close(fig)


ROBUSTNESS_RULES = {
    "all": {"label": "All records"},
    "flag_filtered": {
        "label": "Exclude extreme-count and cross-tradition flags",
        "policy": "exclude_mythical_and_cross",
    },
    "direct_filtered": {
        "label": "Flag-filtered, couple or unnamed-spouse rows",
        "policy": "exclude_mythical_and_cross",
        "row_types": {"couple", "spouse_unnamed"},
    },
    "historical_filtered": {
        "label": "Flag-filtered, historical label only",
        "policy": "exclude_mythical_and_cross",
        "historicity": "historical",
    },
    "without_alternatives": {
        "label": "Flag-filtered, omit all alternative-target rows",
        "policy": "exclude_mythical_and_cross",
        "omit_alternatives": True,
    },
    **{
        f"min_sexed_{limit}": {
            "label": f"Flag-filtered, at least {limit} sex-specified children",
            "policy": "exclude_mythical_and_cross",
            "min_sexed": limit,
        }
        for limit in (2, 5)
    },
    **{
        f"max_total_{limit}": {
            "label": f"At most {limit} recorded children per row",
            "max_total": limit,
        }
        for limit in (5, 10, 20, 50, 100, 200)
    },
    **{
        f"cap_total_{limit}": {
            "label": f"All records, contribution capped at {limit}",
            "cap_total": limit,
        }
        for limit in (10, 20, 50, 200)
    },
}


def select_robustness(rows, rule, alternative_keys=frozenset()):
    selected = select_rows(rows, rule.get("policy", "uncapped"))
    return [
        row
        for row in selected
        if ("row_types" not in rule or row["row_type"] in rule["row_types"])
        and ("historicity" not in rule or row["historicity"] == rule["historicity"])
        and (not rule.get("omit_alternatives") or row_key(row) not in alternative_keys)
        and (
            "min_sexed" not in rule
            or number(row, "n_sons") + number(row, "n_daughters") >= rule["min_sexed"]
        )
        and (
            "max_total" not in rule
            or sum(
                number(row, col) for col in ("n_sons", "n_daughters", "n_unknown_sex")
            )
            <= rule["max_total"]
        )
    ]


def robustness_summary(rows, cap_total=None):
    """Keep raw counts separate from weights; undefined shares stay undefined."""
    if cap_total is not None and cap_total <= 0:
        raise ValueError("The total-contribution cap must be positive")
    raw = summarize(rows)
    weighted = []
    row_shares = []
    categories = defaultdict(lambda: [0.0, 0.0])
    for row in rows:
        sons, daughters, unknown = (
            number(row, col) for col in ("n_sons", "n_daughters", "n_unknown_sex")
        )
        total = sons + daughters + unknown
        weight = min(1, cap_total / total) if cap_total and total else 1
        weighted.append((weight * sons, weight * daughters, weight * unknown))
        if sons + daughters:
            row_shares.append(100 * sons / (sons + daughters))
            categories[row["epic"]][0] += weight * sons
            categories[row["epic"]][1] += weight * daughters
    ws, wd, wu = (math.fsum(x[i] for x in weighted) for i in range(3))
    category_shares = [100 * s / (s + d) for s, d in categories.values()]
    return {
        "rows": len(rows),
        "sexed_rows": len(row_shares),
        "source_categories": len(categories),
        "sons": raw["sons"],
        "daughters": raw["daughters"],
        "unknown_sex": raw["unknown_sex"],
        "weighted_sons": ws,
        "weighted_daughters": wd,
        "weighted_unknown_sex": wu,
        "male_pct": 100 * ws / (ws + wd) if ws + wd else None,
        "equal_record_pct": (
            math.fsum(row_shares) / len(row_shares) if row_shares else None
        ),
        "equal_category_pct": (
            math.fsum(category_shares) / len(category_shares)
            if category_shares
            else None
        ),
        "unknown_all_daughters_pct": (
            100 * ws / (ws + wd + wu) if ws + wd + wu else None
        ),
        "unknown_all_sons_pct": (
            100 * (ws + wu) / (ws + wd + wu) if ws + wd + wu else None
        ),
        "extra_daughters_for_parity": (
            max(0, raw["sons"] - raw["daughters"]) if cap_total is None else None
        ),
        "daughters_multiplier_for_parity": (
            raw["sons"] / raw["daughters"]
            if cap_total is None and raw["daughters"]
            else None
        ),
    }


def robustness_grid(versions, alternatives):
    keys = {(c["epic"], c["parent"]) for a in alternatives for c in a["changes"]}
    # Account for alternatives that rename their target (e.g. Job's two families).
    keys.update(
        (c["values"].get("epic", c["epic"]), c["values"].get("parents", c["parent"]))
        for a in alternatives
        for c in a["changes"]
    )
    return [
        {
            "version": version,
            "specification": name,
            "label": rule["label"],
            **robustness_summary(
                select_robustness(rows, rule, keys), rule.get("cap_total")
            ),
        }
        for version, rows in versions.items()
        for name, rule in ROBUSTNESS_RULES.items()
    ]


PERCENTILES = (5, 10, 25, 50, 75, 90, 95, 99)
DISTRIBUTION_SCOPES = ("all", "flag_filtered", "historical_filtered")


def distribution_summary(values):
    """Describe observations using linearly interpolated empirical percentiles."""
    cuts = (
        quantiles(values, n=100, method="inclusive") if len(values) > 1 else values * 99
    )
    return {
        "observations": len(values),
        "minimum": min(values) if values else None,
        **{f"p{p:02d}": cuts[p - 1] if values else None for p in PERCENTILES},
        "maximum": max(values) if values else None,
    }


def distribution_checks(versions):
    distributions, winsorized = [], []
    for version, rows in versions.items():
        for scope in DISTRIBUTION_SCOPES:
            selected = select_robustness(rows, ROBUSTNESS_RULES[scope])
            counts = [
                tuple(number(r, c) for c in ("n_sons", "n_daughters", "n_unknown_sex"))
                for r in selected
            ]
            # Zero-total rows can be inactive accounts, not observed childlessness.
            positive = [c for c in counts if sum(c) > 0]
            totals = [sum(c) for c in positive]
            values = {
                "sons": [c[0] for c in positive],
                "daughters": [c[1] for c in positive],
                "total_children": totals,
                "male_share_pct": [100 * s / (s + d) for s, d, _ in counts if s + d],
            }
            for measure, observations in values.items():
                distributions.append(
                    {
                        "version": version,
                        "scope": scope,
                        "measure": measure,
                        **distribution_summary(observations),
                    }
                )
            size_distribution = distribution_summary(totals)
            for percentile in (90, 95, 99):
                cap = size_distribution[f"p{percentile}"]
                winsorized.append(
                    {
                        "version": version,
                        "scope": scope,
                        "upper_percentile": percentile,
                        "cap_total": cap,
                        "cutoff_observations": len(totals),
                        "capped_rows": sum(t > cap for t in totals) if totals else 0,
                        **robustness_summary(selected, cap_total=cap),
                    }
                )
    return distributions, winsorized


def influence_checks(rows):
    results = []
    for scope in ("all", "flag_filtered"):
        selected = select_robustness(rows, ROBUSTNESS_RULES[scope])
        baseline = robustness_summary(selected)
        groups = defaultdict(set)
        for row in selected:
            key = row_key(row)
            groups["record", f"{key[0]} / {key[1]}"].add(key)
            groups["source_category", row["epic"]].add(key)
            if row["family_id"]:
                groups["linked_family", row["family_id"]].add(key)
        for (unit, omitted), keys in sorted(groups.items()):
            if unit == "linked_family" and len(keys) < 2:
                continue
            remaining = [r for r in selected if row_key(r) not in keys]
            result = robustness_summary(remaining)
            results.append(
                {
                    "scope": scope,
                    "unit": unit,
                    "omitted": omitted,
                    "removed_rows": len(keys),
                    "baseline_male_pct": baseline["male_pct"],
                    "change_pp": (
                        result["male_pct"] - baseline["male_pct"]
                        if result["male_pct"] is not None
                        and baseline["male_pct"] is not None
                        else None
                    ),
                    **result,
                }
            )
    return results


def joint_coding_extremes(rows, alternatives, rule):
    """Optimize a pooled share over disjoint baseline/alternative choices.

    For any trial share r, minimize (or maximize) S - r*(S+D) separately
    in each linked group, then update r to the chosen overall share. Linked
    rows always move together. These mechanical mixtures need not describe
    a coherent textual edition.
    """
    if rule.get("cap_total") or rule.get("omit_alternatives"):
        raise ValueError("Joint coding supports unweighted inclusion rules only")
    touched = set()
    options = []
    for alternative in alternatives:
        keys = {(c["epic"], c["parent"]) for c in alternative["changes"]}
        if keys & touched:
            raise ValueError("Joint coding requires disjoint alternative targets")
        touched.update(keys)
        baseline = [r for r in rows if row_key(r) in keys]
        changed = apply_alternative(baseline, alternative)
        options.append((alternative["id"], (baseline, changed)))
    fixed = [r for r in rows if row_key(r) not in touched]

    def counts(group):
        s = summarize(select_robustness(group, rule))
        return s["sons"], s["sons"] + s["daughters"]

    fixed_s, fixed_total = counts(fixed)
    if fixed_total <= 0:
        raise ValueError("Joint coding requires a positive unaffected denominator")
    contributions = [(aid, [counts(group) for group in pair]) for aid, pair in options]
    results = []
    for direction, chooser in (("minimum", min), ("maximum", max)):
        ratio = fixed_s / fixed_total
        for _ in range(1000):
            chosen = [
                chooser(range(2), key=lambda i: pair[i][0] - ratio * pair[i][1])
                for _, pair in contributions
            ]
            sons = fixed_s + sum(
                pair[i][0] for (_, pair), i in zip(contributions, chosen)
            )
            total = fixed_total + sum(
                pair[i][1] for (_, pair), i in zip(contributions, chosen)
            )
            updated = sons / total
            if math.isclose(updated, ratio, rel_tol=0, abs_tol=1e-13):
                break
            ratio = updated
        else:
            raise ValueError("Joint coding optimization did not converge")
        combined = fixed + [r for (_, pair), i in zip(options, chosen) for r in pair[i]]
        results.append(
            {
                "direction": direction,
                "selected_alternative_ids": ";".join(
                    aid for (aid, _), i in zip(options, chosen) if i
                ),
                **summarize(select_robustness(combined, rule)),
            }
        )
    return results


def prayer_summary(rows):
    codes = ("son", "daughter", "son_and_daughter", "unspecified")
    if any(r["desired_gender"] not in codes for r in rows):
        raise ValueError("Unknown desired-gender code")
    groups = {"all": rows}
    groups.update(
        {
            epic: [r for r in rows if r["epic"] == epic]
            for epic in sorted({r["epic"] for r in rows})
        }
    )
    return [
        {
            "source_category": epic,
            "episodes": len(group),
            **{code: sum(r["desired_gender"] == code for r in group) for code in codes},
        }
        for epic, group in groups.items()
    ]


def markdown_results(
    grid, influence, envelopes, prayers, distributions, winsorized, summary
):
    current = {r["specification"]: r for r in grid if r["version"] == "current"}
    base = current["all"]
    without_mythical = next(
        r
        for r in summary
        if r["version"] == "current" and r["policy"] == "exclude_mythical"
    )
    variants = len({r["version"] for r in grid}) - 1
    lines = [
        f"The dataset contains {base['rows']} child records, "
        f"{prayers[0]['episodes']} prayer and birth episodes, and "
        f"{variants} alternative codings. Sons predominate in the recorded counts; "
        "the magnitude depends on how much weight large records receive.",
        "",
        "| Summary of recorded children | Male share |",
        "|---|---:|",
        f"| Pooled counts, uncapped | {base['male_pct']:.1f}% |",
        f"| Equal weight per record | {base['equal_record_pct']:.1f}% |",
        f"| Equal weight per source category | {base['equal_category_pct']:.1f}% |",
    ]
    for r in winsorized:
        if r["version"] == "current" and r["scope"] == "all":
            lines.append(
                f"| Total contribution capped at P{r['upper_percentile']} "
                f"({r['cap_total']:g} children) | {r['male_pct']:.1f}% |"
            )
    lines.extend(
        [
            "",
            "Male share is sons / (sons + daughters). The equal-record mean averages "
            "these shares; the equal-category mean averages pooled shares within "
            "nonempty `epic` categories. Records without sex-specified children do "
            "not enter either mean. These summaries describe different quantities.",
            "",
            "### Percentiles and winsorization",
            "",
            "| Measure across records | P10 | P25 | Median | P75 | P90 | P95 | P99 |",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ]
    )
    labels = {
        "sons": "Recorded sons",
        "daughters": "Recorded daughters",
        "total_children": "Recorded children, all sexes",
        "male_share_pct": "Share of sons (%)",
    }
    for r in distributions:
        if r["version"] == "current" and r["scope"] == "all":
            values = " | ".join(
                f"{r[f'p{p:02d}']:.2f}" for p in (10, 25, 50, 75, 90, 95, 99)
            )
            lines.append(f"| {labels[r['measure']]} | {values} |")
    strongest = max(
        (r for r in influence if r["scope"] == "all" and r["unit"] == "record"),
        key=lambda r: abs(r["change_pp"]),
    )
    bounds = {
        r["direction"]: r["male_pct"]
        for r in envelopes
        if r["specification"] == "flag_filtered"
    }
    lines.extend(
        [
            "",
            "Percentiles give each record equal weight and use linear interpolation "
            "between ordered observations "
            "([Python's inclusive method]"
            "(https://docs.python.org/3/library/"
            "statistics.html#statistics.quantiles)). "
            "Count distributions exclude zero-total records, which can represent "
            "inactive accounts. Share distributions exclude records with no "
            "sex-specified children. A median share of 100% describes the middle "
            "record, not the pooled counts.",
            "",
            "Winsorization is upper-only: estimate the size cutoff among "
            "positive-total "
            "records, then multiply each record's sons, daughters, and unspecified-sex "
            "counts by `min(1, cutoff / total)`. This preserves sex composition and "
            "retains records while limiting their contribution. Cutoffs are recomputed "
            "within each selection and coding version. Counts in the source CSV stay "
            "unchanged. Ties mean the fraction capped need not equal the nominal tail.",
            "",
            "### Other sensitivity checks",
            "",
            f"Removing the most influential record ({strongest['omitted']}) gives "
            f"{strongest['male_pct']:.1f}% sons. Excluding the "
            f"{base['rows'] - without_mythical['rows']} inherited "
            f"`mythical_count` records gives "
            f"{without_mythical['male_pct']:.1f}% sons. "
            f"Also excluding `cross_tradition` records gives "
            f"{current['flag_filtered']['male_pct']:.1f}%; restricting further to "
            "records labelled historical gives "
            f"{current['historical_filtered']['male_pct']:.1f}%. "
            "These labels are not validated quality ratings: some other 100-son "
            "records are unflagged, and the historical subset differs in "
            "source composition.",
            "",
            f"Allowing the recorded alternatives to vary jointly gives "
            f"{bounds['minimum']:.1f}–{bounds['maximum']:.1f}% for the flag-filtered "
            "selection. This is a mechanical sensitivity range, not a confidence "
            "interval or necessarily a coherent textual edition. "
            "Full outputs also cover count thresholds, fixed contribution caps, "
            "record and category omissions, and allocation of "
            "unspecified-sex children.",
            "",
            f"The episode wording codes are {prayers[0]['son']} son, "
            f"{prayers[0]['daughter']} daughter, "
            f"{prayers[0]['son_and_daughter']} both, "
            f"and {prayers[0]['unspecified']} unspecified. The list includes "
            "announcements, unintended conception, and revival requests; these "
            "counts do not measure prospective parental preferences.",
        ]
    )
    return "\n".join(lines)


def plot_robustness(grid, destination):
    import matplotlib.pyplot as plt

    rows = [r for r in grid if r["version"] == "current"]
    fig, ax = plt.subplots(figsize=(12, 8))
    for field, label, color, offset in (
        ("male_pct", "Pooled counts", "#456987", -0.18),
        ("equal_record_pct", "Equal records", "#a65f32", 0),
        ("equal_category_pct", "Equal source categories", "#666666", 0.18),
    ):
        points = [(i, r[field]) for i, r in enumerate(rows) if r[field] is not None]
        ax.scatter(
            [value for _, value in points],
            [i + offset for i, _ in points],
            color=color,
            label=label,
            s=24,
        )
    ax.set_yticks(range(len(rows)), [r["label"] for r in rows])
    ax.invert_yaxis()
    ax.set(xlim=(0, 105), xlabel="Male share, percent")
    ax.axvline(50, color="#aaaaaa", linewidth=0.8, linestyle=":")
    ax.set_title("Recorded sex composition under alternative analysis rules", pad=45)
    ax.legend(
        loc="lower right", bbox_to_anchor=(1, 1.01), ncol=3, frameon=False, fontsize=9
    )
    fig.text(
        0.5,
        0.015,
        "Each weighting describes a different quantity. "
        "The dotted line marks numerical parity.\n"
        "Deterministic summaries of selected records; no sampling intervals. "
        "Caps preserve within-record sex composition.",
        ha="center",
        fontsize=9,
    )
    fig.tight_layout(rect=(0, 0.07, 1, 1))
    fig.savefig(destination / "plot_robustness.png", dpi=180)
    plt.close(fig)


def generate(root, output, figures, update_readme=False):
    current, alternatives = load_repository(root)
    output.mkdir(parents=True, exist_ok=True)
    versions = {"current": current[CHILDREN]}
    for alternative in alternatives:
        versions[alternative["id"]] = apply_alternative(current[CHILDREN], alternative)
    summary = [
        {"version": version, "policy": policy, **summarize(rows, policy)}
        for version, rows in versions.items()
        for policy in POLICIES
    ]
    write_csv(output / "summary.csv", summary)
    grouped = []
    for policy in POLICIES:
        for column in ("epic", "historicity", "row_type"):
            groups = defaultdict(list)
            for row in select_rows(current[CHILDREN], policy):
                groups[row[column]].append(row)
            for group, rows in sorted(groups.items()):
                grouped.append(
                    {
                        "policy": policy,
                        "group_by": column,
                        "group": group,
                        **summarize(rows, policy),
                    }
                )
    write_csv(output / "group_summary.csv", grouped)
    variant_dir = output / "alternatives"
    variant_dir.mkdir(exist_ok=True)
    for version, rows in versions.items():
        if version != "current":
            write_csv(variant_dir / f"{version}.csv", rows)
    grid = robustness_grid(versions, alternatives)
    influence = influence_checks(current[CHILDREN])
    envelopes = [
        {"specification": scope, **result}
        for scope in ("all", "flag_filtered", "max_total_20")
        for result in joint_coding_extremes(
            current[CHILDREN], alternatives, ROBUSTNESS_RULES[scope]
        )
    ]
    prayers = prayer_summary(current[PRAYERS])
    write_csv(output / "robustness.csv", grid)
    write_csv(output / "influence.csv", influence)
    write_csv(output / "coding_envelope.csv", envelopes)
    write_csv(output / "prayer_summary.csv", prayers)
    distributions, winsorized = distribution_checks(versions)
    write_csv(output / "distributions.csv", distributions)
    write_csv(output / "winsorized.csv", winsorized)
    description = markdown_results(
        grid, influence, envelopes, prayers, distributions, winsorized, summary
    )
    if update_readme:
        readme_path = root / "readme.md"
        readme = readme_path.read_text(encoding="utf-8")
        start, end = (
            "<!-- BEGIN GENERATED SUMMARY -->",
            "<!-- END GENERATED SUMMARY -->",
        )
        if readme.count(start) != 1 or readme.count(end) != 1:
            raise ValueError("README must contain exactly one generated summary block")
        before, rest = readme.split(start)
        _, after = rest.split(end)
        readme_path.write_text(
            before + start + "\n\n" + description + "\n\n" + end + after,
            encoding="utf-8",
        )
    if figures is not None:
        figures.mkdir(parents=True, exist_ok=True)
        plots(current[CHILDREN], summary, figures)
        plot_robustness(grid, figures)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate without writing")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "results")
    parser.add_argument("--figures-dir", type=Path, default=ROOT / "figs")
    parser.add_argument("--no-plots", action="store_true")
    parser.add_argument("--update-readme", action="store_true")
    args = parser.parse_args()
    if args.check:
        current, alternatives = load_repository()
        print(
            f"Validated {sum(map(len, current.values()))} records and "
            f"{len(alternatives)} alternative codings; "
            "validation checks data structure, not source accuracy."
        )
    else:
        generate(
            ROOT,
            args.output_dir,
            None if args.no_plots else args.figures_dir,
            args.update_readme,
        )
        print(f"Wrote descriptive results to {args.output_dir}")


if __name__ == "__main__":
    main()
