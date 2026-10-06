test_that("source files have unique keys and complete supported codings", {
  expect_equal(nrow(repository$children), 539)
  expect_equal(nrow(repository$prayers), 23)
  expect_equal(length(repository$alternatives), 74)
  expect_silent(validate_rows(repository$children, children_file))
  expect_silent(validate_rows(repository$prayers, prayers_file))
  expect_false(any(repository$children$row_type == "avg_from_aggregate"))
  expect_error(validate_rows(rbind(repository$children, repository$children[1, ]), children_file), "Duplicate")
})

test_that("invalid counts and missing descriptions fail validation", {
  for (value in c("", "nan", "inf", "-1", "0.5")) {
    row <- example_row("one", 1, 1)
    row$n_sons <- value
    expect_error(validate_rows(row, children_file), info = value)
  }
  row <- example_row("one", 1, 1)
  row$sons <- ""
  expect_error(validate_rows(row, children_file), "description")
  for (field in c("source", "parents", "epic")) {
    row <- example_row("one", 1, 1)
    row[[field]] <- ""
    expect_error(validate_rows(row, children_file), "key/source", info = field)
  }
  row <- example_row("one", 1, 1, row_type = "typo")
  expect_error(validate_rows(row, children_file), "row type")
  row <- example_row("one", 1, 1, historicity = "typo")
  expect_error(validate_rows(row, children_file), "historicity")
})

test_that("invalid, blank, and absent prayer codes fail at load time", {
  for (value in c("typo", "")) {
    row <- repository$prayers[1, ]
    row$desired_gender <- value
    expect_error(validate_rows(row, prayers_file), "desired-gender")
    expect_error(prayer_summary(row), "desired-gender")
  }
  row$desired_gender <- NULL
  expect_error(validate_rows(row, prayers_file), "schema")
  expect_error(prayer_summary(row), "desired-gender")
})

test_that("CSV reader preserves literal blanks and rejects malformed inputs", {
  path <- tempfile(fileext = ".csv")
  writeLines(c("epic,parent,source", 'a,"one, two",NA', 'b,three,""'), path)
  rows <- read_rows(path)
  expect_identical(rows$parent, c("one, two", "three"))
  expect_identical(rows$source, c("NA", ""))
  for (text in list(c("a,a", "1,2"), c("a,b", "1,2,3"), c("a,b", "1"), "a,b")) {
    writeLines(text, path)
    expect_error(read_rows(path))
  }
})

test_that("alternative source columns are complete and drive the result", {
  row <- record(repository$children, "Jesse and wife (unnamed)")
  for (field in c("alternate_id", "alternate_source", "alternate_comments", "alternate_n_sons", "alternate_sons")) {
    bad <- row
    bad[[field]] <- ""
    expect_error(validate_rows(bad, children_file), info = field)
  }
  for (value in c("-1", "nan", "1.5")) {
    bad <- row
    bad$alternate_n_sons <- value
    expect_error(validate_rows(bad, children_file), info = value)
  }
  row$alternate_n_sons <- "9"
  row$alternate_sons <- "nine sons in a synthetic account"
  changed <- apply_alternative(row, source_alternatives(row)[[1]])
  expect_equal(number(changed, "n_sons") - number(row, "n_sons"), 2)
  expect_identical(row$n_sons, "7")
})

test_that("missing, repeated, renamed duplicate, and malformed targets fail", {
  rows <- rbind(example_row("one", 1, 1), example_row("two", 1, 1))
  a <- alternative("test", change("absent", list(n_sons = "2")))
  expect_error(apply_alternative(rows, a), "target")
  a$changes <- list(change("one", list(n_sons = "2")), change("one", list(n_sons = "3")))
  expect_error(apply_alternative(rows, a), "target")
  a$changes <- list(change("one", list(typo = "2")))
  expect_error(apply_alternative(rows, a), "columns")
  a$changes <- list(change("one", list(parents = "two")))
  expect_error(apply_alternative(rows, a), "Duplicate")
  a$changes <- list()
  expect_error(apply_alternative(rows, a), "Empty")
})
