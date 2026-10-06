test_that("joint extrema match exhaustive combinations and preserve linked changes", {
  rows <- rbind(
    example_row("fixed", 2, 2),
    example_row("one", 1, 1),
    example_row("left", 3, 1),
    example_row("right", 1, 3),
    example_row("three", 1, 1)
  )
  alts <- list(
    alternative("first", change("one", list(n_sons = "7"))),
    alternative(
      "linked",
      change("left", list(n_sons = "1", n_daughters = "4")),
      change("right", list(n_sons = "2", n_daughters = "1"))
    ),
    alternative("third", change("three", list(n_daughters = "5", row_type = "mythical_count")))
  )
  before <- rows
  for (rule in list(
    list(),
    list(max_total = 5),
    list(policy = "exclude_mythical_and_cross"),
    list(row_types = "couple")
  )) {
    choices <- expand.grid(rep(list(c(FALSE, TRUE)), length(alts)))
    possibilities <- vapply(seq_len(nrow(choices)), function(i) {
      changed <- rows
      for (j in seq_along(alts)) if (choices[i, j]) changed <- apply_alternative(changed, alts[[j]])
      summarize_counts(select_robustness(changed, rule))$male_pct
    }, numeric(1))
    bounds <- joint_coding_extremes(rows, alts, rule)
    expect_equal(bounds$male_pct, range(possibilities))
    for (i in seq_len(nrow(bounds))) {
      changed <- rows
      ids <- strsplit(bounds$selected_alternative_ids[i], ";", fixed = TRUE)[[1]]
      for (a in alts) if (a$id %in% ids) changed <- apply_alternative(changed, a)
      expect_equal(summarize_counts(select_robustness(changed, rule))$male_pct, bounds$male_pct[i])
    }
  }
  expect_identical(rows, before)
})

test_that("unsupported joint choices are rejected", {
  rows <- rbind(example_row("fixed", 2, 2), example_row("one", 1, 1))
  a <- alternative("a", change("one", list(n_sons = "7")))
  b <- alternative("b", change("one", list(n_daughters = "7")))
  expect_error(joint_coding_extremes(rows, list(a, b), list()), "disjoint")
  expect_error(joint_coding_extremes(rows[2, ], list(a), list()), "positive unaffected denominator")
  expect_error(joint_coding_extremes(rows, list(a), list(cap_total = 10)), "unweighted")
  expect_error(joint_coding_extremes(rows, list(a), list(omit_alternatives = TRUE)), "unweighted")
  expect_equal(joint_coding_extremes(rows, list(), list())$male_pct, c(50, 50))
})

test_that("every saved joint bound reconstructs from its linked IDs", {
  bounds <- read_output(file.path(root, "results", "coding_envelope.csv"))
  for (i in seq_len(nrow(bounds))) {
    row <- bounds[i, ]
    changed <- repository$children
    ids <- strsplit(row$selected_alternative_ids, ";", fixed = TRUE)[[1]]
    for (a in repository$alternatives) if (a$id %in% ids) changed <- apply_alternative(changed, a)
    actual <- summarize_counts(select_robustness(changed, robustness_rules[[row$specification]]))
    expect_equal(as.numeric(actual[1, ]), as.numeric(row[1, names(actual)]), tolerance = 1e-10)
  }
})

test_that("prayer codes partition selected episodes without outcome inference", {
  rows <- data.frame(epic = c("a", "a", "b"), desired_gender = c("son", "unspecified", "son_and_daughter"))
  x <- prayer_summary(rows)
  expect_equal(x$episodes, c(3, 2, 1))
  expect_equal(x$son, c(1, 1, 0))
  expect_true(all(rowSums(x[prayer_codes]) == x$episodes))
  counts <- prayer_summary(repository$prayers)
  expect_equal(unlist(counts[1, prayer_codes], use.names = FALSE), c(8, 0, 1, 14))
  unspecified <- c("Abraham and Sarah", "Abraham and Hagar", "Kunti via Surya", "Kunti via Vayu", "Parvati")
  expect_true(all(unspecified %in% repository$prayers$parent))
  expect_true(all(repository$prayers$desired_gender[repository$prayers$parent %in% unspecified] == "unspecified"))
})

test_that("prayer wording stays separate from the associated birth outcome", {
  rows <- repository$prayers
  for (parent in c(
    "Zechariah and Elizabeth", "Abraham and Hagar", "Abraham and Sarah",
    "Manoah and wife", "Ibrahim (2nd)", "Parvati"
  )) {
    row <- rows[rows$parent == parent, ]
    expect_equal(nrow(row), 1)
    expect_identical(row$sons_born, "1")
    expect_identical(row$desired_gender, "unspecified")
  }
  expect_identical(rows$desired_gender[rows$parent == "Gandhari"], "son_and_daughter")
  expect_identical(rows$desired_gender[rows$parent == "Drupad"], "son")
  expect_identical(rows$sons_born[rows$parent == "Hannah"], "1")
  expect_identical(rows$epic[rows$parent == "Zechariah and Elizabeth"], "christian_nt")
})
