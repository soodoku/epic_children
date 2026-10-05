import copy
import itertools

import pytest

from scripts.analyze import (
    ALTERNATE_FIELDS,
    ROBUSTNESS_RULES,
    apply_alternative,
    distribution_checks,
    distribution_summary,
    influence_checks,
    joint_coding_extremes,
    load_repository,
    markdown_results,
    prayer_summary,
    read_rows,
    robustness_grid,
    robustness_summary,
    select_robustness,
    summarize,
)


def example_row(name, sons, daughters, epic="a", unknown=0, **kwargs):
    return {
        "parents": name,
        "epic": epic,
        "n_sons": str(sons),
        "sons": "enumerated sons" if sons else "",
        "n_daughters": str(daughters),
        "daughters": "enumerated daughters" if daughters else "",
        "n_unknown_sex": str(unknown),
        "source": "Test passage",
        "comments": "",
        "row_type": "couple",
        "historicity": "legendary",
        "family_id": "",
        "alternate_id": "",
        **{f"alternate_{field}": "" for field in ALTERNATE_FIELDS},
        **kwargs,
    }


def alternative(identifier, changes):
    return {
        "id": identifier,
        "changes": [
            {"epic": "a", "parent": parent, "values": values}
            for parent, values in changes
        ],
    }


def test_weightings_have_distinct_denominators_and_ignore_inactive_rows():
    rows = [
        example_row("a1", 9, 1),
        example_row("a2", 0, 10),
        example_row("b1", 1, 0, epic="b"),
        example_row("inactive", 0, 0, epic="c"),
        example_row("unspecified", 0, 0, epic="d", unknown=2),
    ]
    result = robustness_summary(rows)
    assert result["rows"] == 5
    assert result["sexed_rows"] == 3
    assert result["source_categories"] == 2
    assert result["male_pct"] == pytest.approx(100 * 10 / 21)
    assert result["equal_record_pct"] == pytest.approx((90 + 0 + 100) / 3)
    assert result["equal_category_pct"] == pytest.approx((45 + 100) / 2)
    assert result["unknown_all_daughters_pct"] == pytest.approx(100 * 10 / 23)
    assert result["unknown_all_sons_pct"] == pytest.approx(100 * 12 / 23)


def test_caps_preserve_composition_and_do_not_recode_counts():
    rows = [
        example_row("large", 1000, 1000),
        example_row("small", 0, 1),
        example_row("unspecified", 0, 0, unknown=4),
    ]
    before = copy.deepcopy(rows)
    result = robustness_summary(rows, cap_total=10)
    assert result["sons"] == 1000
    assert result["daughters"] == 1001
    assert result["weighted_sons"] == 5
    assert result["weighted_daughters"] == 6
    assert result["weighted_unknown_sex"] == 4
    assert result["male_pct"] == pytest.approx(100 * 5 / 11)
    assert result["equal_record_pct"] == 25
    assert result["extra_daughters_for_parity"] is None
    assert rows == before
    with pytest.raises(ValueError, match="positive"):
        robustness_summary(rows, cap_total=0)


def test_undefined_shares_and_unknown_only_bounds():
    for rows in ([], [example_row("inactive", 0, 0)]):
        result = robustness_summary(rows)
        for field in (
            "male_pct",
            "equal_record_pct",
            "equal_category_pct",
            "unknown_all_daughters_pct",
            "unknown_all_sons_pct",
        ):
            assert result[field] is None
    result = robustness_summary([example_row("unspecified", 0, 0, unknown=2)])
    assert result["male_pct"] is None
    assert result["unknown_all_daughters_pct"] == 0
    assert result["unknown_all_sons_pct"] == 100


def test_empirical_percentiles_interpolate_and_handle_empty_and_singleton():
    result = distribution_summary([0, 10, 20, 30, 100])
    assert result["p25"] == 10
    assert result["p50"] == 20
    assert result["p75"] == 30
    assert result["p90"] == pytest.approx(72)
    assert result["p99"] == pytest.approx(97.2)
    assert distribution_summary([7])["p95"] == 7
    empty = distribution_summary([])
    assert empty["observations"] == 0
    assert all(v is None for k, v in empty.items() if k != "observations")


