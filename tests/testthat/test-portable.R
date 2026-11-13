sha <- strrep("a", 40)

local_portable_project <- function(
  profile = NULL,
  lock = TRUE,
  env = parent.frame()
) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "renv"))
  writeLines(
    'stop("auto-loader must not run")',
    file.path(root, "renv", "activate.R")
  )
  if (lock) {
    writeLines("{}", file.path(root, "renv.lock"))
  }
  if (!is.null(profile)) {
    writeLines(profile, file.path(root, ".Rprofile"))
  }
  root
}

# Runs `expr` in a vanilla Rscript started in `root`. The code goes through a
# script file so quoting is the same on every platform.
run_vanilla <- function(root, expr) {
  script <- withr::local_tempfile(fileext = ".R")
  withr::local_dir(root)
  writeLines(expr, script)
  suppressWarnings(
    system2(
      file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(script)),
      stdout = TRUE,
      stderr = TRUE
    ),
    classes = "warning"
  )
}

test_that("pin comes from the installed GitHub commit and follows forks", {
  desc <- list(
    Version = "1.2.3",
    RemoteType = "github",
    RemoteSha = sha,
    RemoteUsername = "someone",
    RemoteRepo = "boosterpak-fork"
  )
  pin <- portable_pin(desc = desc)
  expect_identical(pin$sha, sha)
  expect_identical(pin$spec, "someone/boosterpak-fork")
  expect_identical(pin$version, "1.2.3")
  expect_identical(portable_pin(strrep("b", 40), desc)$sha, strrep("b", 40))
})

test_that("pin refuses installs without a commit and malformed refs", {
  local_source <- list(Version = "0.10.0")
  expect_error(portable_pin(desc = local_source), "no GitHub commit SHA")
  expect_error(
    portable_pin(desc = list(RemoteType = "cran", RemoteSha = sha)),
    "no GitHub commit SHA"
  )
  expect_identical(
    portable_pin(sha, local_source)$spec,
    "seanthimons/boosterpak"
  )
  for (bad in c("v0.10.0", "main", substr(sha, 1, 7), toupper(sha), NA)) {
    expect_error(portable_pin(bad, local_source), "40-character")
  }
})

test_that("generated setup.R parses and carries the pin and bootstrap only", {
  pin <- list(spec = "someone/bp", sha = sha, version = "1.2.3")
  lines <- portable_setup_lines(pin)
  expect_no_error(parse(text = lines))
  expect_true(is_generated_setup(lines))
  text <- paste(lines, collapse = "\n")
  expect_match(text, paste0('ref <- "', sha, '"'), fixed = TRUE)
  expect_match(text, 'renv::install(paste0("someone/bp@", ref)', fixed = TRUE)
  expect_match(text, "boosterpak::restore_portable_project()", fixed = TRUE)
  # Bootstrap behaviour kept from the reference template.
  expect_match(text, "__linux__/[^/]+/", fixed = TRUE)
  expect_match(text, "manylinux_2_28", fixed = TRUE)
  expect_match(text, 'unloadNamespace("boosterpak")', fixed = TRUE)
  expect_match(text, "pkg.platforms", fixed = TRUE)
  expect_match(text, "CRAN_fallback", fixed = TRUE)
  # Machine-local startup data is written by package code, not setup.R.
  expect_no_match(text, "renv/local", fixed = TRUE)
})

test_that("generated files never embed a private Package Manager host", {
  withr::local_envvar(
    BOOSTERPAK_PPM_REPO = "https://ppm.internal.test/cran/latest"
  )
  withr::local_options(boosterpak.ppm_hosts = "ppm.internal.test")
  text <- paste(
    c(
      portable_setup_lines(list(spec = "a/b", sha = sha, version = "1")),
      portable_startup_block()
    ),
    collapse = "\n"
  )
  expect_no_match(text, "internal", fixed = TRUE)
})

