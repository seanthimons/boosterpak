test_that("exact compiled pins recover dated binaries without changing shared state", {
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  withr::local_options(
    repos = c(CRAN = "https://p3m.dev/cran/latest"),
    renv.config.repos.override = NULL
  )
  records <- list(
    duckdb = list(
      Package = "duckdb",
      Version = "1.5.5",
      Source = "Repository",
      Repository = "CRAN",
      NeedsCompilation = "yes"
    ),
    cli = list(
      Package = "cli",
      Version = "3.6.6",
      Source = "Repository",
      Repository = "CRAN",
      NeedsCompilation = "yes"
    ),
    other = list(
      Package = "other",
      Version = "1.0",
      Source = "Repository",
      Repository = "CRAN",
      NeedsCompilation = "yes"
    ),
    private = list(
      Package = "private",
      Version = "1.0",
      Source = "Repository",
      Repository = "internal",
      NeedsCompilation = "yes"
    )
  )
  old <- getOption("repos")
  asked <- character()
  updates <- 0L
  fail <- FALSE
  local_mocked_bindings(
    is_glibc_linux = function() FALSE,
    should_configure_repositories = function() TRUE
  )
  local_mocked_bindings(
    meta_list = function(packages) {
      stopifnot(!"private" %in% packages)
      dated <- any(grepl("2026-09-28$", getOption("repos")))
      data.frame(
        package = c("duckdb", "cli", "other"),
        version = c("1.5.5", "3.6.6", "1.0"),
        platform = c(
          if (dated) "x86_64-w64-mingw32" else "source",
          "x86_64-w64-mingw32",
          "source"
        )
      )
    },
    meta_update = function(...) {
      updates <<- updates + 1L
      if (fail) stop("index unavailable")
    },
    pkg_history = function(pkg) {
      asked <<- c(asked, pkg)
      if (pkg == "other") {
        return(data.frame(
          Version = c("1.0", "2.0"),
          date = c("2026-01-01", "2026-02-01")
        ))
      }
      data.frame(
        Version = c("1.5.5", "1.5.6"),
        date = c("2026-07-25", "2026-09-29")
      )
    },
    .package = "pak"
  )
  run <- function() {
    scope_archived_binary_repos(records)
    expect_equal(
      unname(getOption("repos")[["P3M_archive_2026_09_28"]]),
      "https://p3m.dev/cran/2026-09-28"
    )
    expect_equal(
      unname(getOption("repos")[["P3M_archive_2026_01_31"]]),
      "https://p3m.dev/cran/2026-01-31"
    )
    expect_identical(
      getOption("repos"),
      getOption("renv.config.repos.override")
    )
  }
  expect_message(run(), "duckdb")
  expect_identical(asked, c("duckdb", "other"))
  expect_identical(updates, 1L)
  expect_identical(getOption("repos"), old)
  expect_null(getOption("renv.config.repos.override"))
  expect_identical(records$duckdb$Version, "1.5.5")
  fail <- TRUE
  expect_error(run(), "index unavailable")
  expect_identical(getOption("repos"), old)
  expect_null(getOption("renv.config.repos.override"))
})

test_that("archive lookup respects dated and private repository policies", {
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  withr::local_options(
    repos = c(CRAN = "https://p3m.dev/cran/latest"),
    renv.config.repos.override = NULL
  )
  local_mocked_bindings(should_configure_repositories = function() TRUE)
  local_mocked_bindings(
    meta_list = function(...) stop("must not contact repositories"),
    .package = "pak"
  )
  records <- list(
    pkg = list(
      Source = "Repository",
      Repository = "CRAN",
      NeedsCompilation = "yes"
    )
  )
  for (url in c(
    "https://p3m.dev/cran/2026-09-01",
    "https://private.example/cran/latest"
  )) {
    options(repos = c(CRAN = url))
    expect_null(scope_archived_binary_repos(records))
    expect_identical(unname(getOption("repos")), url)
  }
  options(
    repos = c(CRAN = "https://p3m.dev/cran/latest"),
    renv.config.repos.override = "https://private.example/cran/latest"
  )
  expect_null(scope_archived_binary_repos(records))
  options(renv.config.repos.override = NULL)
  local_mocked_bindings(should_configure_repositories = function() FALSE)
  expect_null(scope_archived_binary_repos(records))
})

test_that("required binary packages fail before installation when only source resolves", {
  records <- list(duckdb = list(Version = "1.5.5"))
  platform <- "source"
  local_mocked_bindings(
    pkg_deps = function(pkg) {
      expect_identical(unname(pkg), "duckdb@1.5.5")
      data.frame(package = "duckdb", platform = platform)
    },
    .package = "pak"
  )
  expect_error(
    check_required_binaries(records, "duckdb"),
    "No compatible binary"
  )
  platform <- "x86_64-w64-mingw32"
  expect_null(check_required_binaries(records, "duckdb"))
  expect_null(check_required_binaries(records, character()))
  expect_error(
    check_required_binaries(records, "unknown"),
    "not in the lockfile"
  )
})
