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
  withr::local_options(list(
    repos = getOption("repos"),
    renv.config.repos.override = getOption("renv.config.repos.override")
  ))
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
  withr::local_options(list(
    repos = getOption("repos"),
    renv.config.repos.override = getOption("renv.config.repos.override")
  ))
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

test_that("Linux PPM restore accepts vendor aliases without changing CPU or OS", {
  withr::local_options(
    repos = c(CRAN = "https://p3m.dev/cran/latest"),
    pkg.platforms = NULL
  )
  withr::local_envvar(PKG_PLATFORMS = NA)
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  check <- function() {
    scope_binary_platforms(platform = "x86_64-redhat-linux-gnu-fedora-44")
    expect_identical(
      getOption("pkg.platforms"),
      c(
        "x86_64-redhat-linux-gnu-fedora-44",
        "x86_64-pc-linux-gnu-fedora-44",
        "source"
      )
    )
  }
  check()
  expect_null(getOption("pkg.platforms"))
  options(pkg.platforms = "source")
  scope_binary_platforms(platform = "aarch64-unknown-linux-gnu-debian-13")
  expect_identical(getOption("pkg.platforms"), "source")
})

test_that("Sonoma accepts older same-CPU Darwin builds without crossing architectures", {
  withr::local_options(
    repos = c(CRAN = "https://p3m.dev/cran/latest"),
    pkg.platforms = NULL
  )
  withr::local_envvar(PKG_PLATFORMS = NA)
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  check <- function() {
    scope_binary_platforms(platform = "aarch64-apple-darwin23")
    expect_identical(
      getOption("pkg.platforms"),
      c(
        "aarch64-apple-darwin23",
        "aarch64-apple-darwin20",
        "source"
      )
    )
  }
  check()
  expect_null(getOption("pkg.platforms"))
  check_old <- function() {
    scope_binary_platforms(platform = "aarch64-apple-darwin20")
    expect_identical(
      getOption("pkg.platforms"),
      c("aarch64-apple-darwin20", "source")
    )
  }
  check_old()
})

test_that("public P3M fallback preserves dates and explicit private policies", {
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_CONFIGURE_REPOSITORIES = NA
  )
  withr::local_options(
    repos = c(
      CRAN = "https://p3m.dev/cran/2026-10-01",
      private = "https://example.org"
    ),
    renv.config.repos.override = "https://p3m.dev/cran/2026-09-01",
    boosterpak.configure_repositories = TRUE
  )
  add_public_cran_fallback()
  expect_identical(
    getOption("repos")[["CRAN"]],
    "https://p3m.dev/cran/2026-10-01"
  )
  expect_identical(getOption("repos")[["private"]], "https://example.org")
  expect_identical(
    getOption("repos")[["CRAN_fallback"]],
    "https://cloud.r-project.org"
  )
  expect_identical(
    getOption("renv.config.repos.override")[["CRAN"]],
    "https://p3m.dev/cran/2026-09-01"
  )
  expect_identical(
    getOption("renv.config.repos.override")[["CRAN_fallback"]],
    "https://cloud.r-project.org"
  )
  options(renv.config.repos.override = "https://example.org/private")
  add_public_cran_fallback()
  expect_identical(
    getOption("renv.config.repos.override"),
    "https://example.org/private"
  )
  options(
    repos = c(
      CRAN = "https://p3m.dev/cran/latest",
      CRAN_fallback = "https://example.org/mirror"
    ),
    renv.config.repos.override = NULL
  )
  add_public_cran_fallback()
  expect_identical(
    getOption("repos")[["CRAN_fallback"]],
    "https://example.org/mirror"
  )
  options(
    repos = c(CRAN = "https://p3m.dev/cran/latest"),
    boosterpak.configure_repositories = FALSE
  )
  add_public_cran_fallback()
  expect_false("CRAN_fallback" %in% names(getOption("repos")))
})

test_that("binary index repairs preserve repository identity without changing the cache", {
  root <- withr::local_tempdir()
  library <- file.path(root, "library")
  path <- file.path(library, "example")
  dir.create(file.path(path, "Meta"), recursive = TRUE)
  fields <- c(
    Package = "example",
    Version = "1.0",
    Repository = "RSPM",
    RemoteType = "url",
    RemoteUrl = "https://p3m.dev/example.tgz"
  )
  write.dcf(as.list(fields), file.path(path, "DESCRIPTION"))
  saveRDS(
    list(DESCRIPTION = fields, other = TRUE),
    file.path(path, "Meta", "package.rds")
  )
  isolated <- FALSE
  local_mocked_bindings(
    isolate = function(project) {
      isolated <<- TRUE
    },
    .package = "renv"
  )
  paths <- renv::paths
  paths$library <- function(...) library
  local_mocked_bindings(paths = paths, .package = "renv")
  original <- list(
    example = list(Source = "Repository", Version = "1.0", Repository = "CRAN")
  )
  restored <- list(example = list(Source = "URL"))
  restore_repository_metadata(root, original, restored)
  expect_true(isolated)
  actual <- read.dcf(file.path(path, "DESCRIPTION"))
  expect_false(any(grepl("^Remote", colnames(actual))))
  expect_equal(unname(actual[1, "Repository"]), "CRAN")
  meta <- readRDS(file.path(path, "Meta", "package.rds"))
  expect_true(meta$other)
  expect_identical(
    meta$DESCRIPTION,
    setNames(as.character(actual[1, ]), colnames(actual))
  )
  isolated <- FALSE
  restore_repository_metadata(root, restored, restored)
  expect_false(isolated)
})
