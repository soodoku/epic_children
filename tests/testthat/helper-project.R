root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (file in list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE)) source(file, local = TRUE)
repository <- load_repository(root)

record <- function(rows, parent) {
  found <- rows[rows$parents == parent, , drop = FALSE]
  stopifnot(nrow(found) == 1L)
  rownames(found) <- NULL
  found
}

variant <- function(id) {
  found <- Filter(function(a) a$id == id, repository$alternatives)
  stopifnot(length(found) == 1L)
  apply_alternative(repository$children, found[[1]])
}

example_row <- function(name, sons, daughters, epic = "a", unknown = 0, ...) {
  row <- repository$children[1, , drop = FALSE]
  row[] <- ""
  values <- list(
    parents = name, epic = epic, n_sons = as.character(sons), n_daughters = as.character(daughters),
    n_unknown_sex = as.character(unknown), sons = if (sons > 0) "enumerated sons" else "",
    daughters = if (daughters > 0) "enumerated daughters" else "", source = "Test passage",
    row_type = "couple", historicity = "legendary"
  )
  values <- utils::modifyList(values, list(...))
  for (column in names(values)) row[[column]] <- values[[column]]
  row
}

change <- function(parent, values, epic = "a") list(epic = epic, parent = parent, values = values)
alternative <- function(id, ...) list(id = id, changes = list(...))
