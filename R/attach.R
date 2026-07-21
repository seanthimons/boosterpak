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

#' Resolve Packages Attached by a Pack
#'
#' @param pack Parsed pack data.
#' @return A character vector of package names to attach.
#' @noRd
pack_attach_packages <- function(pack) {
  field <- sprintf("%s attach", pack$.__path__)
  attach <- pack$attach
  packages <- toml_string_array(pack$packages %||% character(), sprintf("%s packages", pack$.__path__))
  if (is.null(attach) || identical(attach, TRUE)) {
    packages
  } else if (identical(attach, FALSE)) {
    character()
  } else {
    toml_string_array(attach, field)
  }
}

#' Resolve Inherited Pack Attachments
#'
#' @param name Pack name.
#' @param root Project root.
#' @param stack Character vector of pack names already being resolved, used to
#'   detect inheritance cycles.
#' @return A character vector of unique package names to attach.
#' @noRd
resolve_pack_attach <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_attach <- unlist(lapply(parents, resolve_pack_attach, root = root, stack = c(stack, name)), use.names = FALSE)
  unique(c(parent_attach, pack_attach_packages(pack)))
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
#' @return A character vector of package names to attach at startup.
#' @noRd
resolve_config_attach_packages <- function(config, root = ".") {
  validate_attach_config(config)
  attach <- config$attach %||% list()
  if (identical(attach$enabled, FALSE)) {
    return(character())
  }

  declared_packs <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  pack_packages <- unlist(lapply(declared_packs, resolve_pack_attach, root = root), use.names = FALSE)
  declared_attach <- toml_string_array(attach$declared %||% character(), "[attach].declared")
  attach_exclude <- toml_string_array(attach$exclude %||% character(), "[attach].exclude")
  install_exclude <- toml_string_array(config$exclude$declared %||% character(), "[exclude].declared")

  packages <- unique(c(pack_packages, declared_attach))
  packages <- setdiff(packages, setdiff(unique(workflow_packages(config)), declared_attach))
  packages <- setdiff(packages, unique(c(attach_exclude, install_exclude)))
  packages
}

#' Write startup package attachment calls
#'
#' Resolves package attach intent from `boosters.toml` and writes a managed
#' `boosters/attach.R` file containing static `library()` calls. Installation
#' intent remains controlled by pack `packages`; attachment controls only what
#' is loaded at startup by the optional `.Rprofile` hook.
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

  packages <- resolve_config_attach_packages(config, root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(attach_file_lines(packages), path, useBytes = TRUE)
  if (should_emit(verbose)) {
    cli::cli_alert_success("Wrote {.file boosters/attach.R} with {length(packages)} package{?s}.")
  }
  invisible(normalizePath(path, winslash = "/", mustWork = FALSE))
}

#' Build the Managed Attachment File
#'
#' @param packages Character vector of package names to attach.
#' @return A character vector containing the managed attachment file lines.
#' @noRd
attach_file_lines <- function(packages) {
  c(
    "# Generated by boosterpak::write_attach(); do not edit by hand.",
    "# Configure package attachment in boosters.toml.",
    "",
    sprintf("library(%s)", packages),
    ""
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
