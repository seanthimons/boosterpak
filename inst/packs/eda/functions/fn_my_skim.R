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
