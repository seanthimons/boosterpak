#' Build the default boosterpak configuration
#'
#' @param root Project root used to derive the project name.
#' @return A list containing the default project configuration.
#' @noRd
default_config <- function(root = ".") {
  list(
    project = list(
      name = basename(normalizePath(root, winslash = "/", mustWork = FALSE))
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

#' Build the explanatory comment for the boosters_version field
#'
#' @return A character vector of TOML comment lines written above
#'   `boosters_version` in `[project]`.
#' @noRd
boosters_version_comment <- function() {
  c(
    "# boosters_version is the boosterpak version this project was last migrated",
    "# with. init() and the upgrade path refresh it; sync() does not. It is not a",
    "# lock. When it is older than the installed boosterpak, run",
    "# boosterpak::upgrade_project() to bring the project up to date."
  )
}

#' Read the boosters_version recorded in boosters.toml
#'
#' @param root Project root.
#' @return The recorded version as a `package_version`, or `NULL` when the
#'   record is missing or invalid or `boosters.toml` cannot be parsed.
#' @noRd
recorded_boosters_version <- function(root = ".") {
  recorded <- tryCatch(
    read_config(root)$project$boosters_version,
    error = function(err) NULL
  )
  if (!is.character(recorded) || length(recorded) != 1) {
    return(NULL)
  }
  tryCatch(package_version(recorded), error = function(err) NULL)
}

#' Record the installed boosterpak version in boosters.toml
#'
#' Sets `[project].boosters_version` to the installed version, adding the
#' explanatory comment when it is missing. The record is only written when it
#' is missing or older than the installed version, so an older boosterpak never
#' downgrades a record that a newer one wrote. Other lines are left unchanged,
#' and the file is rewritten only when its content changes.
#'
#' @param root Project root.
#' @return `TRUE` if `boosters.toml` changed, otherwise `FALSE`, invisibly.
#' @noRd
set_boosters_version <- function(root = ".") {
  path <- boosters_file(root)
  if (!file.exists(path)) {
    cli::cli_abort(
      "{.file boosters.toml} does not exist. Run {.code boosterpak::init()} first.",
      call = NULL
    )
  }
  recorded <- recorded_boosters_version(root)
  if (
    !is.null(recorded) &&
      !recorded < package_version(package_version_string())
  ) {
    return(invisible(FALSE))
  }
  original <- readLines(path, warn = FALSE)
  lines <- original
  comment <- boosters_version_comment()
  version_line <- sprintf('boosters_version = "%s"', package_version_string())
  headers <- grep("^\\s*\\[[^]]+\\]\\s*(#.*)?$", lines)
  project_start <- grep("^\\s*\\[project\\]\\s*(#.*)?$", lines)
  if (length(project_start) > 1) {
    cli::cli_abort(
      "Could not find a unique [project] section in {.file {path}}.",
      call = NULL
    )
  }

  if (length(project_start) == 0) {
    lines <- c(lines, "", "[project]", comment, version_line)
  } else {
    start <- project_start[[1]]
    next_header <- headers[headers > start]
    end <- if (length(next_header) > 0) next_header[[1]] - 1L else length(lines)
    key <- grep("^\\s*boosters_version\\s*=", lines[start:end])
    if (length(key) > 1) {
      cli::cli_abort(
        "Could not safely update [project].boosters_version in {.file {path}}.",
        call = NULL
      )
    }
    if (length(key) == 1) {
      key_idx <- start + key[[1]] - 1L
      lines[[key_idx]] <- version_line
      # A user comment between the explanation and the key does not count as
      # missing, so the explanation is not written a second time.
      has_comment <- all(comment %in% lines[start:(key_idx - 1L)])
      if (!has_comment) {
        lines <- append(lines, comment, after = key_idx - 1L)
      }
    } else {
      last <- start + max(which(nzchar(trimws(lines[start:end])))) - 1L
      lines <- append(lines, c(comment, version_line), after = last)
    }
  }

  if (identical(lines, original)) {
    return(invisible(FALSE))
  }
  writeLines(lines, path, useBytes = TRUE)
  invisible(TRUE)
}

#' Classify the boosters_version record against the installed boosterpak
#'
#' @param root Project root.
#' @return One of `"missing"` (no `boosters_version` key), `"invalid"` (the file
#'   cannot be parsed or the value is not a version), `"older"` (the record is
#'   older than the installed version), `"current"`, or `"newer"`.
#' @noRd
boosters_version_state <- function(root = ".") {
  config <- tryCatch(read_config(root), error = function(err) NULL)
  if (is.null(config)) {
    return("invalid")
  }
  value <- config$project$boosters_version
  if (is.null(value)) {
    return("missing")
  }
  recorded <- if (is.character(value) && length(value) == 1) {
    tryCatch(package_version(value), error = function(err) NULL)
  }
  if (is.null(recorded)) {
    return("invalid")
  }
  installed <- package_version(package_version_string())
  if (recorded < installed) {
    "older"
  } else if (recorded == installed) {
    "current"
  } else {
    "newer"
  }
}

#' Check whether a project was last migrated with an older boosterpak
#'
#' A project is behind when `boosters.toml` exists and its record is missing,
#' unreadable, or older than the installed boosterpak. A record that is newer
#' than the installed version (an older boosterpak run on a newer project) is
#' not treated as behind. A project created with `init(rprofile = "no")`, or
#' with a declined prompt, has no record until a later `init()` completes the
#' `.Rprofile` step, so it counts as behind here.
#'
#' @param root Project root.
#' @return `TRUE` when the record is missing, invalid, or older than the
#'   installed boosterpak, `FALSE` otherwise, including when `boosters.toml`
#'   does not exist.
#' @noRd
project_needs_upgrade <- function(root = ".") {
  if (!file.exists(boosters_file(root))) {
    return(FALSE)
  }
  boosters_version_state(root) %in% c("missing", "invalid", "older")
}

#' Write the default project configuration
#'
#' @param root Project root.
#' @param record_version Whether to record the installed version in
#'   `[project].boosters_version`. `init()` passes `FALSE` for a new project
#'   and records the version itself once the `.Rprofile` step has run.
#' @return The path to `boosters.toml`, invisibly.
#' @noRd
write_default_config <- function(root = ".", record_version = TRUE) {
  path <- boosters_file(root)
  version_lines <- if (record_version) {
    c(
      boosters_version_comment(),
      sprintf('boosters_version = "%s"', package_version_string())
    )
  }
  lines <- c(
    "# boosters.toml - project configuration",
    "# Edit this file directly or use boosterpak::add_pack() / remove_pack().",
    "",
    "[project]",
    sprintf(
      'name = "%s"',
      escape_toml_string(default_config(root)$project$name)
    ),
    version_lines,
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
