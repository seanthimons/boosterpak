source_mirai_daemons_helper <- function() {
  env <- new.env(parent = globalenv())
  sys.source(test_path("fixtures", "fn_mirai_daemons.R"), envir = env)
  env$mirai_daemons
}

test_that("mirai_daemons dry run supports explicit n and passthrough args", {
  mirai_daemons <- source_mirai_daemons_helper()

  result <- mirai_daemons(
    2,
    dispatcher = FALSE,
    .compute = "cpu",
    dry_run = TRUE
  )

  expect_equal(result$n, 2L)
  expect_equal(result$source, "n")
  expect_false(result$args$dispatcher)
  expect_equal(result$args$.compute, "cpu")
  expect_true(result$dry_run)
})

test_that("mirai_daemons dry run reads [settings.packs.sean-parallel].daemons", {
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  mirai_daemons <- source_mirai_daemons_helper()
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  writeLines(
    c(
      readLines(path, warn = FALSE),
      "",
      "[settings.packs.sean-parallel]",
      "daemons = 3"
    ),
    path
  )

  withr::local_dir(root)
  result <- mirai_daemons(dry_run = TRUE)

  expect_equal(result$n, 3L)
  expect_equal(result$source, "[settings.packs.sean-parallel].daemons")
})

test_that("mirai_daemons dry run defaults auto and supports reset", {
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  mirai_daemons <- source_mirai_daemons_helper()
  root <- withr::local_tempdir()

  withr::local_dir(root)
  result <- mirai_daemons(dry_run = TRUE)
  reset <- mirai_daemons(0, dry_run = TRUE)

  expect_true(is.integer(result$n))
  expect_true(result$n >= 1L)
  expect_equal(result$source, "default")
  expect_equal(reset$n, 0L)
  expect_equal(reset$source, "n")
})
