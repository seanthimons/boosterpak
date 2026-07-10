enable_duckdb_connection_pane <- function(enabled = TRUE) {
  options("duckdb.enable_rstudio_connection_pane" = isTRUE(enabled))
  invisible(getOption("duckdb.enable_rstudio_connection_pane"))
}

enable_duckdb_connection_pane(TRUE)

