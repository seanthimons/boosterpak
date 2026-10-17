test_that("add_pack and remove_pack preserve unrelated TOML comments", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(c("# keep me", lines, "[extra_section]", "value = 1"), path)

  suppressWarnings(add_pack("example", root = root, sync = FALSE, verbose = FALSE))
  config <- boosterpak:::read_config(root)
  expect_true("example" %in% config$packs$declared)
  expect_true("# keep me" %in% readLines(path, warn = FALSE))
  expect_true("[extra_section]" %in% readLines(path, warn = FALSE))

  suppressWarnings(remove_pack("example", root = root, sync = FALSE, verbose = FALSE))
  config <- boosterpak:::read_config(root)
  expect_false("example" %in% config$packs$declared)
  expect_true("# keep me" %in% readLines(path, warn = FALSE))
})

test_that("eager add_pack preflight leaves TOML unchanged when renv is inactive", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  before <- readLines(path, warn = FALSE)

  expect_error(
    add_pack("example", root = root, sync = TRUE, verbose = FALSE),
    "No active project-local renv library"
  )

  expect_equal(readLines(path, warn = FALSE), before)
})

test_that("multi-line pack declarations fail clearly instead of being corrupted", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  packs_section <- grep("^\\[packs\\]$", lines)
  target <- packs_section + grep("^declared =", lines[(packs_section + 1):length(lines)])[1]
  lines <- append(lines[-target], c("declared = [", '  "core",', "]"), after = target - 1)
  writeLines(lines, path)
  before <- readLines(path, warn = FALSE)

  expect_error(
    add_pack("example", root = root, sync = FALSE, verbose = FALSE),
    "multi-line"
  )
  expect_equal(readLines(path, warn = FALSE), before)
})

test_that("add_pack passes hydrate opt-out through to sync", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  hydrate_value <- NULL

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    sync = function(mode = c("apply", "restore"), root = ".", hydrate = TRUE, verbose = NULL, ...) {
      hydrate_value <<- hydrate
    },
    .package = "boosterpak"
  )

  add_pack("example", root = root, sync = TRUE, hydrate = FALSE, verbose = FALSE)

  expect_false(hydrate_value)
})

test_that("eager add_pack supports the active-library strategy", {
  root <- withr::local_tempdir()
  active_lib <- file.path(root, "active-library")
  dir.create(active_lib)
  old_libpaths <- .libPaths()
  withr::defer(.libPaths(old_libpaths))
  .libPaths(c(active_lib, old_libpaths))
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  used_library <- NULL

  local_mocked_bindings(
    sync = function(mode = c("apply", "restore"), root = ".", hydrate = TRUE, verbose = NULL, library = NULL) {
      used_library <<- library
    },
    .package = "boosterpak"
  )

  add_pack(
    "example",
    root = root,
    sync = TRUE,
    verbose = FALSE,
    library = "active"
  )

  expect_identical(used_library, "active")
  expect_true("example" %in% boosterpak:::read_config(root)$packs$declared)
})

write_removal_pack <- function(root, name, packages = "boostertestpkg", extends = NULL) {
  packs_dir <- file.path(root, "boosters", "packs")
  dir.create(packs_dir, recursive = TRUE, showWarnings = FALSE)
  lines <- c(
    sprintf('name = "%s"', name),
    'description = "Removal test pack."',
    sprintf("packages = [%s]", paste(sprintf('"%s"', packages), collapse = ", "))
  )
  if (!is.null(extends)) {
    lines <- c(lines, sprintf('extends = ["%s"]', extends))
  }
  lines <- c(lines, "", "[settings]", "retries = 2")
  writeLines(lines, file.path(packs_dir, sprintf("%s.toml", name)))
}

write_lock_with_package <- function(root, package) {
  packages <- stats::setNames(
    list(list(Package = package, Version = "1.0.0")),
    package
  )
  jsonlite::write_json(
    list(R = list(Version = "4.5.1"), Packages = packages),
    file.path(root, "renv.lock"),
    auto_unbox = TRUE
  )
}

test_that("remove_pack with sync = FALSE regenerates attach.R and drops the pack section", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "fake-attach")
  add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
  write_attach(root, verbose = FALSE)
  attach_path <- file.path(root, "boosters", "attach.R")
  expect_true(any(grepl(
    "boostertestpkg",
    readLines(attach_path, warn = FALSE),
    fixed = TRUE
  )))

  remove_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)

  expect_false(any(grepl(
    "boostertestpkg",
    readLines(attach_path, warn = FALSE),
    fixed = TRUE
  )))
  expect_false(grepl(
    "fake-attach",
    paste(readLines(file.path(root, "boosters.toml"), warn = FALSE), collapse = "\n"),
    fixed = TRUE
  ))
})

test_that("remove_pack keeps unrelated config and removes only the settings section", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "fake-attach")
  add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(c("# keep me", lines, "[extra_section]", "value = 1"), path)

  suppressWarnings(remove_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE))

  lines <- readLines(path, warn = FALSE)
  expect_true("# keep me" %in% lines)
  expect_true("[extra_section]" %in% lines)
  expect_true("[settings]" %in% lines)
  expect_false(any(grepl("settings.packs", lines, fixed = TRUE)))
})

test_that("remove_pack drops packs only pulled in through extends", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "parent-pack", packages = "boostertestparent")
  write_removal_pack(
    root,
    "child-pack",
    packages = "boostertestchild",
    extends = "parent-pack"
  )
  add_pack("child-pack", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  expect_true("[settings.packs.parent-pack]" %in% readLines(path, warn = FALSE))

  remove_pack("child-pack", root = root, sync = FALSE, verbose = FALSE)

  expect_false(any(grepl(
    "settings.packs",
    readLines(path, warn = FALSE),
    fixed = TRUE
  )))
  attach_lines <- readLines(
    file.path(root, "boosters", "attach.R"),
    warn = FALSE
  )
  expect_false(any(grepl("boostertestparent", attach_lines, fixed = TRUE)))
})

