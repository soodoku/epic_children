policies <- c(
  uncapped = "All rows, uncapped", sons_cap_200 = "All rows, sons capped at 200 per row",
  exclude_mythical = "Exclude mythical_count rows",
  exclude_mythical_and_cross = "Exclude mythical_count and cross_tradition rows",
  direct_parent_rows = "Only couple and spouse_unnamed rows"
)

select_rows <- function(rows, policy = "uncapped") {
  if (!policy %in% names(policies)) stop("Unknown policy: ", policy)
  keep <- switch(policy,
    exclude_mythical = rows$row_type != "mythical_count",
    exclude_mythical_and_cross = !rows$row_type %in% c("mythical_count", "cross_tradition"),
    direct_parent_rows = rows$row_type %in% c("couple", "spouse_unnamed"),
    rep(TRUE, nrow(rows))
  )
  rows[keep, , drop = FALSE]
}

share <- function(sons, total) if (total > 0) 100 * sons / total else NA_real_

summarize_counts <- function(rows, policy = "uncapped") {
  selected <- select_rows(rows, policy)
  sons <- number(selected, "n_sons")
  if (policy == "sons_cap_200") sons <- pmin(sons, 200)
  sons <- sum(sons)
  daughters <- sum(number(selected, "n_daughters"))
  data.frame(
    rows = nrow(selected), sons = sons, daughters = daughters,
    unknown_sex = sum(number(selected, "n_unknown_sex")), male_pct = share(sons, sons + daughters)
  )
}

robustness_rules <- list(
  all = list(label = "All records"),
  flag_filtered = list(
    label = "Exclude extreme-count and cross-tradition flags",
    policy = "exclude_mythical_and_cross"
  ),
  direct_filtered = list(
    label = "Flag-filtered, couple or unnamed-spouse rows", policy = "exclude_mythical_and_cross",
    row_types = c("couple", "spouse_unnamed")
  ),
  historical_filtered = list(
    label = "Flag-filtered, historical label only", policy = "exclude_mythical_and_cross", historicity = "historical"
  ),
  without_alternatives = list(
    label = "Flag-filtered, omit all alternative-target rows",
    policy = "exclude_mythical_and_cross",
    omit_alternatives = TRUE
  )
)
for (limit in c(2, 5)) {
  robustness_rules[[paste0("min_sexed_", limit)]] <- list(
    label = paste("Flag-filtered, at least", limit, "sex-specified children"),
    policy = "exclude_mythical_and_cross", min_sexed = limit
  )
}
for (limit in c(5, 10, 20, 50, 100, 200)) {
  robustness_rules[[paste0("max_total_", limit)]] <- list(
    label = paste("At most", limit, "recorded children per row"), max_total = limit
  )
}
for (limit in c(10, 20, 50, 200)) {
  robustness_rules[[paste0("cap_total_", limit)]] <- list(
    label = paste("All records, contribution capped at", limit), cap_total = limit
  )
}

select_robustness <- function(rows, rule, alternative_keys = character()) {
  rows <- select_rows(rows, if (is.null(rule$policy)) "uncapped" else rule$policy)
  keep <- rep(TRUE, nrow(rows))
  if (!is.null(rule$row_types)) keep <- keep & rows$row_type %in% rule$row_types
  if (!is.null(rule$historicity)) keep <- keep & rows$historicity == rule$historicity
  if (isTRUE(rule$omit_alternatives)) keep <- keep & !row_key(rows) %in% alternative_keys
  if (!is.null(rule$min_sexed)) keep <- keep & number(rows, "n_sons") + number(rows, "n_daughters") >= rule$min_sexed
  if (!is.null(rule$max_total)) {
    keep <- keep & rowSums(as.data.frame(lapply(
      rows[count_fields],
      as.numeric
    ))) <= rule$max_total
  }
  rows[keep, , drop = FALSE]
}

