test_that("PPM Linux URLs are portable across distributions and preserve snapshots", {
  local_ppm_hosts()
  urls <- c(
    CRAN = "https://packagemanager.posit.co/cran/__linux__/trixie/latest",
    dated = "https://p3m.dev/cran/__linux__/noble/2026-10-01",
    manylinux = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_17/latest",
    custom = "https://example.org/cran/__linux__/trixie/latest"
  )
  expect_equal(
    portable_ppm_repos(urls),
    c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      dated = "https://p3m.dev/cran/2026-10-01",
      manylinux = "https://packagemanager.posit.co/cran/latest",
      custom = urls[["custom"]]
    )
  )
})

test_that("restore_project repairs old lockfiles before exact restore without packs", {
  root <- withr::local_tempdir()
  url <- "https://packagemanager.posit.co/cran/__linux__/trixie/2026-10-01"
  lock <- list(
    R = list(
      Version = "4.6.0",
      Repositories = list(list(Name = "CRAN", URL = url))
    ),
    Packages = list(
      ps = list(
        Package = "ps",
        Version = "1.9.2",
        Source = "Repository",
        Repository = url
      ),
      other = list(
        Package = "other",
        Version = "2.0.0",
        Source = "Repository",
        Repository = "https://example.org/cran"
      )
    )
  )
  jsonlite::write_json(
    lock,
    file.path(root, "renv.lock"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  restored <- NULL
  local_mocked_bindings(call_renv_restore = function(root) {
    restored <<- renv::lockfile_read(
      file = file.path(root, "renv.lock"),
      project = root
    )
  })
  restore_project(root)
  expect_identical(restored$Packages$ps$Version, "1.9.2")
  expect_identical(restored$Packages$ps$Repository, "CRAN")
  expect_identical(
    restored$Packages$other$Repository,
    "https://example.org/cran"
  )
  expect_identical(
    as.character(restored$R$Repositories$CRAN),
    "https://packagemanager.posit.co/cran/2026-10-01"
  )
  before <- readBin(file.path(root, "renv.lock"), "raw", n = 100000)
  restore_project(root)
  expect_identical(
    readBin(file.path(root, "renv.lock"), "raw", n = 100000),
    before
  )
  expect_false(file.exists(file.path(root, "boosters.toml")))
  expect_error(
    restore_project(withr::local_tempdir()),
    "renv.lock.*does not exist"
  )
})

test_that("snapshot_project uses the active environment without packs", {
  root <- withr::local_tempdir()
  events <- character()
  local_mocked_bindings(
    ensure_project_renv = function(root) {
      events <<- c(events, "active")
    },
    configure_boosterpak_repositories = function(...) {
      events <<- c(events, "repos")
    },
    configure_boosterpak_install_policy = function(...) {
      events <<- c(events, "policy")
    },
    call_renv_snapshot = function(root) {
      events <<- c(events, "snapshot")
    }
  )
  snapshot_project(root)
  expect_identical(events, c("active", "repos", "policy", "snapshot"))
  expect_false(file.exists(file.path(root, "boosters.toml")))
})
