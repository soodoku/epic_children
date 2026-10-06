test_that("weightings have distinct denominators and ignore inactive rows", {
  rows <- rbind(
    example_row("a1", 9, 1), example_row("a2", 0, 10), example_row("b1", 1, 0, epic = "b"),
    example_row("inactive", 0, 0, epic = "c"), example_row("unspecified", 0, 0, epic = "d", unknown = 2)
  )
  x <- robustness_summary(rows)
  expect_equal(x$rows, 5)
  expect_equal(x$sexed_rows, 3)
  expect_equal(x$source_categories, 2)
  expect_equal(x$male_pct, 100 * 10 / 21)
  expect_equal(x$equal_record_pct, (90 + 0 + 100) / 3)
  expect_equal(x$equal_category_pct, (45 + 100) / 2)
  expect_equal(x$unknown_all_daughters_pct, 100 * 10 / 23)
  expect_equal(x$unknown_all_sons_pct, 100 * 12 / 23)
})

test_that("counting policies have the specified math", {
  rows <- rbind(
    example_row("big", 1000, 0, row_type = "mythical_count"),
    example_row("parallel", 1, 0, row_type = "cross_tradition"), example_row("normal", 1, 1, unknown = 2)
  )
  expect_equal(summarize_counts(rows)$sons, 1002)
  expect_equal(summarize_counts(rows, "sons_cap_200")$sons, 202)
  expect_equal(summarize_counts(rows, "exclude_mythical")$male_pct, 100 * 2 / 3)
  expect_equal(summarize_counts(rows, "exclude_mythical_and_cross")$male_pct, 50)
  expect_equal(summarize_counts(rows, "direct_parent_rows")$rows, 1)
  expect_error(summarize_counts(rows, "typo"), "Unknown policy")
})

test_that("caps preserve composition, raw counts, and baseline", {
  rows <- rbind(example_row("large", 1000, 1000), example_row("small", 0, 1), example_row("unknown", 0, 0, unknown = 4))
  before <- rows
  x <- robustness_summary(rows, 10)
  expect_equal(x$sons, 1000)
  expect_equal(x$daughters, 1001)
  expect_equal(x$weighted_sons, 5)
  expect_equal(x$weighted_daughters, 6)
  expect_equal(x$weighted_unknown_sex, 4)
  expect_equal(x$male_pct, 100 * 5 / 11)
  expect_equal(x$equal_record_pct, 25)
  expect_true(is.na(x$extra_daughters_for_parity))
  expect_identical(rows, before)
  for (cap in c(0, -1, NA_real_, Inf)) expect_error(robustness_summary(rows, cap), "positive")
})

test_that("undefined shares remain missing, including empty selections", {
  for (rows in list(example_row("inactive", 0, 0), repository$children[FALSE, ])) {
    x <- robustness_summary(rows)
    expect_true(all(is.na(unlist(x[c(
      "male_pct",
      "equal_record_pct",
      "equal_category_pct",
      "unknown_all_daughters_pct",
      "unknown_all_sons_pct"
    )]))))
  }
  x <- robustness_summary(example_row("unknown", 0, 0, unknown = 2))
  expect_true(is.na(x$male_pct))
  expect_equal(x$unknown_all_daughters_pct, 0)
  expect_equal(x$unknown_all_sons_pct, 100)
})

test_that("inclusive percentiles interpolate and handle empty and singleton values", {
  x <- distribution_summary(c(0, 10, 20, 30, 100))
  expect_equal(unname(unlist(x[c("p25", "p50", "p75", "p90", "p99")])), c(10, 20, 30, 72, 97.2))
  expect_equal(distribution_summary(7)$p95, 7)
  expect_equal(distribution_summary(numeric())$observations, 0)
  expect_true(all(is.na(distribution_summary(numeric())[-1])))
})

