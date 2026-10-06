theme_evidence <- function() {
  ggplot2::theme_minimal(base_size = 11, base_family = "sans") +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_blank(),
      plot.caption = ggplot2::element_text(hjust = 0, size = 9),
      plot.margin = ggplot2::margin(8, 18, 8, 8),
      plot.title.position = "plot", plot.caption.position = "plot",
      axis.title.y = ggplot2::element_blank(), legend.position = "top",
      legend.title = ggplot2::element_blank()
    )
}

save_evidence <- function(plot, path, width, height) {
  ggplot2::ggsave(paste0(path, ".pdf"), plot, width = width, height = height, bg = "white")
  ggplot2::ggsave(paste0(path, ".png"), plot, width = width, height = height, dpi = 180, bg = "white")
}
