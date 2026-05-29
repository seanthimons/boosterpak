test_that("live pak and renv apply sync installs declared packages", {
  skip_if_not(
    identical(Sys.getenv("BOOSTERPAK_LIVE_TESTS"), "true"),
    "Set BOOSTERPAK_LIVE_TESTS=true to run live pak/renv integration tests."
  )

  root <- withr::local_tempdir()
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  test_libpaths <- .libPaths()
  init(root = root, renv = "yes", rprofile = "no", verbose = FALSE)
  .libPaths(unique(c(.libPaths(), test_libpaths)))
  expect_true(file.exists(file.path(root, "renv.lock")))
  expect_false("boosterpak" %in% boosterpak:::missing_packages("boosterpak", root = root))
  config_path <- file.path(root, "boosters.toml")
  lines <- readLines(config_path, warn = FALSE)
  lines[lines == 'declared = ["core"]'] <- 'declared = ["example"]'
  lines[lines == "auto_snapshot = true"] <- "auto_snapshot = true"
  writeLines(lines, config_path)

  sync(root = root, verbose = FALSE)
  s <- status(root = root, verbose = FALSE)

  expect_true(s$renv_active)
  expect_true(s$lockfile_exists)
  expect_true("cli" %in% s$packages)
  expect_false("cli" %in% s$missing_packages)
})

test_that("live restore warns when lockfile omits direct declared packages", {
  skip_if_not(
    identical(Sys.getenv("BOOSTERPAK_LIVE_TESTS"), "true"),
    "Set BOOSTERPAK_LIVE_TESTS=true to run live pak/renv integration tests."
  )

  root <- withr::local_tempdir()
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  test_libpaths <- .libPaths()
  init(root = root, renv = "yes", rprofile = "no", verbose = FALSE)
  .libPaths(unique(c(.libPaths(), test_libpaths)))
  config_path <- file.path(root, "boosters.toml")
  lines <- readLines(config_path, warn = FALSE)
  lines[lines == 'declared = ["core"]'] <- 'declared = ["example"]'
  writeLines(lines, config_path)
  renv::snapshot(project = root, prompt = FALSE)

  expect_warning(
    sync(mode = "restore", root = root, verbose = FALSE),
    "cli"
  )
})
