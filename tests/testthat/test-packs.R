test_that("built-in packs are discoverable", {
  packs <- list_packs(verbose = FALSE)
  expect_setequal(packs$name, c("core", "example", "github-example"))
  expect_true(all(c("name", "description", "scope", "path") %in% names(packs)))
})

test_that("packs resolve transitively", {
  expect_equal(boosterpak:::resolve_pack("example"), "cli")
})
