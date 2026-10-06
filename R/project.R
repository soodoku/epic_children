generate_results <- function(root = ".", output = file.path(root, "results")) {
  repository <- load_repository(root)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  versions <- c(list(current = repository$children), stats::setNames(
    lapply(repository$alternatives, function(a) apply_alternative(repository$children, a)),
    vapply(repository$alternatives, `[[`, character(1), "id")
  ))
  summary <- dplyr::bind_rows(lapply(names(versions), function(version) {
    dplyr::bind_rows(lapply(names(policies), function(policy) {
      cbind(version = version, policy = policy, summarize_counts(versions[[version]], policy))
    }))
  }))
  grouped <- list()
  for (policy in names(policies)) {
    for (column in c("epic", "historicity", "row_type")) {
      selected <- select_rows(repository$children, policy)
      for (group in sort(unique(selected[[column]]), method = "radix")) {
        grouped[[length(grouped) + 1L]] <- cbind(
          policy = policy, group_by = column, group = group,
          summarize_counts(selected[selected[[column]] == group, , drop = FALSE], policy)
        )
      }
    }
  }
  grid <- robustness_grid(versions, repository$alternatives)
  envelopes <- dplyr::bind_rows(lapply(c("all", "flag_filtered", "max_total_20"), function(scope) {
    cbind(
      specification = scope,
      joint_coding_extremes(repository$children, repository$alternatives, robustness_rules[[scope]])
    )
  }))
  distribution <- distribution_checks(versions)
  tables <- list(
    summary = summary, group_summary = dplyr::bind_rows(grouped), robustness = grid,
    influence = influence_checks(repository$children), coding_envelope = envelopes,
    prayer_summary = prayer_summary(repository$prayers), distributions = distribution$distributions,
    winsorized = distribution$winsorized
  )
  for (name in names(tables)) write_output(tables[[name]], file.path(output, paste0(name, ".csv")))
  alternative_dir <- file.path(output, "alternatives")
  dir.create(alternative_dir, showWarnings = FALSE)
  for (version in setdiff(names(versions), "current")) {
    write_output(versions[[version]], file.path(alternative_dir, paste0(version, ".csv")))
  }
  invisible(tables)
}

load_results <- function(directory = "results") {
  names <- c(
    "summary",
    "group_summary",
    "robustness",
    "influence",
    "coding_envelope",
    "prayer_summary",
    "distributions",
    "winsorized"
  )
  stats::setNames(lapply(names, function(name) read_output(file.path(directory, paste0(name, ".csv")))), names)
}
