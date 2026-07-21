#' Locate the project configuration file
#'
#' @param root Project root.
#' @return The path to `boosters.toml`.
#' @noRd
boosters_file <- function(root = ".") {
  file.path(root, "boosters.toml")
}

#' Locate the project booster directory
#'
#' @param root Project root.
#' @return The path to the project's `boosters` directory.
#' @noRd
boosters_dir <- function(root = ".") {
  file.path(root, "boosters")
}

#' Locate the project function directory
#'
#' @param root Project root.
#' @return The directory containing project function files.
#' @noRd
functions_dir <- function(root = ".") {
  boosters_dir(root)
}

#' Locate the generated attach file
#'
#' @param root Project root.
#' @return The path to the project's generated `attach.R` file.
#' @noRd
attach_file <- function(root = ".") {
  file.path(boosters_dir(root), "attach.R")
}

#' Locate a project function file
#'
#' @param name Function name.
#' @param root Project root.
#' @return The path to the corresponding project function file.
#' @noRd
function_file <- function(name, root = ".") {
  file.path(functions_dir(root), sprintf("fn_%s.R", name))
}

#' Locate a pack function sidecar
#'
#' @param pack_path Path to a pack manifest.
#' @return The path to the pack's function sidecar directory.
#' @noRd
pack_sidecar_dir <- function(pack_path) {
  file.path(dirname(pack_path), "functions")
}

#' Locate a function within a pack
#'
#' @param pack_path Path to a pack manifest.
#' @param name Function name.
#' @return The path to the corresponding pack function file.
#' @noRd
pack_function_file <- function(pack_path, name) {
  file.path(pack_sidecar_dir(pack_path), sprintf("fn_%s.R", name))
}

#' Test whether a pack manifest uses nested layout
#'
#' @param pack_path Path to a pack manifest.
#' @return A single logical value indicating whether the manifest is nested.
#' @noRd
pack_is_nested_manifest <- function(pack_path) {
  identical(
    basename(dirname(pack_path)),
    tools::file_path_sans_ext(basename(pack_path))
  )
}

#' Locate a catalog function file
#'
#' @param name Function name.
#' @param root Project root.
#' @return Catalog file paths corresponding to `name`, with `NA` for no match.
#' @noRd
catalog_function_file <- function(name, root = ".") {
  catalog <- function_catalog(root)
  catalog$path[match(name, catalog$name)]
}

#' Locate the project pack directory
#'
#' @param root Project root.
#' @return The path to the project's pack directory.
#' @noRd
project_packs_dir <- function(root = ".") {
  file.path(boosters_dir(root), "packs")
}

#' Locate the user pack directory
#'
#' @return The path to the user-level pack directory.
#' @noRd
user_packs_dir <- function() {
  file.path(tools::R_user_dir("boosters", "config"), "packs")
}

#' Build the current startup hook
#'
#' @return A single string containing the current `.Rprofile` startup hook.
#' @noRd
rprofile_line <- function() {
  'if (dir.exists("boosters")) { attach <- file.path("boosters", "attach.R"); if (file.exists(attach)) source(attach); invisible(lapply(list.files("boosters", "^fn_.*\\\\.R$", full.names = TRUE), source)) }'
}

#' Build the legacy startup hook
#'
#' @return A single string containing the legacy `.Rprofile` startup hook.
#' @noRd
legacy_rprofile_line <- function() {
  'if (dir.exists("boosters")) invisible(lapply(list.files("boosters", "^fn_.*\\\\.R$", full.names = TRUE), source))'
}

#' Get the installed boosterpak version
#'
#' @return The installed package version as a string.
#' @noRd
package_version_string <- function() {
  as.character(utils::packageVersion("boosterpak"))
}
