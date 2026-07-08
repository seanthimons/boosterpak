write_settings_pack <- function(
  root,
  name = "cfg",
  extends = NULL,
  settings = TRUE
) {
  packs_dir <- file.path(root, "boosters", "packs")
  dir.create(packs_dir, recursive = TRUE, showWarnings = FALSE)
  lines <- c(
    sprintf('name = "%s"', name),
    'description = "Settings pack."',
    "packages = []"
  )
  if (!is.null(extends)) {
    lines <- c(lines, sprintf('extends = ["%s"]', extends))
  }
  if (isTRUE(settings)) {
    lines <- c(
      lines,
      "",
      "[settings]",
      'dirs = ["a", "b"]',
      "retries = 2"
    )
  }
  writeLines(lines, file.path(packs_dir, sprintf("%s.toml", name)))
}

test_that("adding a pack with settings scaffolds a project settings section", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_settings_pack(root)
  path <- file.path(root, "boosters.toml")
  before <- readLines(path, warn = FALSE)

  add_pack("cfg", root = root, sync = FALSE, verbose = FALSE)

  lines <- readLines(path, warn = FALSE)
  expect_true("[settings.packs.cfg]" %in% lines)
  expect_true('dirs = ["a", "b"]' %in% lines)
  expect_true("retries = 2" %in% lines)
  header <- setdiff(before, "declared = []")
  expect_true(all(header[grepl("^\\[|^#", header)] %in% lines))
})

test_that("re-adding a pack preserves edited project settings", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_settings_pack(root)
  path <- file.path(root, "boosters.toml")
  add_pack("cfg", root = root, sync = FALSE, verbose = FALSE)

  lines <- readLines(path, warn = FALSE)
  lines[lines == "retries = 2"] <- "retries = 5"
  writeLines(lines, path)

  remove_pack("cfg", root = root, sync = FALSE, verbose = FALSE)
  add_pack("cfg", root = root, sync = FALSE, verbose = FALSE)

  lines <- readLines(path, warn = FALSE)
  expect_true("retries = 5" %in% lines)
  expect_false("retries = 2" %in% lines)
  expect_equal(sum(lines == "[settings.packs.cfg]"), 1L)
})

test_that("pack_setting resolves project override, pack default, then default", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_settings_pack(root)
  path <- file.path(root, "boosters.toml")
  add_pack("cfg", root = root, sync = FALSE, verbose = FALSE)

  lines <- readLines(path, warn = FALSE)
  lines[lines == "retries = 2"] <- "retries = 5"
  writeLines(lines, path)

  expect_equal(pack_setting("cfg", "retries", root = root), 5L)
  expect_equal(pack_setting("cfg", "dirs", root = root), c("a", "b"))

  lines <- readLines(path, warn = FALSE)
  section <- match("[settings.packs.cfg]", lines)
  lines <- lines[seq_len(section - 1)]
  writeLines(lines, path)

  expect_equal(pack_setting("cfg", "retries", root = root), 2L)
  expect_equal(
    pack_setting("cfg", "missing", default = "x", root = root),
    "x"
  )
  expect_equal(pack_setting("nope", "k", default = 1L, root = root), 1L)
})

test_that("packs without settings do not scaffold a section", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_settings_pack(root, settings = FALSE)
  path <- file.path(root, "boosters.toml")

  add_pack("cfg", root = root, sync = FALSE, verbose = FALSE)

  expect_false(any(grepl(
    "[settings.packs",
    readLines(path, warn = FALSE),
    fixed = TRUE
  )))
})

test_that("scaffolded settings sections pass config validation", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_settings_pack(root)
  add_pack("cfg", root = root, sync = FALSE, verbose = FALSE)

  expect_silent(boosterpak:::validate_config(
    boosterpak:::read_config(root),
    root
  ))
})

test_that("adding a pack scaffolds settings for extended packs too", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_settings_pack(root)
  write_settings_pack(root, name = "child", extends = "cfg", settings = FALSE)
  path <- file.path(root, "boosters.toml")

  add_pack("child", root = root, sync = FALSE, verbose = FALSE)

  expect_true("[settings.packs.cfg]" %in% readLines(path, warn = FALSE))
})
