#' Build the default boosterpak configuration
#'
#' @param root Project root used to derive the project name.
#' @return A list containing the default project configuration.
#' @noRd
default_config <- function(root = ".") {
  list(
    project = list(
      name = basename(normalizePath(root, winslash = "/", mustWork = FALSE)),
      boosters_version = package_version_string()
    ),
    packs = list(declared = "core"),
    extras = list(declared = self_install_spec()),
    exclude = list(declared = character()),
    attach = list(
      enabled = TRUE,
      declared = character(),
      exclude = character()
    ),
    settings = list(
      air_toml = TRUE,
      auto_snapshot = TRUE,
      library = "renv"
    )
  )
}

#' Read a boosterpak project configuration
#'
#' @param root Project root.
#' @return The parsed `boosters.toml` configuration.
#' @noRd
read_config <- function(root = ".") {
  path <- boosters_file(root)
  if (!file.exists(path)) {
    cli::cli_abort(
      "{.file boosters.toml} does not exist. Run {.code boosterpak::init()} first.",
      call = NULL
    )
  }
  read_toml_file(path)
}

#' Validate a boosterpak project configuration
#'
#' @param config Parsed boosterpak configuration.
#' @param root Project root used to resolve declared packs and functions.
#' @return `TRUE`, invisibly, or an error if the configuration is invalid.
#' @noRd
validate_config <- function(config, root = ".") {
  config$packs$declared <- toml_string_array(
    config$packs$declared %||% character(),
    "[packs].declared"
  )
  config$extras$declared <- toml_string_array(
    config$extras$declared %||% character(),
    "[extras].declared"
  )
  config$exclude$declared <- toml_string_array(
    config$exclude$declared %||% character(),
    "[exclude].declared"
  )
  validate_attach_config(config)
  validate_config_functions(config, root)

  declared <- config$packs$declared %||% character()
  invisible(lapply(declared, load_pack, root = root))
  invisible(lapply(declared, resolve_pack, root = root))

  settings <- config$settings %||% list()
  if (!is.null(settings$air_toml) && !is.logical(settings$air_toml)) {
    cli::cli_abort(
      "{.field [settings].air_toml} must be {.code true} or {.code false}.",
      call = NULL
    )
  }
  if (!is.null(settings$auto_snapshot) && !is.logical(settings$auto_snapshot)) {
    cli::cli_abort(
      "{.field [settings].auto_snapshot} must be {.code true} or {.code false}.",
      call = NULL
    )
  }
  resolve_library_strategy(config = config)
  if (!is.null(settings$parallel_daemons)) {
    cli::cli_warn(
      "{.field [settings].parallel_daemons} is deprecated; declare the value as a pack setting instead, e.g. {.field [settings.packs.sean-parallel].daemons}."
    )
  }
  validate_pack_settings(settings)

  warn_unknown_keys(config)
  invisible(TRUE)
}

#' Validate project pack settings
#'
#' @param settings Parsed project settings table.
#' @return `TRUE`, invisibly, or an error if a pack settings entry is invalid.
#' @noRd
validate_pack_settings <- function(settings) {
  packs <- settings$packs
  if (is.null(packs)) {
    return(invisible(TRUE))
  }
  if (!is.list(packs) || is.data.frame(packs)) {
    cli::cli_abort(
      "{.field [settings.packs]} must be a TOML table.",
      call = NULL
    )
  }
  invisible(lapply(names(packs), function(name) {
    entry <- packs[[name]]
    if (!is.list(entry) || is.data.frame(entry)) {
      cli::cli_abort(
        "{.field [settings.packs.{name}]} must be a TOML table.",
        call = NULL
      )
    }
  }))
  invisible(TRUE)
}

#' Normalize and validate a TOML string array
#'
#' @param value Parsed TOML value to validate.
#' @param field Field description used in error messages.
#' @return A character vector, with an empty list normalized to `character()`.
#' @noRd
toml_string_array <- function(value, field) {
  if (is.list(value) && length(value) == 0) {
    return(character())
  }
  if (!is.character(value)) {
    cli::cli_abort("{.field {field}} must be a string array.", call = NULL)
  }
  value
}

#' Warn about unknown configuration keys
#'
#' @param config Parsed boosterpak configuration.
#' @return `TRUE`, invisibly.
#' @noRd
warn_unknown_keys <- function(config) {
  known_top <- c(
    "project",
    "packs",
    "extras",
    "exclude",
    "attach",
    "settings",
    "functions"
  )
  unknown <- setdiff(names(config), known_top)
  if (length(unknown) > 0) {
    cli::cli_warn("Unknown top-level key{?s}: {unknown}.")
  }
  known_settings <- c(
    "air_toml",
    "parallel_daemons",
    "auto_snapshot",
    "library",
    "camcorder",
    "packs"
  )
  unknown_settings <- setdiff(
    names(config$settings %||% list()),
    known_settings
  )
  if (length(unknown_settings) > 0) {
    cli::cli_warn("Unknown [settings] key{?s}: {unknown_settings}.")
  }
  invisible(TRUE)
}

