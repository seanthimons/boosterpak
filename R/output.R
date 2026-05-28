should_emit <- function(verbose = NULL) {
  if (isTRUE(verbose)) {
    return(TRUE)
  }
  if (identical(verbose, FALSE)) {
    return(FALSE)
  }
  interactive()
}

check_verbose <- function(verbose) {
  if (!is.null(verbose) && !isTRUE(verbose) && !identical(verbose, FALSE)) {
    cli::cli_abort("{.arg verbose} must be {.code NULL}, {.code TRUE}, or {.code FALSE}.", call = NULL)
  }
  invisible(TRUE)
}
