test_that("init configures PPM repos from R default CRAN placeholder", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@", Internal = "https://example.test/repo"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("repos")[["Internal"]],
    "https://example.test/repo"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    paste(
      "CRAN=https://packagemanager.posit.co/cran/latest",
      "Internal=https://example.test/repo",
      sep = ";"
    )
  )
  expect_false(file.exists(file.path(root, ".Rprofile")))
})

test_that("init persists PPM repository setup before renv activation", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  writeLines(
    c("before <- TRUE", "source(\"renv/activate.R\")", "after <- TRUE"),
    file.path(root, ".Rprofile")
  )

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  marker <- match(boosterpak:::rprofile_repository_marker(), lines)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)
  hook_line <- match(boosterpak:::rprofile_line(), lines)

  expect_equal(marker, renv_line - 3L)
  expect_match(lines[[marker + 1L]], "options\\(repos = c")
  expect_match(lines[[marker + 2L]], "renv.config.repos.override")
  expect_equal(hook_line, renv_line + 1L)
})

test_that("init preserves explicit non-PPM repos", {
  withr::local_options(list(
    repos = c(CRAN = "https://cloud.r-project.org"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(getOption("repos")[["CRAN"]], "https://cloud.r-project.org")
  expect_null(getOption("renv.config.repos.override"))
})

test_that("init preserves existing renv repository override", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = "CRAN=https://example.test/cran",
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    "CRAN=https://example.test/cran"
  )
})

test_that("repository helpers handle NA values and names", {
  expect_false(boosterpak:::uses_posit_package_manager(c(
    NA_character_,
    "https://example.test/repo"
  )))
  expect_true(boosterpak:::uses_posit_package_manager(c(
    NA_character_,
    "https://packagemanager.posit.co/cran/latest"
  )))

  repos <- c("https://cloud.r-project.org", "https://example.test/repo")
  names(repos) <- c("CRAN", NA_character_)

  expect_equal(
    boosterpak:::format_repos_override(repos),
    "https://cloud.r-project.org"
  )
  expect_equal(
    boosterpak:::rprofile_repos_value(repos),
    '"https://cloud.r-project.org", "https://example.test/repo"'
  )
})

test_that("init repository configuration can be disabled by option", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(getOption("repos")[["CRAN"]], "@CRAN@")
  expect_null(getOption("renv.config.repos.override"))
})

test_that("init emits cli alert when configuring repositories", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  expect_message(
    init(root = root, renv = "no", rprofile = "no", verbose = TRUE),
    "Posit Package Manager"
  )
})
