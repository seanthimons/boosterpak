test_that("sync apply requires active project-local renv", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  dir.create(file.path(root, "renv"), recursive = TRUE)
  writeLines("", file.path(root, "renv", "activate.R"))

  expect_error(
    sync(root = root, verbose = FALSE),
    "No active project-local renv library"
  )
})

test_that("sync restore requires boosters.toml and renv.lock", {
  root <- withr::local_tempdir()
  expect_error(
    sync(mode = "restore", root = root, verbose = FALSE),
    "boosters.toml"
  )

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  expect_error(
    sync(mode = "restore", root = root, verbose = FALSE),
    "renv.lock"
  )
})