def test_winsorization_uses_positive_totals_and_preserves_sex_composition():
    rows = [
        example_row("small", 0, 2),
        example_row("large", 40, 40, unknown=20),
        example_row("unknown", 0, 0, unknown=10),
        example_row("inactive", 0, 0),
    ]
    before = copy.deepcopy(rows)
    distributions, winsorized = distribution_checks({"current": rows})
    measures = {r["measure"]: r for r in distributions if r["scope"] == "all"}
    assert measures["total_children"]["observations"] == 3
    assert measures["total_children"]["p50"] == 10
    assert measures["male_share_pct"]["observations"] == 2
    assert measures["male_share_pct"]["p50"] == 25
    result = next(
        r for r in winsorized if r["scope"] == "all" and r["upper_percentile"] == 90
    )
    assert result["cap_total"] == 82
    assert result["capped_rows"] == 1
    assert result["cutoff_observations"] == 3
    assert result["weighted_sons"] == pytest.approx(32.8)
    assert result["weighted_daughters"] == pytest.approx(34.8)
    assert result["weighted_unknown_sex"] == pytest.approx(26.4)
    assert result["male_pct"] == pytest.approx(100 * 32.8 / 67.6)
    assert result["equal_record_pct"] == 25
    assert result["sons"] == 40
    assert result["daughters"] == 42
    assert rows == before


def test_winsorization_recomputes_cutoffs_for_versions_and_selections():
    baseline = [
        example_row("small", 0, 2),
        example_row("large", 100, 0, row_type="mythical_count"),
    ]
    revised = [
        example_row("small", 0, 2),
        example_row("large", 10, 0, row_type="mythical_count"),
    ]
    _, winsorized = distribution_checks({"current": baseline, "revised": revised})
    cutoffs = {
        (r["version"], r["scope"]): r["cap_total"]
        for r in winsorized
        if r["upper_percentile"] == 90
    }
    assert cutoffs["current", "all"] == pytest.approx(90.2)
    assert cutoffs["revised", "all"] == pytest.approx(9.2)
    assert cutoffs["current", "flag_filtered"] == 2
    assert cutoffs["revised", "flag_filtered"] == 2
    assert cutoffs["current", "historical_filtered"] is None


def test_winsorization_ties_and_unknown_only_records():
    _, winsorized = distribution_checks(
        {"current": [example_row(str(i), 0, 0, unknown=4) for i in range(20)]}
    )
    for r in winsorized:
        assert r["capped_rows"] == 0
        assert r["male_pct"] is None
        if r["scope"] == "all":
            assert r["cap_total"] == 4
            assert r["weighted_unknown_sex"] == 80


def test_size_rules_count_unknown_children_and_use_inclusive_thresholds():
    rows = [
        example_row("two", 1, 1),
        example_row("three", 1, 1, unknown=1),
        example_row("only_unknown", 0, 0, unknown=3),
    ]
    assert [r["parents"] for r in select_robustness(rows, {"max_total": 2})] == ["two"]
    assert [r["parents"] for r in select_robustness(rows, {"min_sexed": 2})] == [
        "two",
        "three",
    ]


def test_excluding_alternative_targets_handles_renamed_rows():
    rows = [example_row("fixed", 1, 1), example_row("old", 2, 0)]
    alt = alternative("rename", [("old", {"parents": "new", "n_sons": "3"})])
    versions = {"current": rows, "rename": apply_alternative(rows, alt)}
    grid = robustness_grid(versions, [alt])
    results = [r for r in grid if r["specification"] == "without_alternatives"]
    assert len(results) == 2
    for r in results:
        assert (r["rows"], r["sons"], r["daughters"], r["male_pct"]) == (1, 1, 1, 50)


def test_omission_checks_remove_whole_units_and_conserve_rows():
    rows = [
        example_row("a1", 9, 1, family_id="linked"),
        example_row("b1", 1, 9, epic="b", family_id="linked"),
    ]
    checks = influence_checks(rows)
    for result in checks:
        assert result["removed_rows"] + result["rows"] == 2
    records = {
        r["omitted"]: r for r in checks if r["scope"] == "all" and r["unit"] == "record"
    }
    assert records["a / a1"]["male_pct"] == 10
    assert records["a / a1"]["change_pp"] == -40
    assert records["b / b1"]["male_pct"] == 90
    families = [r for r in checks if r["unit"] == "linked_family"]
    assert len(families) == 2
    assert all(r["rows"] == 0 and r["male_pct"] is None for r in families)


@pytest.mark.parametrize(
    "rule",
    [
        {},
        {"max_total": 5},
        {"policy": "exclude_mythical_and_cross"},
        {"row_types": {"couple"}},
    ],
)
def test_joint_extremes_match_exhaustive_enumeration_and_keep_links(rule):
    rows = [
        example_row("fixed", 2, 2),
        example_row("one", 1, 1),
        example_row("left", 3, 1),
        example_row("right", 1, 3),
        example_row("three", 1, 1),
    ]
    alts = [
        alternative("first", [("one", {"n_sons": "7"})]),
        alternative(
            "linked",
            [
                ("left", {"n_sons": "1", "n_daughters": "4"}),
                ("right", {"n_sons": "2", "n_daughters": "1"}),
            ],
        ),
        alternative(
            "third", [("three", {"n_daughters": "5", "row_type": "mythical_count"})]
        ),
    ]
    before = copy.deepcopy(rows)
    possibilities = []
    for choices in itertools.product((False, True), repeat=len(alts)):
        changed = rows
        for use, alt in zip(choices, alts):
            if use:
                changed = apply_alternative(changed, alt)
        possibilities.append(summarize(select_robustness(changed, rule))["male_pct"])
    bounds = joint_coding_extremes(rows, alts, rule)
    assert bounds[0]["male_pct"] == pytest.approx(min(possibilities))
    assert bounds[1]["male_pct"] == pytest.approx(max(possibilities))
    for bound in bounds:
        changed = rows
        for alt in alts:
            if alt["id"] in bound["selected_alternative_ids"].split(";"):
                changed = apply_alternative(changed, alt)
        assert (
            summarize(select_robustness(changed, rule))["male_pct"] == bound["male_pct"]
        )
    assert rows == before


