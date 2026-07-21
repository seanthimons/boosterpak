#' Resolve whether routine output should be emitted
#'
#' @param verbose Explicit verbosity setting, or `NULL` to follow interactive
#'   mode.
#' @return A logical scalar indicating whether to emit routine output.
#' @noRd
should_emit <- function(verbose = NULL) {
  if (isTRUE(verbose)) {
    return(TRUE)
  }
  if (identical(verbose, FALSE)) {
    return(FALSE)
  }
  interactive()
}

#' Validate a verbosity setting
#'
#' @param verbose Verbosity value to validate.
#' @return `TRUE`, invisibly, or an error if `verbose` is invalid.
#' @noRd
check_verbose <- function(verbose) {
  if (!is.null(verbose) && !isTRUE(verbose) && !identical(verbose, FALSE)) {
    cli::cli_abort("{.arg verbose} must be {.code NULL}, {.code TRUE}, or {.code FALSE}.", call = NULL)
  }
  invisible(TRUE)
}