#' Write the default project configuration
#'
#' @param root Project root.
#' @return The path to `boosters.toml`, invisibly.
#' @noRd
write_default_config <- function(root = ".") {
  path <- boosters_file(root)
  lines <- c(
    "# boosters.toml - project configuration",
    "# Edit this file directly or use boosterpak::add_pack() / remove_pack().",
    "",
    "[project]",
    sprintf(
      'name = "%s"',
      escape_toml_string(default_config(root)$project$name)
    ),
    sprintf('boosters_version = "%s"', package_version_string()),
    "",
    "[packs]",
    'declared = ["core"]',
    "",
    "[extras]",
    sprintf('declared = ["%s"]', escape_toml_string(self_install_spec())),
    "",
    "[exclude]",
    "declared = []",
    "",
    "[attach]",
    "enabled = true",
    "declared = []",
    "exclude = []",
    "",
    "[functions]",
    "installed = []",
    "",
    "[settings]",
    "air_toml = true",
    "auto_snapshot = true",
    'library = "renv"',
    ""
  )
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}

#' Format a supported pack setting as TOML
#'
#' @param value A scalar string, logical or number, or a character vector.
#' @return A character scalar containing the TOML representation of `value`.
#' @noRd
format_toml_value <- function(value) {
  if (is.character(value) && length(value) == 1) {
    sprintf('"%s"', escape_toml_string(value))
  } else if (is.logical(value) && length(value) == 1) {
    if (isTRUE(value)) "true" else "false"
  } else if (is.numeric(value) && length(value) == 1) {
    as.character(value)
  } else if (is.character(value)) {
    sprintf(
      "[%s]",
      paste(
        sprintf('"%s"', vapply(value, escape_toml_string, character(1))),
        collapse = ", "
      )
    )
  } else {
    cli::cli_abort(
      "Pack settings values must be strings, booleans, numbers, or string arrays.",
      call = NULL
    )
  }
}

#' Ensure a project pack settings section exists
#'
#' @param path Path to `boosters.toml`.
#' @param pack_name Pack name used in the settings table header.
#' @param settings Named list of default pack settings.
#' @return `path`, invisibly.
#' @noRd
ensure_pack_settings_section <- function(path, pack_name, settings) {
  if (length(settings) == 0) {
    return(invisible(path))
  }
  lines <- readLines(path, warn = FALSE)
  header <- sprintf("[settings.packs.%s]", pack_name)
  if (any(trimws(lines) == header)) {
    return(invisible(path))
  }
  entries <- vapply(
    names(settings),
    function(key) sprintf("%s = %s", key, format_toml_value(settings[[key]])),
    character(1)
  )
  writeLines(c(lines, "", header, entries), path, useBytes = TRUE)
  invisible(path)
}

#' Scaffold settings for resolved packs
#'
#' @param names Character vector of pack names whose settings should be
#'   scaffolded.
#' @param root Project root.
#' @return A list with one settings-scaffolding result per resolved pack,
#'   invisibly.
#' @noRd
scaffold_pack_settings <- function(names, root = ".") {
  packs <- unique(unlist(
    lapply(names, resolve_pack_names, root = root),
    use.names = FALSE
  ))
  invisible(lapply(packs, function(pack_name) {
    pack <- load_pack(pack_name, root)
    settings <- pack$settings %||% list()
    if (length(settings) > 0) {
      ensure_pack_settings_section(boosters_file(root), pack_name, settings)
    }
  }))
}

#' Escape a string for a TOML basic string
#'
#' @param x Character vector to escape.
#' @return `x` with double quotes escaped.
#' @noRd
escape_toml_string <- function(x) {
  gsub('"', '\\"', x, fixed = TRUE)
}

#' Resolve boosterpak's self-install specification
#'
#' @param desc Package description metadata.
#' @return A GitHub `owner/repo` installation specification.
#' @noRd
self_install_spec <- function(desc = utils::packageDescription("boosterpak")) {
  remote_type <- desc[["RemoteType"]]
  remote_user <- desc[["RemoteUsername"]] %||% desc[["GithubUsername"]]
  remote_repo <- desc[["RemoteRepo"]] %||% desc[["GithubRepo"]]

  if (
    !is.null(remote_type) &&
      identical(tolower(remote_type), "github") &&
      !is.null(remote_user) &&
      !is.null(remote_repo)
  ) {
    return(sprintf("%s/%s", remote_user, remote_repo))
  }

  "seanthimons/boosterpak"
}
