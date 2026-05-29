scaffold_analysis <- function(dirs = c(
  "data/raw",
  "data/processed",
  "docs",
  "output/figures",
  "R",
  "scratch"
), root = getwd()) {
  if (!requireNamespace("fs", quietly = TRUE)) {
    stop("Package 'fs' is required for scaffold_analysis().", call. = FALSE)
  }

  paths <- fs::path(root, dirs)
  fs::dir_create(paths)
  invisible(paths)
}
