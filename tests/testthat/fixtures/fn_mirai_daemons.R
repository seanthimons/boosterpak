mirai_daemons <- function(n = NULL, ..., dry_run = FALSE) {
  dots <- list(...)
  resolved <- resolve_mirai_daemon_count(n)

  if (isTRUE(dry_run)) {
    return(list(
      n = resolved$n,
      source = resolved$source,
      args = dots,
      dry_run = TRUE
    ))
  }

  if (!requireNamespace("mirai", quietly = TRUE)) {
    stop("Package 'mirai' is required to start mirai daemons.", call. = FALSE)
  }

  do.call(mirai::daemons, c(list(n = resolved$n), dots))
}

resolve_mirai_daemon_count <- function(n = NULL) {
  if (!is.null(n)) {
    return(list(
      n = normalize_mirai_daemon_count(n, "n", allow_zero = TRUE),
      source = "n"
    ))
  }

  setting <- read_mirai_daemon_setting()
  list(
    n = normalize_mirai_daemon_count(
      setting$value,
      setting$source,
      allow_zero = FALSE
    ),
    source = setting$source
  )
}

read_mirai_daemon_setting <- function() {
  if (!requireNamespace("boosterpak", quietly = TRUE)) {
    return(list(value = "auto", source = "default"))
  }
  value <- boosterpak::pack_setting("sean-parallel", "daemons")
  if (is.null(value)) {
    return(list(value = "auto", source = "default"))
  }
  list(value = value, source = "[settings.packs.sean-parallel].daemons")
}

normalize_mirai_daemon_count <- function(value, field, allow_zero = FALSE) {
  if (identical(value, "auto")) {
    return(resolve_auto_mirai_daemons())
  }

  minimum <- if (isTRUE(allow_zero)) 0L else 1L
  ok_number <- is.numeric(value) &&
    length(value) == 1 &&
    is.finite(value) &&
    value == as.integer(value) &&
    value >= minimum

  if (!ok_number) {
    if (isTRUE(allow_zero)) {
      stop(
        sprintf("%s must be \"auto\" or a non-negative integer.", field),
        call. = FALSE
      )
    }
    stop(
      sprintf("%s must be \"auto\" or a positive integer.", field),
      call. = FALSE
    )
  }

  as.integer(value)
}

resolve_auto_mirai_daemons <- function() {
  cores <- tryCatch(
    parallel::detectCores(logical = TRUE),
    error = function(err) NA_integer_
  )
  if (
    !is.numeric(cores) ||
      length(cores) != 1 ||
      is.na(cores) ||
      !is.finite(cores) ||
      cores < 2
  ) {
    return(1L)
  }
  max(1L, as.integer(cores) - 1L)
}
