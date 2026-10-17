#' Validate Attachment Configuration
#'
#' @param config Parsed project configuration.
#' @return `TRUE`, invisibly.
#' @noRd
validate_attach_config <- function(config) {
  attach <- config$attach %||% list()
  if (!is.null(attach$enabled) && !is.logical(attach$enabled)) {
    cli::cli_abort("{.field [attach].enabled} must be {.code true} or {.code false}.", call = NULL)
  }
  attach$declared <- toml_string_array(attach$declared %||% character(), "[attach].declared")
  attach$exclude <- toml_string_array(attach$exclude %||% character(), "[attach].exclude")
  invisible(TRUE)
}

#' Validate a Pack Attachment Declaration
#'
#' @param value Pack attachment declaration to validate.
#' @param field Field label used in validation errors.
#' @return `TRUE`, invisibly.
#' @noRd
validate_pack_attach <- function(value, field) {
  if (is.null(value)) {
    return(invisible(TRUE))
  }
  if (is.logical(value) && length(value) == 1) {
    return(invisible(TRUE))
  }
  toml_string_array(value, field)
  invisible(TRUE)
}

#' Validate a Pack Attach Mode
#'
#' @param value Pack `attach_mode` value to validate, or `NULL` when the key is
#'   absent.
#' @param field Field label used in validation errors.
#' @return `TRUE`, invisibly.
#' @noRd
validate_pack_attach_mode <- function(value, field) {
  if (is.null(value)) {
    return(invisible(TRUE))
  }
  if (!is.character(value) || length(value) != 1 || !value %in% c("always", "interactive")) {
    cli::cli_abort(
      "{.field {field}} must be {.val always} or {.val interactive}.",
      call = NULL
    )
  }
  invisible(TRUE)
}

#' Resolve Packages Attached by a Pack
#'
#' @param pack Parsed pack data.
#' @return A character vector of package names to attach.
#' @noRd
pack_attach_packages <- function(pack) {
  field <- sprintf("%s attach", pack$.__path__)
  # [[ ]] matches exactly. `$` would partially match `attach_mode` when the
  # pack sets only that key.
  attach <- pack[["attach"]]
  packages <- toml_string_array(pack$packages %||% character(), sprintf("%s packages", pack$.__path__))
  if (is.null(attach) || identical(attach, TRUE)) {
    packages
  } else if (identical(attach, FALSE)) {
    character()
  } else {
    toml_string_array(attach, field)
  }
}

#' Read a Pack Attach Mode
#'
#' @param pack Parsed pack data.
#' @return `"interactive"` when the pack sets `attach_mode = "interactive"`,
#'   otherwise `"always"`.
#' @noRd
pack_attach_mode <- function(pack) {
  pack[["attach_mode"]] %||% "always"
}

#' Get Workflow Package Names
#'
#' @param config Parsed project configuration.
#' @return A character vector of boosterpak workflow package names.
#' @noRd
workflow_packages <- function(config) {
  c(
    "pak",
    "renv",
    "boosterpak",
    vapply(
      toml_string_array(config$extras$declared %||% character(), "[extras].declared"),
      package_name_from_spec,
      character(1),
      USE.NAMES = FALSE
    )
  )
}

#' Resolve Project Attachment Packages
#'
#' @param config Parsed project configuration.
#' @param root Project root.
#' @return A character vector of every package to attach, at startup or only in
#'   interactive sessions. Packages from `attach_mode = "interactive"` packs are
#'   included; see `resolve_config_attach_sources()` for their mode.
#' @noRd
resolve_config_attach_packages <- function(config, root = ".") {
  resolve_config_attach_sources(config, root)$package
}

