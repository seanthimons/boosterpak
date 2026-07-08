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
      parallel_daemons = "auto",
      auto_snapshot = TRUE
    )
  )
}

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
  validate_config_functions(config)

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
  if (!is.null(settings$parallel_daemons)) {
    ok_auto <- identical(settings$parallel_daemons, "auto")
    ok_number <- is.numeric(settings$parallel_daemons) &&
      length(settings$parallel_daemons) == 1 &&
      settings$parallel_daemons >= 1 &&
      settings$parallel_daemons == as.integer(settings$parallel_daemons)
    if (!ok_auto && !ok_number) {
      cli::cli_abort(
        "{.field [settings].parallel_daemons} must be {.val auto} or a positive integer.",
        call = NULL
      )
    }
  }

  warn_unknown_keys(config)
  invisible(TRUE)
}

toml_string_array <- function(value, field) {
  if (is.list(value) && length(value) == 0) {
    return(character())
  }
  if (!is.character(value)) {
    cli::cli_abort("{.field {field}} must be a string array.", call = NULL)
  }
  value
}

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
    "camcorder"
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
    'parallel_daemons = "auto"',
    "auto_snapshot = true",
    ""
  )
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}

escape_toml_string <- function(x) {
  gsub('"', '\\"', x, fixed = TRUE)
}

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