test_that("remove_pack keeps the settings of a parent another declared pack extends", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "shared-parent", packages = "boostertestparent")
  write_removal_pack(
    root,
    "child-a",
    packages = "boostertestchild",
    extends = "shared-parent"
  )
  write_removal_pack(
    root,
    "child-b",
    packages = "boostertestsibling",
    extends = "shared-parent"
  )
  add_pack("child-a", root = root, sync = FALSE, verbose = FALSE)
  add_pack("child-b", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  expect_true("[settings.packs.shared-parent]" %in% readLines(path, warn = FALSE))

  remove_pack("child-a", root = root, sync = FALSE, verbose = FALSE)

  lines <- readLines(path, warn = FALSE)
  expect_true("[settings.packs.shared-parent]" %in% lines)
  expect_true("[settings.packs.child-b]" %in% lines)
  expect_false("[settings.packs.child-a]" %in% lines)
  attach_lines <- readLines(file.path(root, "boosters", "attach.R"), warn = FALSE)
  expect_true(any(grepl("boostertestparent", attach_lines, fixed = TRUE)))
  expect_true(any(grepl("boostertestsibling", attach_lines, fixed = TRUE)))
  expect_false(any(grepl("boostertestchild", attach_lines, fixed = TRUE)))
})

test_that("remove_pack drops child tables that follow an unrelated table", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "fake-attach")
  add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(c(
    lines,
    "[extra_section]",
    "value = 1",
    "",
    "[settings.packs.fake-attach.late]",
    "level = 3"
  ), path)

  suppressWarnings(remove_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE))

  lines <- readLines(path, warn = FALSE)
  expect_false(any(grepl("settings.packs.fake-attach", lines, fixed = TRUE)))
  expect_false("level = 3" %in% lines)
  expect_true("[extra_section]" %in% lines)
  expect_equal(lines[[length(lines)]], "value = 1")
})

test_that("remove_pack keeps comments above the next table and drops child tables", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "fake-attach")
  add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(c(
    lines,
    "[settings.packs.fake-attach.nested]",
    "level = 2",
    "",
    "# Describes the table below.",
    "[extra_section]",
    "value = 1"
  ), path)

  suppressWarnings(remove_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE))

  lines <- readLines(path, warn = FALSE)
  expect_false(any(grepl("settings.packs.fake-attach", lines, fixed = TRUE)))
  expect_false("level = 2" %in% lines)
  expect_false("retries = 2" %in% lines)
  next_table <- match("[extra_section]", lines)
  expect_false(is.na(next_table))
  expect_equal(lines[[next_table - 1L]], "# Describes the table below.")
  expect_equal(lines[[next_table + 1L]], "value = 1")
})

test_that("the removed settings section notice follows routine output", {
  make_project <- function(root) {
    init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
    write_removal_pack(root, "fake-attach")
    add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
  }
  loud_root <- withr::local_tempdir()
  quiet_root <- withr::local_tempdir()
  make_project(loud_root)
  make_project(quiet_root)

  loud <- testthat::capture_messages(
    remove_pack("fake-attach", root = loud_root, sync = FALSE, verbose = TRUE)
  )
  quiet <- testthat::capture_messages(
    remove_pack("fake-attach", root = quiet_root, sync = FALSE)
  )

  expect_true(any(grepl("Removed 1 settings section", loud, fixed = TRUE)))
  expect_false(any(grepl("settings section", quiet, fixed = TRUE)))
})

test_that("remove_pack reports packages left in renv.lock unless verbose is FALSE", {
  make_project <- function(root) {
    init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
    write_removal_pack(root, "fake-attach")
    add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
    write_lock_with_package(root, "boostertestpkg")
  }
  loud_root <- withr::local_tempdir()
  quiet_root <- withr::local_tempdir()
  make_project(loud_root)
  make_project(quiet_root)

  messages <- testthat::capture_messages(
    remove_pack("fake-attach", root = loud_root, sync = FALSE)
  )
  expect_true(any(grepl("renv::snapshot", messages, fixed = TRUE)))
  # The three cli bullets must render as separate lines, not one run-on line.
  message_lines <- unlist(strsplit(paste(messages, collapse = ""), "\n", fixed = TRUE))
  expect_true(any(grepl("still listed in", message_lines, fixed = TRUE)))
  expect_true(any(grepl("boosterpak does not change", message_lines, fixed = TRUE)))
  expect_true(any(grepl("renv::snapshot()", message_lines, fixed = TRUE)))
  expect_true(any(grepl("renv::remove()", message_lines, fixed = TRUE)))
  expect_false(any(grepl("boosterpak does not change", message_lines, fixed = TRUE) &
    grepl("renv::snapshot()", message_lines, fixed = TRUE)))
  expect_no_message(
    remove_pack("fake-attach", root = quiet_root, sync = FALSE, verbose = FALSE)
  )
})

test_that("remove_pack does not warn about lockfile packages that were never locked", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  write_removal_pack(root, "fake-attach")
  add_pack("fake-attach", root = root, sync = FALSE, verbose = FALSE)
  write_lock_with_package(root, "unrelated")

  messages <- testthat::capture_messages(
    remove_pack("fake-attach", root = root, sync = FALSE)
  )
  expect_false(any(grepl("renv", messages, fixed = TRUE)))
})