robustness_summary <- function(rows, cap_total = NULL) {
  if (!is.null(cap_total) && (length(cap_total) != 1L || !is.finite(cap_total) || cap_total <= 0)) {
    stop("The total-contribution cap must be positive")
  }
  raw <- summarize_counts(rows)
  sons <- number(rows, "n_sons")
  daughters <- number(rows, "n_daughters")
  unknown <- number(rows, "n_unknown_sex")
  totals <- sons + daughters + unknown
  weights <- rep(1, nrow(rows))
  if (!is.null(cap_total)) weights[totals > 0] <- pmin(1, cap_total / totals[totals > 0])
  sexed <- sons + daughters > 0
  record_shares <- 100 * sons[sexed] / (sons + daughters)[sexed]
  groups <- split(which(sexed), rows$epic[sexed])
  category_shares <- vapply(
    groups,
    function(i) share(sum(weights[i] * sons[i]), sum(weights[i] * (sons[i] + daughters[i]))),
    numeric(1)
  )
  ws <- sum(weights * sons)
  wd <- sum(weights * daughters)
  wu <- sum(weights * unknown)
  data.frame(
    rows = nrow(rows), sexed_rows = sum(sexed), source_categories = length(groups),
    sons = raw$sons, daughters = raw$daughters, unknown_sex = raw$unknown_sex,
    weighted_sons = ws, weighted_daughters = wd, weighted_unknown_sex = wu,
    male_pct = share(ws, ws + wd),
    equal_record_pct = if (length(record_shares)) mean(record_shares) else NA_real_,
    equal_category_pct = if (length(category_shares)) mean(category_shares) else NA_real_,
    unknown_all_daughters_pct = share(ws, ws + wd + wu), unknown_all_sons_pct = share(ws + wu, ws + wd + wu),
    extra_daughters_for_parity = if (is.null(cap_total)) max(0, raw$sons - raw$daughters) else NA_real_,
    daughters_multiplier_for_parity =
      if (is.null(cap_total) && raw$daughters > 0) raw$sons / raw$daughters else NA_real_
  )
}

robustness_grid <- function(versions, alternatives) {
  keys <- unlist(lapply(alternatives, function(a) {
    unlist(lapply(a$changes, function(change) {
      c(
        paste(change$epic, change$parent, sep = "\r"),
        paste(
          if (is.null(change$values$epic)) change$epic else change$values$epic,
          if (is.null(change$values$parents)) change$parent else change$values$parents,
          sep = "\r"
        )
      )
    }))
  }), use.names = FALSE)
  dplyr::bind_rows(lapply(names(versions), function(version) {
    dplyr::bind_rows(lapply(names(robustness_rules), function(name) {
      rule <- robustness_rules[[name]]
      cbind(
        version = version, specification = name, label = rule$label,
        robustness_summary(select_robustness(versions[[version]], rule, keys), rule$cap_total)
      )
    }))
  }))
}

percentiles <- c(5, 10, 25, 50, 75, 90, 95, 99)
distribution_scopes <- c("all", "flag_filtered", "historical_filtered")

distribution_summary <- function(values) {
  cuts <- if (length(values)) {
    unname(stats::quantile(values, percentiles / 100, type = 7))
  } else {
    rep(
      NA_real_,
      length(percentiles)
    )
  }
  data.frame(
    observations = length(values), minimum = if (length(values)) min(values) else NA_real_,
    as.list(stats::setNames(cuts, sprintf("p%02d", percentiles))),
    maximum = if (length(values)) max(values) else NA_real_
  )
}

distribution_checks <- function(versions) {
  distributions <- winsorized <- list()
  for (version in names(versions)) {
    for (scope in distribution_scopes) {
      selected <- select_robustness(versions[[version]], robustness_rules[[scope]])
      s <- number(selected, "n_sons")
      d <- number(selected, "n_daughters")
      totals <- s + d + number(selected, "n_unknown_sex")
      positive <- totals > 0
      values <- list(
        sons = s[positive], daughters = d[positive], total_children = totals[positive],
        male_share_pct = 100 * s[s + d > 0] / (s + d)[s + d > 0]
      )
      for (measure in names(values)) {
        distributions[[length(distributions) + 1L]] <- cbind(
          version = version, scope = scope, measure = measure, distribution_summary(values[[measure]])
        )
      }
      sizes <- distribution_summary(totals[positive])
      for (p in c(90, 95, 99)) {
        cap <- sizes[[paste0("p", p)]]
        winsorized[[length(winsorized) + 1L]] <- cbind(
          version = version, scope = scope, upper_percentile = p, cap_total = cap,
          cutoff_observations = sum(positive), capped_rows = if (any(positive)) sum(totals > cap) else 0L,
          robustness_summary(selected, if (is.na(cap)) NULL else cap)
        )
      }
    }
  }
  list(distributions = dplyr::bind_rows(distributions), winsorized = dplyr::bind_rows(winsorized))
}

