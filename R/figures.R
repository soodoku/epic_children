plot_results <- function(tables, destination = "figs") {
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  groups <- subset(tables$group_summary, policy == "exclude_mythical_and_cross" & group_by == "epic" & rows >= 5)
  groups <- groups[order(groups$male_pct, groups$group), ]
  groups$label <- factor(paste0(groups$group, " (rows=", groups$rows, ")"),
    levels = paste0(groups$group, " (rows=", groups$rows, ")")
  )
  categories <- ggplot2::ggplot(groups, ggplot2::aes(male_pct, label)) +
    ggplot2::geom_col(fill = "#456987", width = 0.7) +
    ggplot2::scale_x_continuous(limits = c(0, 100), breaks = seq(0, 100, 20), expand = c(0, 0)) +
    ggplot2::labs(
      x = "Sons / (sons + daughters), percent", title = "Recorded children by source category",
      caption = paste(
        "Excludes mythical_count and cross_tradition records; source ambiguities remain.",
        "Categories with at least 5 retained rows. Categories are inherited labels.",
        sep = "\n"
      )
    ) +
    theme_evidence()
  save_evidence(categories, file.path(destination, "plot_by_tradition"), 9, 7.5)

  counts <- subset(tables$summary, version == "current")
  counts$label <- factor(unname(policies[counts$policy]), levels = rev(unname(policies)))
  counting <- ggplot2::ggplot(counts, ggplot2::aes(male_pct, label)) +
    ggplot2::geom_col(fill = "#456987", width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%%", male_pct)), hjust = 1.15, colour = "white") +
    ggplot2::scale_x_continuous(limits = c(0, 100), breaks = seq(0, 100, 20), expand = c(0, 0)) +
    ggplot2::labs(
      x = "Sons / (sons + daughters), percent", title = "Counting policies applied to the working dataset",
      caption = "Source ambiguities remain. Policies change weights or included records."
    ) +
    theme_evidence()
  save_evidence(counting, file.path(destination, "plot_counting_policies"), 10, 4)

  base <- subset(tables$robustness, version == "current")
  measures <- c(
    male_pct = "Pooled counts",
    equal_record_pct = "Equal records",
    equal_category_pct = "Equal source categories"
  )
  points <- dplyr::bind_rows(lapply(names(measures), function(measure) {
    data.frame(label = base$label, value = base[[measure]], measure = unname(measures[measure]))
  }))
  points$label <- factor(points$label, levels = rev(base$label))
  points$measure <- factor(points$measure, levels = unname(measures))
  robustness <- ggplot2::ggplot(points, ggplot2::aes(value, label, colour = measure)) +
    ggplot2::geom_vline(xintercept = 50, colour = "grey65", linetype = "dotted", linewidth = 0.4) +
    ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.55, orientation = "y"), size = 2.3) +
    ggplot2::scale_colour_manual(values = c("#456987", "#AA6030", "#666666")) +
    ggplot2::scale_x_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    ggplot2::labs(
      x = "Share of sons, percent", title = "Recorded sex composition under alternative analysis rules",
      caption = paste(
        "Each weighting describes a different quantity. Dotted line: numerical parity (50%).",
        "Descriptive summaries; no sampling intervals. Caps preserve within-record sex composition.",
        sep = "\n"
      )
    ) +
    theme_evidence(14) +
    ggplot2::theme(legend.justification = "left")
  save_evidence(robustness, file.path(destination, "plot_robustness"), 12, 8)
  invisible(list(categories = categories, counting = counting, robustness = robustness))
}