def test_joint_extremes_reject_overlaps_and_unguaranteed_denominators():
    rows = [example_row("fixed", 2, 2), example_row("one", 1, 1)]
    a = alternative("a", [("one", {"n_sons": "7"})])
    b = alternative("b", [("one", {"n_daughters": "7"})])
    with pytest.raises(ValueError, match="disjoint"):
        joint_coding_extremes(rows, [a, b], {})
    with pytest.raises(ValueError, match="positive unaffected denominator"):
        joint_coding_extremes(rows[1:], [a], {})


def test_prayer_counts_partition_episodes_without_sex_inference():
    rows = [
        {"epic": "a", "desired_gender": "son"},
        {"epic": "a", "desired_gender": "unspecified"},
        {"epic": "b", "desired_gender": "son_and_daughter"},
    ]
    summary = prayer_summary(rows)
    assert summary[0] == {
        "source_category": "all",
        "episodes": 3,
        "son": 1,
        "daughter": 0,
        "son_and_daughter": 1,
        "unspecified": 1,
    }
    for r in summary:
        assert r["episodes"] == sum(
            r[c] for c in ("son", "daughter", "son_and_daughter", "unspecified")
        )
    with pytest.raises(ValueError, match="Unknown desired-gender"):
        prayer_summary([{"epic": "a", "desired_gender": "typo"}])


def test_generated_robustness_prose_and_source_extremes_reconcile():
    from scripts.analyze import CHILDREN, ROOT

    current, alternatives = load_repository()
    directory = ROOT / "results"
    grid = read_rows(directory / "robustness.csv")
    influence = read_rows(directory / "influence.csv")
    envelopes = read_rows(directory / "coding_envelope.csv")
    prayers = read_rows(directory / "prayer_summary.csv")
    distributions = read_rows(directory / "distributions.csv")
    winsorized = read_rows(directory / "winsorized.csv")
    summary = read_rows(directory / "summary.csv")
    assert len(grid) == (len(alternatives) + 1) * len(ROBUSTNESS_RULES)
    for bound in envelopes:
        combined = current[CHILDREN]
        for alt in alternatives:
            if alt["id"] in bound["selected_alternative_ids"].split(";"):
                combined = apply_alternative(combined, alt)
        result = summarize(
            select_robustness(combined, ROBUSTNESS_RULES[bound["specification"]])
        )
        for col in ("rows", "sons", "daughters", "unknown_sex", "male_pct"):
            assert result[col] == pytest.approx(float(bound[col]))
    numeric = {
        "rows",
        "sexed_rows",
        "source_categories",
        "sons",
        "daughters",
        "unknown_sex",
        "weighted_sons",
        "weighted_daughters",
        "weighted_unknown_sex",
        "male_pct",
        "equal_record_pct",
        "equal_category_pct",
        "unknown_all_daughters_pct",
        "unknown_all_sons_pct",
        "extra_daughters_for_parity",
        "daughters_multiplier_for_parity",
        "removed_rows",
        "baseline_male_pct",
        "change_pp",
        "episodes",
        "son",
        "daughter",
        "son_and_daughter",
        "unspecified",
    }
    numeric.update(
        {
            "observations",
            "minimum",
            "maximum",
            "upper_percentile",
            "cap_total",
            "cutoff_observations",
            "capped_rows",
        }
    )
    numeric.update(f"p{p:02d}" for p in (5, 10, 25, 50, 75, 90, 95, 99))
    for table in (
        grid,
        influence,
        envelopes,
        prayers,
        distributions,
        winsorized,
        summary,
    ):
        for row in table:
            for field in numeric & row.keys():
                row[field] = float(row[field]) if row[field] else None
                if row[field] is not None and row[field].is_integer():
                    row[field] = int(row[field])
    assert (
        markdown_results(
            grid, influence, envelopes, prayers, distributions, winsorized, summary
        )
        in (ROOT / "readme.md").read_text()
    )
