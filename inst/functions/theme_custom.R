theme_custom <- function(base_size = 11, base_family = "") {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    cli::cli_abort("{.pkg ggplot2} is required for {.fn theme_custom}.", call = NULL)
  }
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.background = ggplot2::element_rect(fill = "white", color = NA),
      plot.background = ggplot2::element_rect(fill = "white", color = NA),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
}