test_that("write_portable_setup replaces the renv activation line in place", {
  root <- local_portable_project(c(
    "x <- 1",
    'source("renv/activate.R")',
    "y <- 2",
    'source("renv/activate.R")'
  ))
  written <- write_portable_setup(root, ref = sha, verbose = FALSE)
  expect_identical(basename(written), c("setup.R", ".Rprofile"))

  profile <- readLines(file.path(root, ".Rprofile"))
  expect_identical(profile[[1]], "x <- 1")
  expect_identical(profile[[2]], rprofile_portable_begin_marker())
  expect_identical(
    profile[length(profile) - 1L],
    rprofile_portable_end_marker()
  )
  expect_identical(profile[[length(profile)]], "y <- 2")
  expect_false(any(is_rprofile_renv_activation(profile)))
  expect_identical(sum(profile == rprofile_portable_begin_marker()), 1L)
  expect_no_error(parse(file.path(root, ".Rprofile")))
  expect_true(is_generated_setup(readLines(file.path(root, "setup.R"))))
})

test_that("write_portable_setup creates .Rprofile when absent and is idempotent", {
  root <- local_portable_project()
  write_portable_setup(root, ref = sha, verbose = FALSE)
  expect_identical(
    readLines(file.path(root, ".Rprofile")),
    portable_startup_block()
  )
  before <- list(
    setup = readBin(file.path(root, "setup.R"), "raw", 1e5),
    profile = readBin(file.path(root, ".Rprofile"), "raw", 1e5)
  )
  expect_length(write_portable_setup(root, ref = sha, verbose = FALSE), 0)
  expect_identical(
    readBin(file.path(root, "setup.R"), "raw", 1e5),
    before$setup
  )
  expect_identical(
    readBin(file.path(root, ".Rprofile"), "raw", 1e5),
    before$profile
  )
})

test_that("rerunning strips an activation line that renv added back", {
  root <- local_portable_project()
  write_portable_setup(root, ref = sha, verbose = FALSE)
  profile <- readLines(file.path(root, ".Rprofile"))
  writeLines(
    c('source("renv/activate.R")', profile, "z <- 3"),
    file.path(root, ".Rprofile")
  )
  write_portable_setup(root, ref = sha, verbose = FALSE)
  updated <- readLines(file.path(root, ".Rprofile"))
  expect_false(any(is_rprofile_renv_activation(updated)))
  expect_identical(updated, c(portable_startup_block(), "z <- 3"))
})

test_that("a new pin refreshes setup.R", {
  root <- local_portable_project()
  write_portable_setup(root, ref = sha, verbose = FALSE)
  other <- strrep("b", 40)
  written <- write_portable_setup(root, ref = other, verbose = FALSE)
  expect_identical(basename(written), "setup.R")
  expect_match(
    paste(readLines(file.path(root, "setup.R")), collapse = "\n"),
    other,
    fixed = TRUE
  )
})

test_that("a hand-written setup.R is replaced only with overwrite", {
  root <- local_portable_project()
  writeLines("# my own setup", file.path(root, "setup.R"))
  expect_error(
    write_portable_setup(root, ref = sha, verbose = FALSE),
    "not generated by boosterpak"
  )
  expect_identical(readLines(file.path(root, "setup.R")), "# my own setup")
  expect_false(file.exists(file.path(root, ".Rprofile")))
  write_portable_setup(root, ref = sha, overwrite = TRUE, verbose = FALSE)
  expect_true(is_generated_setup(readLines(file.path(root, "setup.R"))))
})

