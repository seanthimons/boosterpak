version_line_index <- function(lines) {
  which(grepl("^boosters_version = ", lines))
}

write_stale_version <- function(root, version = "0.0.1") {
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines[version_line_index(lines)] <- sprintf('boosters_version = "%s"', version)
  writeLines(lines, path)
}

# A project initialized with the given .Rprofile step, with repository and
# install policy setup switched off so the tests stay inside the project.
local_project <- function(rprofile = "yes", .env = parent.frame()) {
  withr::local_options(
    list(
      boosterpak.configure_repositories = FALSE,
      boosterpak.configure_install_policy = FALSE
    ),
    .local_envir = .env
  )
  root <- withr::local_tempdir(.local_envir = .env)
  init(root = root, renv = "no", rprofile = rprofile, verbose = FALSE)
  root
}

test_that("generated boosters.toml records the version with an explanation", {
  root <- local_project("yes")
  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)

  at <- version_line_index(lines)
  expect_length(at, 1L)
  expect_equal(
    lines[[at]],
    sprintf('boosters_version = "%s"', boosterpak:::package_version_string())
  )
  comment <- boosterpak:::boosters_version_comment()
  expect_equal(lines[seq.int(at - length(comment), length.out = length(comment))], comment)
  expect_match(paste(comment, collapse = "\n"), "last migrated")
  expect_true(any(grepl('^name = "', lines)))
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("a new project with rprofile = 'no' is not marked migrated", {
  root <- local_project("no")
  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)

  expect_length(version_line_index(lines), 0L)
  expect_false(any(grepl("^# boosters_version", lines)))
  expect_true(any(grepl("^name = ", lines)))
  expect_true(boosterpak:::project_needs_upgrade(root))
  # The skipped .Rprofile setup is reported to init(), not treated as current.
  skipped <- boosterpak:::ensure_rprofile_line(root, "no", repository_lines = character())
  expect_true(isTRUE(attr(skipped, "skipped")))

  # The first init() that completes the .Rprofile step records the version.
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_equal(
    lines[[version_line_index(lines)]],
    sprintf('boosters_version = "%s"', boosterpak:::package_version_string())
  )
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("a new project written with rprofile = 'no' keeps the rest of the default config", {
  root <- local_project("no")
  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)

  expect_equal(lines[[1]], "# boosters.toml - project configuration")
  expect_true(any(grepl("^\\[packs\\]$", lines)))
  expect_true(any(grepl("^\\[attach\\]$", lines)))
})

test_that("init refreshes a stale boosters_version and keeps user edits", {
  root <- local_project("yes")
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines <- c(lines[seq_len(version_line_index(lines) - 1L)], "# my note", lines[version_line_index(lines):length(lines)])
  writeLines(lines, path)
  write_stale_version(root, "0.6.0.9000")
  expect_true(boosterpak:::project_needs_upgrade(root))

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(path, warn = FALSE)
  expect_equal(
    lines[[version_line_index(lines)]],
    sprintf('boosters_version = "%s"', boosterpak:::package_version_string())
  )
  expect_true("# my note" %in% lines)
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("init with rprofile = 'no' does not mark an existing project migrated", {
  root <- local_project("yes")
  write_stale_version(root, "0.6.0.9000")

  result <- init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_false(result$rprofile_changed)
  expect_true(boosterpak:::project_needs_upgrade(root))
  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_equal(lines[[version_line_index(lines)]], 'boosters_version = "0.6.0.9000"')
})

test_that("init with rprofile = 'yes' marks the project migrated", {
  root <- local_project("yes")
  write_stale_version(root, "0.6.0.9000")
  expect_true(boosterpak:::project_needs_upgrade(root))

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("a newer recorded boosters_version is never downgraded", {
  root <- local_project("yes")
  path <- file.path(root, "boosters.toml")
  write_stale_version(root, "99.0.0")
  before <- readLines(path, warn = FALSE)

  expect_false(boosterpak:::set_boosters_version(root))
  expect_equal(readLines(path, warn = FALSE), before)

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)
  expect_equal(readLines(path, warn = FALSE), before)
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("a user comment above the key does not duplicate the explanation", {
  root <- withr::local_tempdir()
  comment <- boosterpak:::boosters_version_comment()
  writeLines(
    c(
      "[project]",
      'name = "annotated"',
      comment,
      "# my note about the record",
      'boosters_version = "0.0.1"'
    ),
    file.path(root, "boosters.toml")
  )

  expect_true(boosterpak:::set_boosters_version(root))

  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_equal(sum(lines == comment[[1]]), 1L)
  expect_equal(sum(grepl("^# boosters_version", lines)), 1L)
  expect_true("# my note about the record" %in% lines)
  expect_equal(lines[[version_line_index(lines)]], sprintf('boosters_version = "%s"', boosterpak:::package_version_string()))
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("project_needs_upgrade reports a newer installed boosterpak after the record", {
  root <- local_project("yes")
  expect_false(boosterpak:::project_needs_upgrade(root))

  local_mocked_bindings(
    package_version_string = function() "99.0.0",
    .package = "boosterpak"
  )
  expect_true(boosterpak:::project_needs_upgrade(root))

  # Recording the version is what marks the project as migrated.
  expect_true(boosterpak:::set_boosters_version(root))
  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_equal(lines[[version_line_index(lines)]], 'boosters_version = "99.0.0"')
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("set_boosters_version is a no-op when the record is current", {
  root <- local_project("yes")
  path <- file.path(root, "boosters.toml")
  before <- readLines(path, warn = FALSE)

  expect_false(boosterpak:::set_boosters_version(root))
  expect_equal(readLines(path, warn = FALSE), before)
})

test_that("set_boosters_version adds the explanation to records written without it", {
  root <- withr::local_tempdir()
  writeLines(
    c(
      "[project]",
      'name = "older"',
      'boosters_version = "0.6.0.9000"',
      "",
      "[packs]",
      'declared = ["core"]'
    ),
    file.path(root, "boosters.toml")
  )

  expect_true(boosterpak:::set_boosters_version(root))

  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  comment <- boosterpak:::boosters_version_comment()
  at <- version_line_index(lines)
  expect_equal(
    lines[seq.int(at - length(comment), length.out = length(comment))],
    comment
  )
  expect_equal(lines[[at]], sprintf('boosters_version = "%s"', boosterpak:::package_version_string()))
  expect_true('name = "older"' %in% lines)
  expect_true('declared = ["core"]' %in% lines)
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("set_boosters_version adds the field when [project] lacks it", {
  root <- withr::local_tempdir()
  writeLines(c("[project]", 'name = "bare"'), file.path(root, "boosters.toml"))

  boosterpak:::set_boosters_version(root)

  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_length(version_line_index(lines), 1L)
  expect_true('name = "bare"' %in% lines)
  expect_false(boosterpak:::project_needs_upgrade(root))
})

test_that("project_needs_upgrade treats a missing record as needing upgrade", {
  root <- local_project("yes")
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(lines[-version_line_index(lines)], path)

  expect_true(boosterpak:::project_needs_upgrade(root))
  expect_false(boosterpak:::project_needs_upgrade(withr::local_tempdir()))
})

test_that("sync does not refresh boosters_version", {
  root <- local_project("yes")
  write_stale_version(root)

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".", ...) character(),
    install_via = function(specs, root = ".", ...) TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )
  sync(root = root, verbose = FALSE)

  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_equal(lines[[version_line_index(lines)]], 'boosters_version = "0.0.1"')
  expect_true(boosterpak:::project_needs_upgrade(root))
})