#' Write startup package attachment calls
#'
#' Resolves package attach intent from `boosters.toml` and writes a managed
#' `boosters/attach.R` file. The file attaches each package independently: a
#' package that is not installed is reported in one summary line, and the rest
#' still attach. Installation intent remains controlled by pack `packages`;
#' attachment controls only what is loaded at startup by the optional
#' `.Rprofile` hook. Packages from packs with `attach_mode = "interactive"` are
#' attached only when `interactive()` is true, so workers and non-interactive
#' runs skip them.
#'
#' @param root Project root.
#' @param verbose Whether to print routine summaries.
#' @return Path to `boosters/attach.R`, invisibly.
#' @export
write_attach <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- read_config(root)
  validate_config(config, root)
  path <- attach_file(root)

  if (identical((config$attach %||% list())$enabled, FALSE)) {
    if (is_managed_attach_file(path)) {
      unlink(path)
    }
    if (should_emit(verbose)) {
      cli::cli_alert_info("Package attachment disabled; removed managed {.file boosters/attach.R}.")
    }
    return(invisible(normalizePath(path, winslash = "/", mustWork = FALSE)))
  }

  attached <- resolve_config_attach_sources(config, root)
  packages <- attached$package
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    attach_file_lines(
      packages[!attached$interactive],
      interactive_packages = packages[attached$interactive]
    ),
    path,
    useBytes = TRUE
  )
  if (should_emit(verbose)) {
    cli::cli_alert_success("Wrote {.file boosters/attach.R} with {length(packages)} package{?s}.")
  }
  invisible(normalizePath(path, winslash = "/", mustWork = FALSE))
}

#' Source the Managed Attachment File
#'
#' Sources `boosters/attach.R` so declared packages are available immediately
#' in the current R session.
#'
#' @param root Project root.
#' @param verbose Whether to print routine summaries.
#' @return `TRUE` invisibly when an attachment file was sourced, otherwise
#'   `FALSE` invisibly.
#' @noRd
source_attach <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  path <- attach_file(root)
  if (!file.exists(path)) {
    return(invisible(FALSE))
  }

  sys.source(path, envir = globalenv())
  if (should_emit(verbose)) {
    cli::cli_alert_success("Sourced {.file boosters/attach.R} in the current R session.")
  }
  invisible(TRUE)
}

#' Build the Managed Attachment File
#'
#' The file runs from `.Rprofile` before boosterpak is loaded, so it does not
#' call any boosterpak function. Each package is attached on its own: a missing
#' package is counted, not fatal. The whole body is wrapped in `tryCatch()` so
#' an error cannot stop the `boosters/fn_*.R` files that the same startup hook
#' sources next. The `library()` calls stay literal so `renv::dependencies()`
#' still finds them. Interactive-only packages get the same calls inside an
#' `if (interactive())` block.
#'
#' @param packages Character vector of package names to attach on every start.
#' @param interactive_packages Character vector of package names to attach only
#'   when `interactive()` is true.
#' @return A character vector containing the managed attachment file lines.
#' @noRd
attach_file_lines <- function(packages, interactive_packages = character()) {
  header <- c(
    "# Generated by boosterpak::write_attach(); do not edit by hand.",
    "# Configure package attachment in boosters.toml.",
    ""
  )
  if (length(packages) == 0 && length(interactive_packages) == 0) {
    return(header)
  }

  calls <- attach_package_calls(packages)
  if (length(interactive_packages) > 0) {
    calls <- c(
      calls,
      "  if (interactive()) {",
      attach_package_calls(interactive_packages, indent = "    "),
      "  }"
    )
  }
  c(
    header,
    "tryCatch(local({",
    "  .missing <- character()",
    calls,
    paste0(
      "  if (length(.missing) > 0L) message(sprintf(",
      "\"boosterpak: %d attach package%s not available or failed to load (%s). Run renv::restore() if they are not installed.\", ",
      "length(.missing), if (length(.missing) == 1L) \"\" else \"s\", ",
      "paste(.missing, collapse = \", \")))"
    ),
    "}), error = function(err) message(\"boosterpak: package attachment failed: \", conditionMessage(err)))",
    ""
  )
}

#' Build the Per-Package Attachment Calls
#'
#' @param packages Character vector of package names.
#' @param indent Indentation prefix for each generated line.
#' @return A character vector with one guarded `library()` call per package.
#' @noRd
attach_package_calls <- function(packages, indent = "  ") {
  sprintf(
    paste0(
      indent,
      'if (requireNamespace("%s", quietly = TRUE)) ',
      'tryCatch(library(%s), error = function(err) .missing <<- c(.missing, "%s")) ',
      'else .missing <- c(.missing, "%s")'
    ),
    packages,
    packages,
    packages,
    packages
  )
}

