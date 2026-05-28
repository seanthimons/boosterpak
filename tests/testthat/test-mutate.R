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
