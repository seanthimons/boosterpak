#' rlang is needed at runtime by cli
#'
#' `cli::cli_abort()`, `cli::cli_warn()` and `cli::cli_inform()` call rlang,
#' which cli only suggests. boosterpak uses all three, so rlang is declared in
#' Imports; this tag is the import that keeps `R CMD check` from flagging it
#' as unused.
#'
#' @importFrom rlang abort
#' @noRd
NULL
