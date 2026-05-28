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