test_that("write_portable_setup refuses non-renv, pack, and malformed projects", {
  root <- withr::local_tempdir()
  expect_error(write_portable_setup(root, ref = sha), "not an renv project")

  root <- local_portable_project()
  writeLines("", file.path(root, "boosters.toml"))
  expect_error(write_portable_setup(root, ref = sha), "pack project")
  expect_false(file.exists(file.path(root, "setup.R")))

  root <- local_portable_project(c(
    'source("renv/activate.R")',
    rprofile_startup_block()
  ))
  expect_error(write_portable_setup(root, ref = sha), "pack project")
  expect_true(any(is_rprofile_renv_activation(readLines(file.path(
    root,
    ".Rprofile"
  )))))

  root <- local_portable_project(c(
    rprofile_portable_begin_marker(),
    "z <- 1"
  ))
  expect_error(write_portable_setup(root, ref = sha), "unmatched portable")
  expect_false(file.exists(file.path(root, "setup.R")))
})

test_that("opening the project before setup installs nothing and prints the hint", {
  root <- local_portable_project()
  write_portable_setup(root, ref = sha, verbose = FALSE)
  files <- sort(list.files(root, recursive = TRUE, all.files = TRUE))
  out <- run_vanilla(
    root,
    'source(".Rprofile"); cat("RENV:", isNamespaceLoaded("renv"), "\\n")'
  )
  expect_match(out, "Rscript --vanilla setup.R", fixed = TRUE, all = FALSE)
  expect_match(out, "RENV: FALSE", fixed = TRUE, all = FALSE)
  expect_identical(
    sort(list.files(root, recursive = TRUE, all.files = TRUE)),
    files
  )

  # A marker from another platform or R minor still installs nothing.
  dir.create(file.path(root, "renv", "local"))
  writeLines(
    c(dirname(find.package("renv")), "another-platform", portable_r_minor()),
    file.path(root, "renv", "local", "startup")
  )
  out <- run_vanilla(
    root,
    'source(".Rprofile"); cat("RENV:", isNamespaceLoaded("renv"), "\\n")'
  )
  expect_match(out, "Rscript --vanilla setup.R", fixed = TRUE, all = FALSE)
  expect_match(out, "RENV: FALSE", fixed = TRUE, all = FALSE)
})

test_that("a prepared project loads renv from the machine-local marker", {
  root <- local_portable_project()
  write_portable_setup(root, ref = sha, verbose = FALSE)
  dir.create(file.path(root, "renv", "local"))
  writeLines(
    c(dirname(find.package("renv")), R.version$platform, portable_r_minor()),
    file.path(root, "renv", "local", "startup")
  )
  out <- run_vanilla(
    root,
    paste(
      'source(".Rprofile")',
      'cat("RENV:", isNamespaceLoaded("renv"), "\\n")',
      'cat("LIB:", renv::paths$library(project = getwd()), "\\n")',
      sep = "; "
    )
  )
  expect_match(out, "RENV: TRUE", fixed = TRUE, all = FALSE)
  expect_match(out, "LIB: ", fixed = TRUE, all = FALSE)
  expect_no_match(out, "Rscript --vanilla setup.R", fixed = TRUE)
})

test_that("setup.R stops outside a project root", {
  root <- local_portable_project(lock = FALSE)
  write_portable_setup(root, ref = sha, verbose = FALSE)
  out <- run_vanilla(root, 'source("setup.R")')
  expect_match(
    out,
    "Run setup.R from a project root",
    fixed = TRUE,
    all = FALSE
  )
})

test_that("restore_portable_project restores, then records startup data", {
  root <- local_portable_project()
  restored <- NULL
  local_mocked_bindings(restore_project = function(root, require_binaries) {
    restored <<- list(root = root, require_binaries = require_binaries)
    invisible("records")
  })
  expect_identical(
    restore_portable_project(root, require_binaries = "duckdb"),
    "records"
  )
  expect_identical(restored$require_binaries, "duckdb")
  startup <- readLines(file.path(root, "renv", "local", "startup"))
  expect_identical(
    startup,
    c(dirname(find.package("renv")), R.version$platform, portable_r_minor())
  )
  expect_identical(
    readLines(file.path(root, "renv", "local", ".gitignore")),
    "*"
  )
  expect_false(file.exists(file.path(root, ".Rprofile")))
})

