boosters_file <- function(root = ".") {
  file.path(root, "boosters.toml")
}

boosters_dir <- function(root = ".") {
  file.path(root, "boosters")
}

functions_dir <- function(root = ".") {
  boosters_dir(root)
}

attach_file <- function(root = ".") {
  file.path(boosters_dir(root), "attach.R")
}

function_file <- function(name, root = ".") {
  file.path(functions_dir(root), sprintf("fn_%s.R", name))
}

pack_sidecar_dir <- function(pack_path) {
  file.path(dirname(pack_path), "functions")
}

pack_function_file <- function(pack_path, name) {
  file.path(pack_sidecar_dir(pack_path), sprintf("fn_%s.R", name))
}

pack_is_nested_manifest <- function(pack_path) {
  identical(
    basename(dirname(pack_path)),
    tools::file_path_sans_ext(basename(pack_path))
  )
}

catalog_function_file <- function(name, root = ".") {
  catalog <- function_catalog(root)
  catalog$path[match(name, catalog$name)]
}

project_packs_dir <- function(root = ".") {
  file.path(boosters_dir(root), "packs")
}

user_packs_dir <- function() {
  file.path(tools::R_user_dir("boosters", "config"), "packs")
}

rprofile_line <- function() {
  'if (dir.exists("boosters")) { attach <- file.path("boosters", "attach.R"); if (file.exists(attach)) source(attach); invisible(lapply(list.files("boosters", "^fn_.*\\\\.R$", full.names = TRUE), source)) }'
}

legacy_rprofile_line <- function() {
  'if (dir.exists("boosters")) invisible(lapply(list.files("boosters", "^fn_.*\\\\.R$", full.names = TRUE), source))'
}

package_version_string <- function() {
  as.character(utils::packageVersion("boosterpak"))
}
