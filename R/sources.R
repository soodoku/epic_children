children_file <- "epic_children.csv"
prayers_file <- "epic_prayer_for_children.csv"
prayer_codes <- c("son", "daughter", "son_and_daughter", "unspecified")
count_fields <- c("n_sons", "n_daughters", "n_unknown_sex")
alternate_fields <- c("n_sons", "sons", "n_daughters", "daughters", "n_unknown_sex", "source", "comments")
row_types <- c("couple", "spouse_unnamed", "single_divine", "mythical_count", "multi_wife_agg", "cross_tradition")

read_rows <- function(path) {
  rows <- suppressWarnings(readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = character(), trim_ws = FALSE, name_repair = "minimal", progress = FALSE
  ))
  if (anyDuplicated(names(rows)) || any(!nzchar(names(rows)))) stop("Missing or duplicate column names: ", path)
  if (!nrow(rows)) stop("Empty dataset: ", path)
  if (nrow(readr::problems(rows)) || anyNA(rows)) stop("Ragged CSV record: ", path)
  as.data.frame(rows, stringsAsFactors = FALSE)
}

row_key <- function(rows) {
  parent <- if ("parents" %in% names(rows)) rows$parents else rows$parent
  paste(rows$epic, parent, sep = "\r")
}

number <- function(rows, column) {
  if (!column %in% names(rows) || anyNA(rows[[column]]) || any(!nzchar(trimws(rows[[column]])))) {
    stop("Missing ", column)
  }
  value <- suppressWarnings(as.numeric(rows[[column]]))
  if (any(!is.finite(value) | value < 0)) stop("Invalid ", column)
  value
}

validate_rows <- function(rows, dataset) {
  required <- if (dataset == children_file) {
    c("epic", "parents", "source", "row_type", "historicity", "sons", "daughters", count_fields)
  } else if (dataset == prayers_file) {
    c("epic", "parent", "source", "desired_gender", "sons_born", "daughters_born")
  } else {
    stop("Unknown dataset: ", dataset)
  }
  if (!all(required %in% names(rows)) || anyDuplicated(names(rows)) || anyNA(rows)) {
    stop("Missing or inconsistent schema in ", dataset)
  }
  if (anyDuplicated(row_key(rows))) stop("Duplicate record keys in ", dataset)
  parent <- if (dataset == children_file) "parents" else "parent"
  if (any(!nzchar(trimws(unlist(rows[c("epic", parent, "source")]))))) stop("Missing key/source")
  columns <- if (dataset == children_file) count_fields else c("sons_born", "daughters_born")
  for (column in columns) {
    value <- number(rows, column)
    if (any(value != floor(value))) stop("Fractional child count")
  }
  if (dataset == children_file) {
    if (any(!rows$row_type %in% row_types)) stop("Unknown row type")
    if (any(!rows$historicity %in% c("historical", "legendary", "mythological"))) stop("Unknown historicity")
    for (sex in c("sons", "daughters")) {
      if (any(number(rows, paste0("n_", sex)) > 0 & !nzchar(trimws(rows[[sex]])))) {
        stop("Positive count without description")
      }
    }
    source_alternatives(rows)
  } else if (any(!rows$desired_gender %in% prayer_codes)) {
    stop("Unknown desired-gender code")
  }
  invisible(rows)
}

source_alternatives <- function(rows) {
  columns <- c("alternate_id", paste0("alternate_", alternate_fields))
  if (!all(columns %in% names(rows))) stop("Missing alternate source columns")
  alternatives <- list()
  for (i in seq_len(nrow(rows))) {
    row <- rows[i, , drop = FALSE]
    if (!any(nzchar(trimws(unlist(row[columns]))))) next
    if (any(!nzchar(trimws(unlist(row[c("alternate_id", "alternate_source", "alternate_comments")]))))) {
      stop("Incomplete alternate source")
    }
    for (field in count_fields) {
      count <- number(row, paste0("alternate_", field))
      if (count != floor(count)) stop("Fractional alternate count")
      if (field != "n_unknown_sex" && count > 0 && !nzchar(trimws(row[[paste0("alternate_", sub("n_", "", field))]]))) {
        stop("Alternate count without names")
      }
    }
    values <- as.list(row[paste0("alternate_", alternate_fields)])
    names(values) <- alternate_fields
    id <- row$alternate_id
    change <- list(epic = row$epic, parent = row$parents, values = values)
    alternatives[[id]] <- c(alternatives[[id]], list(change))
  }
  lapply(
    sort(as.character(names(alternatives)), method = "radix"),
    function(id) list(id = id, changes = alternatives[[id]])
  )
}

apply_alternative <- function(rows, alternative) {
  if (!length(alternative$changes)) stop("Empty alternative")
  keys <- row_key(rows)
  touched <- character()
  result <- rows
  for (change in alternative$changes) {
    key <- paste(change$epic, change$parent, sep = "\r")
    index <- which(keys == key)
    if (length(index) != 1L || key %in% touched) stop("Alternative target is missing or duplicated")
    if (!all(names(change$values) %in% names(rows))) stop("Unknown alternative columns")
    for (column in names(change$values)) result[index, column] <- change$values[[column]]
    touched <- c(touched, key)
  }
  validate_rows(result, children_file)
  result <- result[order(result$epic, result$parents, method = "radix"), , drop = FALSE]
  rownames(result) <- NULL
  result
}

load_repository <- function(root = ".") {
  children <- read_rows(file.path(root, "data", children_file))
  prayers <- read_rows(file.path(root, "data", prayers_file))
  validate_rows(children, children_file)
  validate_rows(prayers, prayers_file)
  alternatives <- c(
    jsonlite::fromJSON(file.path(root, "data", "alternatives.json"), simplifyVector = FALSE),
    source_alternatives(children)
  )
  ids <- vapply(alternatives, `[[`, character(1), "id")
  if (any(!grepl("^[a-z0-9_]+$", ids)) || anyDuplicated(ids)) stop("Invalid or duplicate alternative IDs")
  alternatives <- alternatives[order(ids, method = "radix")]
  for (alternative in alternatives) apply_alternative(children, alternative)
  list(children = children, prayers = prayers, alternatives = alternatives)
}

write_output <- function(rows, path) readr::write_csv(rows, path, na = "")
read_output <- function(path) readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