test_that("restore_project and snapshot_project still write no startup files", {
  root <- local_portable_project()
  local_mocked_bindings(
    call_renv_restore = function(...) invisible(NULL),
    ensure_project_renv = function(root) invisible(NULL),
    call_renv_snapshot = function(root) invisible(NULL)
  )
  withr::local_options(
    repos = getOption("repos"),
    renv.config.repos.override = getOption("renv.config.repos.override")
  )
  restore_project(root)
  snapshot_project(root)
  expect_false(file.exists(file.path(root, ".Rprofile")))
  expect_false(file.exists(file.path(root, "setup.R")))
  expect_false(dir.exists(file.path(root, "renv", "local")))
})

test_that("deinit removes the portable block only together with renv", {
  root <- local_portable_project(c("x <- 1"))
  write_portable_setup(root, ref = sha, verbose = FALSE)
  profile <- file.path(root, ".Rprofile")
  before <- readLines(profile)

  result <- deinit(
    root,
    renv = FALSE,
    boosters = FALSE,
    rprofile = TRUE,
    lockfile = FALSE,
    air = FALSE,
    force = TRUE,
    verbose = FALSE
  )
  expect_false(result$rprofile_changed)
  expect_identical(readLines(profile), before)

  result <- deinit(
    root,
    renv = TRUE,
    boosters = FALSE,
    rprofile = TRUE,
    lockfile = FALSE,
    air = FALSE,
    force = TRUE,
    verbose = FALSE
  )
  expect_true(result$rprofile_changed)
  expect_identical(readLines(profile), "x <- 1")
  expect_true(file.exists(file.path(root, "setup.R")))
})

test_that("deinit preserves a malformed portable block and warns", {
  root <- local_portable_project(c(
    "x <- 1",
    rprofile_portable_begin_marker(),
    "y <- 2"
  ))
  expect_warning(
    deinit(
      root,
      renv = TRUE,
      boosters = FALSE,
      rprofile = TRUE,
      lockfile = FALSE,
      air = FALSE,
      force = TRUE,
      verbose = FALSE
    ),
    "malformed or unmatched"
  )
  expect_true(
    rprofile_portable_begin_marker() %in%
      readLines(file.path(root, ".Rprofile"))
  )
})

test_that("deinit keeps the portable block as the renv activation when asked", {
  root <- local_portable_project()
  write_portable_setup(root, ref = sha, verbose = FALSE)
  profile <- file.path(root, ".Rprofile")
  before <- readLines(profile)
  # renv = TRUE with rprofile = FALSE keeps the loader, and says why.
  result <- deinit(
    root,
    renv = TRUE,
    boosters = FALSE,
    rprofile = FALSE,
    lockfile = FALSE,
    air = FALSE,
    force = TRUE,
    verbose = FALSE
  )
  expect_identical(readLines(profile), before)
  expect_true(any(grepl(
    "renv activation preserved by request",
    unlist(result$preserved)
  )))
})

test_that("the pin is read back only from a generated setup.R", {
  root <- local_portable_project()
  expect_null(portable_setup_pin(root))
  write_portable_setup(root, ref = sha, verbose = FALSE)
  expect_identical(portable_setup_pin(root), sha)

  writeLines(sprintf('ref <- "%s"', sha), file.path(root, "setup.R"))
  expect_null(portable_setup_pin(root))
})

test_that("installed_boosterpak_sha reads only GitHub installs", {
  expect_identical(
    installed_boosterpak_sha(list(RemoteType = "github", RemoteSha = sha)),
    sha
  )
  expect_true(is.na(installed_boosterpak_sha(list(RemoteType = "local"))))
  expect_true(is.na(installed_boosterpak_sha(list(Version = "1.0.0"))))
  expect_true(is.na(installed_boosterpak_sha(list(
    RemoteType = "github",
    RemoteSha = NA_character_
  ))))
})
