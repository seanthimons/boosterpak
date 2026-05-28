#' Negated value matching
#'
#' @param x Values to match.
#' @param table Values to match against.
#' @return Logical vector indicating values not found in `table`.
#' @export
`%ni%` <- function(x, table) {
  !(x %in% table)
}

#' Geometric mean
#'
#' @param x Numeric vector.
#' @param na.rm Whether to remove missing values.
#' @return Geometric mean of positive values.
#' @export
geo_mean <- function(x, na.rm = FALSE) {
  if (na.rm) {
    x <- x[!is.na(x)]
  }
  if (any(is.na(x))) {
    return(NA_real_)
  }
  if (length(x) == 0 || any(x <= 0)) {
    return(NA_real_)
  }
  exp(mean(log(x)))
}

#' Custom ggplot2 theme
#'
#' @param base_size Base font size.
#' @param base_family Base font family.
#' @return A ggplot2 theme.
#' @export
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

#' Skimr preset with numeric helpers
#'
#' @param data Data frame to skim.
#' @param ... Additional arguments passed to `skimr::skim()`.
#' @return A skimr summary.
#' @export
my_skim <- function(data, ...) {
  if (!requireNamespace("skimr", quietly = TRUE)) {
    cli::cli_abort("{.pkg skimr} is required for {.fn my_skim}.", call = NULL)
  }
  skimr::skim_with(
    numeric = skimr::sfl(
      geo_mean = ~ geo_mean(.x, na.rm = TRUE),
      hist = skimr::inline_hist
    ),
    append = TRUE
  )
  skimr::skim(data, ...)
}
