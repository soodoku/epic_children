test_that("central results reproduce independent known totals", {
  x <- robustness_summary(repository$children)
  expect_equal(x$sons, 63149)
  expect_equal(x$daughters, 480)
  expect_equal(x$unknown_sex, 4)
  expect_equal(x$male_pct, 100 * 63149 / (63149 + 480))
  expect_equal(x$equal_record_pct, 80.11977690831955, tolerance = 1e-9)
  x <- distribution_checks(list(current = repository$children))
  expect_equal(subset(x$winsorized, scope == "all")$cap_total, c(8, 13, 100))
  expect_equal(subset(x$winsorized, scope == "all")$capped_rows, c(51, 25, 5))
  expect_equal(subset(x$distributions, scope == "all" & measure == "total_children")$p50, 2)
  expect_equal(subset(x$distributions, scope == "all" & measure == "male_share_pct")$p50, 100)
})

test_that("all committed tables reproduce and grouped totals reconcile", {
  output <- tempfile("epic-results-")
  tables <- generate_results(root, output)
  expect_equal(nrow(tables$robustness), (length(repository$alternatives) + 1) * length(robustness_rules))
  files <- list.files(output, pattern = "[.]csv$", recursive = TRUE)
  expect_setequal(files, list.files(file.path(root, "results"), pattern = "[.]csv$", recursive = TRUE))
  for (file in files) {
    reader <- if (startsWith(file, "alternatives/")) read_rows else read_output
    expect_equal(reader(file.path(output, file)),
      reader(file.path(root, "results", file)),
      tolerance = 1e-10, info = file
    )
  }
  for (policy_name in names(policies)) {
    overall <- subset(tables$summary, version == "current" & policy == policy_name)
    for (column in c("epic", "historicity", "row_type")) {
      parts <- subset(tables$group_summary, policy == policy_name & group_by == column)
      expect_equal(
        colSums(parts[c("rows", "sons", "daughters", "unknown_sex")]),
        unlist(overall[c("rows", "sons", "daughters", "unknown_sex")])
      )
    }
  }
  path <- tempfile(fileext = ".md")
  file.copy(file.path(root, "readme.md"), path)
  update_readme(tables, path)
  expect_identical(readLines(path), readLines(file.path(root, "readme.md")))
})

test_that("the analysis command works outside the repository", {
  output <- tempfile()
  status <- withr::with_dir(
    tempdir(),
    system2(
      file.path(R.home("bin"), "Rscript"), c(shQuote(file.path(root, "scripts", "run_all.R")), "--check"),
      stdout = output, stderr = output
    )
  )
  expect_equal(status, 0)
  expect_match(paste(readLines(output), collapse = "\n"), "Validated 562 records and 74 alternative codings")
})

test_that("figures use the reported data, common percentage axes, and supported groups", {
  plots <- plot_results(load_results(file.path(root, "results")), tempfile("epic-figures-"))
  for (plot in plots) expect_equal(plot$scales$get_scales("x")$limits, c(0, 100))
  expect_true(all(plots$categories$data$rows >= 5))
  expect_true(all(plots$categories$data$policy == "exclude_mythical_and_cross"))
  expect_equal(nrow(plots$robustness$data), 3 * length(robustness_rules))
  expect_false(anyNA(plots$robustness$data$value))
  built <- ggplot2::ggplot_build(plots$robustness)
  expect_equal(sort(built$data[[2]]$x), sort(plots$robustness$data$value))
})


test_that("entry points select their own locked environment", {
  elsewhere <- tempfile("other-r-project-")
  dir.create(elsewhere)
  output <- tempfile()
  status <- withr::with_envvar(c(RENV_PROJECT = elsewhere), system2(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(file.path(root, "scripts", "run_all.R")), "--check"),
    stdout = output, stderr = output
  ))
  text <- paste(readLines(output), collapse = "\n")
  expect_equal(status, 0)
  expect_match(text, "Validated 562 records and 74 alternative codings")
  expect_false(grepl("Warning|Failed", text))
  expect_length(list.files(elsewhere, all.files = TRUE, no.. = TRUE), 0)
})