influence_checks <- function(rows) {
  results <- list()
  for (scope in c("all", "flag_filtered")) {
    selected <- select_robustness(rows, robustness_rules[[scope]])
    baseline <- robustness_summary(selected)
    units <- list(
      linked_family = split(which(nzchar(selected$family_id)), selected$family_id[nzchar(selected$family_id)]),
      record = split(seq_len(nrow(selected)), paste(selected$epic, selected$parents, sep = " / ")),
      source_category = split(seq_len(nrow(selected)), selected$epic)
    )
    for (unit in names(units)) {
      for (omitted in sort(as.character(names(units[[unit]])), method = "radix")) {
        indexes <- units[[unit]][[omitted]]
        if (unit == "linked_family" && length(indexes) < 2L) next
        result <- robustness_summary(selected[-indexes, , drop = FALSE])
        results[[length(results) + 1L]] <- cbind(
          scope = scope, unit = unit, omitted = omitted, removed_rows = length(indexes),
          baseline_male_pct = baseline$male_pct, change_pp = result$male_pct - baseline$male_pct, result
        )
      }
    }
  }
  dplyr::bind_rows(results)
}

joint_coding_extremes <- function(rows, alternatives, rule) {
  if (!is.null(rule$cap_total) || isTRUE(rule$omit_alternatives)) {
    stop("Joint coding supports unweighted inclusion rules only")
  }
  touched <- character()
  options <- list()
  counts <- function(group) {
    x <- summarize_counts(select_robustness(group, rule))
    c(sons = x$sons, total = x$sons + x$daughters)
  }
  for (alternative in alternatives) {
    keys <- vapply(alternative$changes, function(c) paste(c$epic, c$parent, sep = "\r"), character(1))
    if (any(keys %in% touched)) stop("Joint coding requires disjoint alternative targets")
    touched <- c(touched, keys)
    baseline <- rows[row_key(rows) %in% keys, , drop = FALSE]
    options[[alternative$id]] <- list(baseline, apply_alternative(baseline, alternative))
  }
  fixed <- rows[!row_key(rows) %in% touched, , drop = FALSE]
  fixed_counts <- counts(fixed)
  if (fixed_counts["total"] <= 0) stop("Joint coding requires a positive unaffected denominator")
  contributions <- lapply(options, function(pair) rbind(counts(pair[[1]]), counts(pair[[2]])))
  dplyr::bind_rows(lapply(c("minimum", "maximum"), function(direction) {
    ratio <- unname(fixed_counts["sons"] / fixed_counts["total"])
    converged <- FALSE
    for (iteration in seq_len(1000)) {
      chosen <- vapply(contributions, function(pair) {
        score <- pair[, "sons"] - ratio * pair[, "total"]
        if (direction == "minimum") which.min(score) else which.max(score)
      }, integer(1))
      total <- fixed_counts
      for (i in seq_along(contributions)) total <- total + contributions[[i]][chosen[i], ]
      updated <- unname(total["sons"] / total["total"])
      if (abs(updated - ratio) <= 1e-13) {
        converged <- TRUE
        break
      }
      ratio <- updated
    }
    if (!converged) stop("Joint coding optimization did not converge")
    combined <- dplyr::bind_rows(c(list(fixed), lapply(seq_along(options), function(i) options[[i]][[chosen[i]]])))
    cbind(
      direction = direction, selected_alternative_ids = paste(names(options)[chosen == 2L], collapse = ";"),
      summarize_counts(select_robustness(combined, rule))
    )
  }))
}

prayer_summary <- function(rows) {
  if (!"desired_gender" %in% names(rows) || any(!rows$desired_gender %in% prayer_codes)) {
    stop("Unknown desired-gender code")
  }
  groups <- c(list(all = rows), split(rows, factor(rows$epic, levels = sort(unique(rows$epic), method = "radix"))))
  dplyr::bind_rows(lapply(names(groups), function(epic) {
    group <- groups[[epic]]
    data.frame(source_category = epic, episodes = nrow(group), as.list(vapply(
      stats::setNames(prayer_codes, prayer_codes), function(code) sum(group$desired_gender == code), integer(1)
    )))
  }))
}