#' Check for a Managed Attachment File
#'
#' @param path Path to a potential managed attachment file.
#' @return `TRUE` if `path` exists and begins with the boosterpak management
#'   marker.
#' @noRd
is_managed_attach_file <- function(path) {
  file.exists(path) &&
    length(readLines(path, warn = FALSE, n = 1)) == 1 &&
    identical(readLines(path, warn = FALSE, n = 1), "# Generated by boosterpak::write_attach(); do not edit by hand.")
}

#' Build Attachment Origin Rows
#'
#' @param package Character vector of package names.
#' @param pack A single pack label, or one label per package.
#' @param interactive_only Logical value, or one value per package, that is
#'   `TRUE` when the package attaches only in interactive sessions.
#' @return A data frame with `package`, `pack`, and `interactive` columns, one
#'   row per package.
#' @noRd
attach_origin_rows <- function(package, pack, interactive_only = FALSE) {
  data.frame(
    package = as.character(package),
    pack = rep_len(as.character(pack), length(package)),
    interactive = rep_len(as.logical(interactive_only), length(package)),
    stringsAsFactors = FALSE
  )
}

#' Trace Attachment Requests Through a Pack Tree
#'
#' Walks the `extends` tree and records which pack asked for each package. Each
#' pack's own `attach_mode` applies to the packages that pack contributes, so
#' an inherited package keeps the mode of the pack that declares it.
#'
#' @param name Pack name.
#' @param root Project root.
#' @param stack Character vector of pack names already being resolved, used to
#'   detect inheritance cycles.
#' @return A data frame with `package`, `pack`, and `interactive` columns. A
#'   package can appear once per pack that requests it.
#' @noRd
pack_attach_origins <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_rows <- lapply(parents, pack_attach_origins, root = root, stack = c(stack, name))
  own_rows <- attach_origin_rows(
    pack_attach_packages(pack),
    name,
    interactive_only = identical(pack_attach_mode(pack), "interactive")
  )
  do.call(rbind, c(parent_rows, list(own_rows)))
}

#' Resolve Startup Attachment Packages With Their Sources
#'
#' This is the one place that decides which packages attach. It walks the
#' declared packs and `[attach].declared`, then applies the `[attach].exclude`,
#' `[exclude].declared`, and workflow-package filters. Each remaining package is
#' labeled with the packs that requested it. Packages named in
#' `[attach].declared` are labeled `"[attach].declared"`.
#'
#' A package is `interactive` only when every request for it comes from a pack
#' with `attach_mode = "interactive"`. One unconditional request makes it
#' attach on every R start.
#'
#' @param config Parsed project configuration.
#' @param root Project root.
#' @return A data frame with `package`, `pack`, and `interactive` columns, one
#'   row per attached package. `pack` lists the contributing packs, comma
#'   separated. `interactive` is `TRUE` for packages that attach only in
#'   interactive sessions. The data frame has no rows when attachment is
#'   disabled or nothing attaches.
#' @noRd
resolve_config_attach_sources <- function(config, root = ".") {
  validate_attach_config(config)
  attach <- config$attach %||% list()
  if (identical(attach$enabled, FALSE)) {
    return(attach_origin_rows(character(), character(), logical()))
  }

  declared_packs <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  declared_attach <- toml_string_array(attach$declared %||% character(), "[attach].declared")
  attach_exclude <- toml_string_array(attach$exclude %||% character(), "[attach].exclude")
  install_exclude <- toml_string_array(config$exclude$declared %||% character(), "[exclude].declared")

  origins <- do.call(
    rbind,
    c(
      lapply(declared_packs, pack_attach_origins, root = root),
      list(attach_origin_rows(declared_attach, "[attach].declared"))
    )
  )
  packages <- unique(origins$package)
  packages <- setdiff(packages, setdiff(unique(workflow_packages(config)), declared_attach))
  packages <- setdiff(packages, unique(c(attach_exclude, install_exclude)))

  labels <- vapply(
    packages,
    function(package) {
      paste(unique(origins$pack[origins$package == package]), collapse = ", ")
    },
    character(1),
    USE.NAMES = FALSE
  )
  interactive_only <- vapply(
    packages,
    function(package) all(origins$interactive[origins$package == package]),
    logical(1),
    USE.NAMES = FALSE
  )
  attach_origin_rows(packages, labels, interactive_only)
}
