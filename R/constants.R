boosters_file <- function(root = ".") {
  file.path(root, "boosters.toml")
}

boosters_dir <- function(root = ".") {
  file.path(root, "boosters")
}

project_packs_dir <- function(root = ".") {
  file.path(boosters_dir(root), "packs")
}

user_packs_dir <- function() {
  file.path(tools::R_user_dir("boosters", "config"), "packs")
}

rprofile_line <- function() {
  'if (dir.exists("boosters")) invisible(lapply(list.files("boosters", "^fn_.*\\\\.R$", full.names = TRUE), source))'
}

package_version_string <- function() {
  as.character(utils::packageVersion("boosterpak"))
}
