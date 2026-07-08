#' Report boosterpak project status
#'
#' @param root Project root.
#' @param verbose Whether to print routine summaries.
#' @return A list describing project status, invisibly. Includes config
#'   validity, declared and resolved packs, package and missing-package counts,
#'   attach state, materialized function drift/missing counts, pack catalog
#'   counts, renv state, lockfile presence, and `.Rprofile` hook state.
#' @export
status <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config_exists <- file.exists(boosters_file(root))
  valid <- FALSE
  packages <- character()
  packs <- character()
  resolved_packs <- character()
  extras <- character()
  exclude <- character()
  functions <- character()
  function_status <- function_status_frame()
  attach_enabled <- TRUE
  attach_packages <- character()
  parse_error <- NULL
  if (config_exists) {
    config <- tryCatch(
      read_config(root),
      error = function(err) {
        parse_error <<- conditionMessage(err)
        NULL
      }
    )
    valid <- !is.null(config) &&
      tryCatch(
        {
          validate_config(config, root)
          TRUE
        },
        error = function(err) {
          parse_error <<- conditionMessage(err)
          FALSE
        }
      )
    if (isTRUE(valid)) {
      packages <- resolve_config_packages(config, root)
      packs <- config$packs$declared %||% character()
      resolved_packs <- resolve_config_pack_names(config, root)
      extras <- toml_string_array(
        config$extras$declared %||% character(),
        "[extras].declared"
      )
      exclude <- toml_string_array(
        config$exclude$declared %||% character(),
        "[exclude].declared"
      )
      functions <- installed_functions(config)
      function_status <- collect_function_status(functions, root)
      attach_enabled <- !identical((config$attach %||% list())$enabled, FALSE)
      attach_packages <- resolve_config_attach_packages(config, root)
    }
  }
  pack_catalog <- available_packs(root)
  missing <- missing_packages(packages, root)
  out <- list(
    config_exists = config_exists,
    config_valid = valid,
    packs = packs,
    resolved_packs = resolved_packs,
    extras = extras,
    exclude = exclude,
    packages = packages,
    package_count = length(packages),
    missing_packages = missing,
    missing_package_count = length(missing),
    functions = functions,
    function_status = function_status,
    function_count = length(functions),
    function_missing_count = sum(!function_status$exists),
    function_drift_count = sum(
      function_status$exists & !function_status$matches
    ),
    attach_enabled = attach_enabled,
    attach_packages = attach_packages,
    attach_package_count = length(attach_packages),
    attach_file_exists = file.exists(attach_file(root)),
    pack_catalog = pack_catalog,
    pack_counts = stats::setNames(
      vapply(
        c("project", "user", "builtin"),
        function(scope) sum(pack_catalog$scope == scope),
        integer(1)
      ),
      c("project", "user", "builtin")
    ),
    renv_active = is_project_renv_active(root),
    lockfile_exists = file.exists(file.path(root, "renv.lock")),
    rprofile_hook = has_rprofile_line(root),
    config_error = parse_error
  )
  if (should_emit(verbose)) {
    cli::cli_h1("boosterpak status")
    cli::cli_li(
      "boosters.toml: {if (out$config_exists) 'present' else 'missing'}"
    )
    cli::cli_li("config valid: {out$config_valid}")
    cli::cli_li("renv active: {out$renv_active}")
    cli::cli_li(
      "renv.lock: {if (out$lockfile_exists) 'present' else 'missing'}"
    )
    cli::cli_li(".Rprofile hook: {out$rprofile_hook}")
    cli::cli_li("declared packs: {format_status_values(out$packs)}")
    cli::cli_li(
      "resolved packages: {out$package_count} ({out$missing_package_count} missing)"
    )
    cli::cli_li(
      "materialized functions: {out$function_count} ({out$function_missing_count} missing, {out$function_drift_count} drifted)"
    )
    cli::cli_li(
      "startup attach: {out$attach_enabled}, {out$attach_package_count} package{?s}, file {if (out$attach_file_exists) 'present' else 'missing'}"
    )
    cli::cli_li(
      "pack catalog: {out$pack_counts[['project']]} project, {out$pack_counts[['user']]} user, {out$pack_counts[['builtin']]} built-in"
    )
  }
  invisible(out)
}

function_status_frame <- function() {
  data.frame(
    name = character(),
    path = character(),
    exists = logical(),
    matches = logical(),
    stringsAsFactors = FALSE
  )
}

collect_function_status <- function(functions, root) {
  rows <- lapply(functions, function(name) {
    local <- function_file(name, root)
    package <- catalog_function_file(name, root)
    exists <- file.exists(local)
    matches <- exists &&
      identical(
        readLines(local, warn = FALSE),
        readLines(package, warn = FALSE)
      )
    data.frame(
      name = name,
      path = local,
      exists = exists,
      matches = matches,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows) %||% function_status_frame()
}

format_status_values <- function(values) {
  if (length(values) == 0) {
    "(none)"
  } else {
    paste(values, collapse = ", ")
  }
}