test_that("winsorization uses positive totals and preserves sex composition", {
  rows <- rbind(
    example_row("small", 0, 2),
    example_row("large", 40, 40, unknown = 20),
    example_row("unknown", 0, 0, unknown = 10),
    example_row("inactive", 0, 0)
  )
  before <- rows
  results <- distribution_checks(list(current = rows))
  distributions <- subset(results$distributions, scope == "all")
  expect_equal(distributions$observations[distributions$measure == "total_children"], 3)
  expect_equal(distributions$p50[distributions$measure == "total_children"], 10)
  expect_equal(distributions$observations[distributions$measure == "male_share_pct"], 2)
  expect_equal(distributions$p50[distributions$measure == "male_share_pct"], 25)
  x <- subset(results$winsorized, scope == "all" & upper_percentile == 90)
  expect_equal(x$cap_total, 82)
  expect_equal(x$capped_rows, 1)
  expect_equal(x$cutoff_observations, 3)
  expect_equal(x$weighted_sons, 32.8)
  expect_equal(x$weighted_daughters, 34.8)
  expect_equal(x$weighted_unknown_sex, 26.4)
  expect_equal(x$male_pct, 100 * 32.8 / 67.6)
  expect_equal(x$equal_record_pct, 25)
  expect_identical(rows, before)
})

test_that("winsorization recomputes cutoffs within versions and selections", {
  baseline <- rbind(example_row("small", 0, 2), example_row("large", 100, 0, row_type = "mythical_count"))
  revised <- rbind(example_row("small", 0, 2), example_row("large", 10, 0, row_type = "mythical_count"))
  x <- subset(distribution_checks(list(current = baseline, revised = revised))$winsorized, upper_percentile == 90)
  expect_equal(x$cap_total[x$version == "current" & x$scope == "all"], 90.2)
  expect_equal(x$cap_total[x$version == "revised" & x$scope == "all"], 9.2)
  expect_equal(x$cap_total[x$scope == "flag_filtered"], c(2, 2))
  expect_true(all(is.na(x$cap_total[x$scope == "historical_filtered"])))
  rows <- dplyr::bind_rows(lapply(1:20, function(i) example_row(as.character(i), 0, 0, unknown = 4)))
  x <- subset(distribution_checks(list(current = rows))$winsorized, scope == "all")
  expect_equal(x$capped_rows, rep(0, 3))
  expect_equal(x$cap_total, rep(4, 3))
  expect_true(all(is.na(x$male_pct)))
})

test_that("size thresholds include unknown sex and renamed alternative targets are omitted", {
  rows <- rbind(
    example_row("two", 1, 1),
    example_row("three", 1, 1, unknown = 1),
    example_row("unknown", 0, 0, unknown = 3)
  )
  expect_identical(select_robustness(rows, list(max_total = 2))$parents, "two")
  expect_identical(select_robustness(rows, list(min_sexed = 2))$parents, c("two", "three"))
  a <- alternative("rename", change("three", list(parents = "new", n_sons = "3")))
  x <- subset(
    robustness_grid(list(current = rows, rename = apply_alternative(rows, a)), list(a)),
    specification == "without_alternatives"
  )
  expect_equal(x$rows, c(2, 2))
  expect_equal(x$sons, c(1, 1))
  expect_equal(x$male_pct, c(50, 50))
})

test_that("omission checks remove complete units and preserve empty denominators", {
  rows <- rbind(
    example_row("a1", 9, 1, family_id = "linked"),
    example_row("b1", 1, 9, epic = "b", family_id = "linked")
  )
  x <- influence_checks(rows)
  expect_true(all(x$removed_rows + x$rows == 2))
  expect_equal(subset(x, scope == "all" & unit == "record" & omitted == "a / a1")$male_pct, 10)
  expect_equal(subset(x, scope == "all" & unit == "record" & omitted == "b / b1")$change_pp, 40)
  expect_true(all(is.na(subset(x, unit == "linked_family")$male_pct)))
  rows$family_id <- ""
  expect_false(any(influence_checks(rows)$unit == "linked_family"))
})
