scaffold_analysis <- function(dirs = c(
  "data/raw",
  "data/processed",
  "docs",
  "output/figures",
  "R",
  "scratch"
)) {
  if (!requireNamespace("fs", quietly = TRUE)) {
    stop("Package 'fs' is required for scaffold_analysis().", call. = FALSE)
  }
  if (!requireNamespace("here", quietly = TRUE)) {
    stop("Package 'here' is required for scaffold_analysis().", call. = FALSE)
  }

  paths <- here::here(dirs)
  fs::dir_create(paths)
  invisible(paths)
}
