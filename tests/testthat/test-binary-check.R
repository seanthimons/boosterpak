# The curl redirect warning reads these options, so pin them to keep tests
# independent of the session running them.
local_default_download_options <- function(.env = parent.frame()) {
  withr::local_options(
    download.file.method = NULL,
    download.file.extra = NULL,
    .local_envir = .env
  )
}

# A package index shaped like utils::available.packages(): a character matrix
# with one row per package, named by package. `versions` is a named character
# vector of current versions and `needs` names the packages that compile.
test_index <- function(versions = character(), needs = character()) {
  package <- names(versions) %||% character()
  index <- cbind(
    Package = package,
    Version = unname(versions),
    NeedsCompilation = ifelse(package %in% needs, "yes", "no")
  )
  rownames(index) <- package
  index
}

mock_binary_check <- function(
  type = "binary",
  tag = "4.6-manylinux_2_28",
  status = 200L,
  version = "3.6.6",
  .env = parent.frame()
) {
  local_default_download_options(.env)
  headers <- c(`x-package-type` = type, `x-package-binary-tag` = tag)
  versions <- if (is.na(version)) character() else c(cli = version)
  local_mocked_bindings(
    is_linux = function() TRUE,
    fetch_package_index = function(contriburl) {
      list(index = test_index(versions), error = NULL)
    },
    fetch_package_headers = function(url) {
      if (is.null(status)) {
        return(list(error = "Timeout was reached"))
      }
      list(status = status, headers = headers[!is.na(headers)])
    },
    .env = .env
  )
}

# Serve fixed indexes keyed by contrib URL, so lockfile checks run offline. A
# URL without an index fails the way an unreachable repository does. Returns an
# environment whose `contriburls` field records every index request in order.
# `configured` and `glibc` set whether boosterpak rewrites the lockfile URLs to
# the manylinux binary URL on this machine.
mock_lockfile_check <- function(
  indexes,
  configured = TRUE,
  glibc = TRUE,
  .env = parent.frame()
) {
  local_default_download_options(.env)
  requests <- new.env(parent = emptyenv())
  requests$contriburls <- character()
  local_mocked_bindings(
    is_linux = function() TRUE,
    is_glibc_linux = function() glibc,
    should_configure_repositories = function() configured,
    fetch_package_index = function(contriburl) {
      requests$contriburls <- c(requests$contriburls, contriburl)
      index <- indexes[[contriburl]]
      if (is.null(index)) {
        return(list(index = NULL, error = "not served"))
      }
      list(index = index, error = NULL)
    },
    fetch_package_headers = function(url) {
      list(
        status = 200L,
        headers = c(
          `x-package-type` = "binary",
          `x-package-binary-tag` = "4.6-manylinux_2_28"
        )
      )
    },
    .env = .env
  )
  requests
}

# A renv.lock entry. `repository = NULL` makes a non-repository (GitHub) pin.
lock_pin <- function(package, version, repository = "CRAN") {
  if (is.null(repository)) {
    return(list(Package = package, Version = version, Source = "GitHub"))
  }
  list(Package = package, Version = version, Source = "Repository", Repository = repository)
}

# Write an renv.lock with the given recorded repositories and pins, in the
# layout renv writes, and return its path.
local_test_lockfile <- function(
  pins,
  repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"),
  .env = parent.frame()
) {
  path <- withr::local_tempfile(fileext = ".lock", .local_envir = .env)
  recorded <- unname(Map(
    function(name, url) list(Name = name, URL = url),
    names(repos),
    repos
  ))
  packages <- stats::setNames(
    pins,
    vapply(pins, function(pin) pin$Package, character(1))
  )
  jsonlite::write_json(
    list(R = list(Version = "4.6.1", Repositories = recorded), Packages = packages),
    path,
    auto_unbox = TRUE,
    pretty = TRUE
  )
  path
}

ppm_repos <- function() {
  c(CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest")
}

test_that("parse_response_headers reads only the final response", {
  lines <- c(
    "HTTP/2 302 \r\n",
    "location: https://cdn.example.test/cli.tar.gz\r\n",
    "x-package-type: source\r\n",
    "\r\n",
    "HTTP/2 200 \r\n",
    "Content-Type: binary/octet-stream\r\n",
    "X-Package-Type: binary\r\n",
    "x-package-binary-tag: 4.6-manylinux_2_28\r\n",
    "\r\n"
  )

  headers <- boosterpak:::parse_response_headers(lines)

  expect_equal(headers[["x-package-type"]], "binary")
  expect_equal(headers[["x-package-binary-tag"]], "4.6-manylinux_2_28")
  expect_false("location" %in% names(headers))
  expect_length(boosterpak:::parse_response_headers(character()), 0L)
  expect_length(boosterpak:::parse_response_headers("HTTP/2 200 \r\n"), 0L)
})

test_that("check_binary_repos reports binaries", {
  mock_binary_check()
  local_ppm_hosts()

  expect_no_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE)
  )

  expect_equal(nrow(result), 1L)
  expect_equal(result$name, "CRAN")
  expect_equal(result$package, "cli")
  expect_equal(result$version, "3.6.6")
  expect_equal(result$status, 200L)
  expect_equal(result$package_type, "binary")
  expect_equal(result$binary_tag, "4.6-manylinux_2_28")
  expect_true(result$binary)
  expect_message(
    check_binary_repos(ppm_repos(), verbose = TRUE),
    "serving binary packages"
  )
})

test_that("check_binary_repos warns when Package Manager serves source", {
  mock_binary_check(type = "source", tag = NA)
  local_ppm_hosts()
  repos <- c(CRAN = "https://p3m.dev/cran/latest")

  expect_warning(
    result <- check_binary_repos(repos, verbose = FALSE),
    "serving source packages"
  )
  expect_equal(result$package_type, "source")
  expect_true(is.na(result$binary_tag))
  expect_false(result$binary)
  expect_warning(
    check_binary_repos(repos, verbose = FALSE),
    "__linux__/manylinux_2_28/latest",
    fixed = TRUE
  )
})

test_that("check_binary_repos handles failed and unusual responses", {
  local_ppm_hosts()

  mock_binary_check(status = NULL)
  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "failed (Timeout was reached)",
    fixed = TRUE
  )
  expect_true(is.na(result$binary))
  expect_equal(result$version, "3.6.6")

  mock_binary_check(status = 404L)
  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "HTTP 404"
  )
  expect_equal(result$status, 404L)

  mock_binary_check(type = NA, tag = NA)
  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "no X-Package-Type header"
  )
  expect_true(is.na(result$binary))
})

test_that("check_binary_repos tolerates a missing package", {
  mock_binary_check(version = NA_character_)
  local_ppm_hosts()

  expect_no_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE)
  )
  expect_true(is.na(result$version))
  expect_true(is.na(result$status))
  expect_true(is.na(result$binary))
  expect_message(
    check_binary_repos(ppm_repos(), verbose = TRUE),
    "is not in this repository"
  )
})

test_that("curl_lacks_redirect_flag finds the redirect flag in any form", {
  lacks <- boosterpak:::curl_lacks_redirect_flag
  ua <- '--header "User-Agent: R (4.6.1 x86_64-pc-linux-gnu x86_64 linux-gnu)"'

  # curl without a redirect flag
  expect_true(lacks("curl", NULL))
  expect_true(lacks("curl", character()))
  expect_true(lacks("curl", "-fsS"))
  expect_true(lacks("curl", ua))
  expect_true(lacks("curl", c("-sS", ua)))
  expect_true(lacks("curl", "--limit-rate 1M"))
  expect_true(lacks("curl", '-w "%{http_code}"'))

  # curl with one
  expect_false(lacks("curl", "-L"))
  expect_false(lacks("curl", "-fsSL"))
  expect_false(lacks("curl", "-4L"))
  expect_false(lacks("curl", paste("-fsSL", ua)))
  expect_false(lacks("curl", c("-sS", "-L", ua)))
  expect_false(lacks("curl", "--location"))
  expect_false(lacks("curl", "--location-trusted --fail"))
  expect_false(lacks("curl", paste(ua, "-L")))

  # other methods never need it
  expect_false(lacks(NULL, NULL))
  expect_false(lacks("libcurl", NULL))
  expect_false(lacks("wget", NULL))
  expect_false(lacks("internal", "-fsS"))
})

test_that("check_binary_repos warns when curl cannot follow redirects", {
  mock_binary_check()
  local_ppm_hosts()
  withr::local_options(
    download.file.method = "curl",
    download.file.extra = "-fsS"
  )

  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "has no .-L."
  )
  # The check itself still ran and passed, which is why the warning exists.
  expect_true(result$binary)
  expect_warning(
    check_binary_repos(ppm_repos(), verbose = FALSE),
    "redirect page"
  )
})

test_that("check_binary_repos stays quiet when redirects are followed", {
  mock_binary_check()
  local_ppm_hosts()

  for (setup in list(
    list(method = "curl", extra = "-fsSL"),
    list(method = "curl", extra = "--location"),
    list(method = "wget", extra = NULL),
    list(method = "libcurl", extra = NULL),
    list(method = NULL, extra = NULL)
  )) {
    withr::local_options(
      download.file.method = setup$method,
      download.file.extra = setup$extra
    )
    expect_no_warning(check_binary_repos(ppm_repos(), verbose = FALSE))
  }
})

test_that("the curl redirect warning needs a Package Manager repository", {
  mock_binary_check()
  local_ppm_hosts()
  withr::local_options(
    download.file.method = "curl",
    download.file.extra = NULL
  )

  expect_no_warning(
    check_binary_repos(c(CRAN = "https://example.test/repo"), verbose = FALSE)
  )
})

test_that("check_binary_repos warns about an unreadable package index", {
  local_ppm_hosts()
  local_default_download_options()
  local_mocked_bindings(
    is_linux = function() TRUE,
    fetch_package_index = function(contriburl) {
      list(index = NULL, error = "cannot open URL")
    }
  )

  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "could not read the package index (cannot open URL)",
    fixed = TRUE
  )
  expect_true(is.na(result$binary))
})

test_that("check_binary_repos warns about an unexpected package type", {
  mock_binary_check(type = "mystery")
  local_ppm_hosts()

  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "unexpected X-Package-Type",
    fixed = FALSE
  )
  expect_false(result$binary)
})

test_that("check_binary_repos explains source on a binary URL", {
  mock_binary_check(type = "source", tag = NA)
  local_ppm_hosts()

  expect_warning(
    check_binary_repos(ppm_repos(), verbose = FALSE),
    "already selects binaries.*HTTPUserAgent"
  )
})

test_that("the source hint depends on the repository URL", {
  local_ppm_hosts()

  generic <- boosterpak:::source_hint("https://p3m.dev/cran/latest/")
  expect_match(generic, "__linux__/manylinux_2_28/latest", fixed = TRUE)
  expect_false(grepl("//", sub("https://", "", generic, fixed = TRUE), fixed = TRUE))

  linux <- boosterpak:::source_hint(
    "https://p3m.dev/cran/__linux__/manylinux_2_28/latest"
  )
  expect_match(linux, "already selects binaries", fixed = TRUE)
  expect_match(linux, "HTTPUserAgent", fixed = TRUE)

  # A distro URL is not a manylinux URL, so it gets neither of the above.
  distro <- boosterpak:::source_hint(
    "https://p3m.dev/cran/__linux__/noble/latest"
  )
  expect_false(grepl("already selects binaries", distro, fixed = TRUE))
  expect_match(distro, "Use a binary URL for your platform", fixed = TRUE)

  # Braces in a URL must not be read as cli templates.
  braces <- boosterpak:::source_hint("https://p3m.dev/cra{n}/latest")
  expect_no_error(cli::format_inline(braces))
})

test_that("check_binary_repos skips other repositories and handles many", {
  mock_binary_check()
  local_ppm_hosts()
  repos <- c(
    CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest",
    Internal = "https://example.test/repo",
    Snap = "https://p3m.dev/cran/__linux__/manylinux_2_28/2026-01-02"
  )

  result <- check_binary_repos(repos, verbose = FALSE)

  expect_equal(result$name, c("CRAN", "Snap"))
  expect_equal(nrow(result), 2L)

  result <- check_binary_repos(
    unname(repos[1]),
    verbose = FALSE
  )
  expect_equal(result$name, "")

  expect_message(
    result <- check_binary_repos(c(CRAN = "https://example.test/repo"), verbose = TRUE),
    "No Posit Package Manager repositories"
  )
  expect_equal(nrow(result), 0L)
})

test_that("check_binary_repos recognizes self-hosted Package Manager hosts", {
  mock_binary_check()
  local_ppm_hosts(repo = "https://ppm.corp.test/team-cran/latest")

  result <- check_binary_repos(
    c(Team = "https://ppm.corp.test/team-cran/__linux__/manylinux_2_28/latest"),
    verbose = FALSE
  )

  expect_equal(nrow(result), 1L)
  expect_true(result$binary)
})

test_that("check_binary_repos only runs on Linux", {
  local_mocked_bindings(
    is_linux = function() FALSE,
    fetch_package_index = function(...) stop("unexpected request"),
    fetch_package_headers = function(...) stop("unexpected request")
  )

  expect_message(
    result <- check_binary_repos(ppm_repos(), verbose = TRUE),
    "only supports Linux"
  )
  expect_equal(nrow(result), 0L)
  expect_named(
    result,
    c(
      "repo", "name", "package", "version", "status", "package_type",
      "binary_tag", "binary"
    )
  )
})

test_that("check_binary_repos validates its arguments", {
  expect_error(check_binary_repos(package = NA_character_), "single package name")
  expect_error(check_binary_repos(package = c("a", "b")), "single package name")
  expect_error(check_binary_repos(verbose = "yes"), "verbose")
  expect_error(
    check_binary_repos(repos = ppm_repos(), lockfile = "renv.lock"),
    "not both"
  )
  expect_error(
    check_binary_repos(snapshot_dates = "2026-10-14"),
    "needs .*lockfile"
  )

  missing <- withr::local_tempfile(fileext = ".lock")
  expect_error(check_binary_repos(lockfile = missing), "does not exist")
  expect_error(
    check_binary_repos(lockfile = c("a.lock", "b.lock")),
    "single file path"
  )
  not_renv <- withr::local_tempfile(fileext = ".lock")
  writeLines("{}", not_renv)
  expect_error(check_binary_repos(lockfile = not_renv), "not a readable")

  lockfile <- local_test_lockfile(list(lock_pin("cli", "3.6.6")))
  expect_error(
    check_binary_repos(lockfile = lockfile, snapshot_dates = "2026-13-01"),
    "YYYY-MM-DD"
  )
  expect_error(
    check_binary_repos(lockfile = lockfile, snapshot_dates = "latest"),
    "YYYY-MM-DD"
  )
})

test_that("ppm_binary_url selects the manylinux binary URL", {
  manylinux <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"

  expect_equal(
    boosterpak:::ppm_binary_url("https://packagemanager.posit.co/cran/latest"),
    manylinux
  )
  expect_equal(
    boosterpak:::ppm_binary_url(c(CRAN = "https://p3m.dev/cran/2026-01-02")),
    c(CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/2026-01-02")
  )
  expect_equal(
    boosterpak:::ppm_binary_url(
      "https://packagemanager.posit.co/cran/latest",
      snapshot = "2026-10-14"
    ),
    "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/2026-10-14"
  )
  # Already binary, a distro URL, and other hosts are left as they are.
  expect_equal(boosterpak:::ppm_binary_url(manylinux), manylinux)
  distro <- "https://packagemanager.posit.co/cran/__linux__/noble/latest"
  expect_equal(boosterpak:::ppm_binary_url(distro), distro)
  other <- "https://example.test/cran/latest"
  expect_equal(boosterpak:::ppm_binary_url(other), other)

  # A distro URL keeps its distro when the snapshot changes, and a trailing
  # slash is dropped.
  expect_equal(
    boosterpak:::ppm_binary_url(distro, snapshot = "2026-10-14"),
    "https://packagemanager.posit.co/cran/__linux__/noble/2026-10-14"
  )
  expect_equal(boosterpak:::ppm_binary_url(paste0(distro, "/")), distro)
  expect_equal(
    boosterpak:::ppm_binary_url("https://packagemanager.posit.co/cran/latest/", snapshot = "2026-10-14"),
    "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/2026-10-14"
  )
  # A Package Manager URL with no snapshot segment cannot be moved to a date.
  odd <- "https://packagemanager.posit.co/cran/a/b/latest"
  expect_true(is.na(boosterpak:::ppm_binary_url(odd, snapshot = "2026-10-14")))
  expect_equal(boosterpak:::ppm_binary_url(odd), odd)
})

test_that("read_lockfile_repos keeps recorded repositories and repository pins", {
  path <- local_test_lockfile(
    list(lock_pin("cli", "3.6.6"), lock_pin("localpkg", "0.1", repository = NULL)),
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )

  lock <- boosterpak:::read_lockfile_repos(path)

  expect_equal(lock$repos, c(CRAN = "https://packagemanager.posit.co/cran/latest"))
  expect_equal(
    lock$pins,
    data.frame(
      package = "cli",
      version = "3.6.6",
      repository = "CRAN",
      resolved = "CRAN",
      stringsAsFactors = FALSE
    )
  )
})

test_that("resolve_pin_repositories matches names, URLs and the single Package Manager repository", {
  local_ppm_hosts()
  repos <- c(
    CRAN = "https://packagemanager.posit.co/cran/latest",
    Internal = "https://example.test/repo"
  )
  values <- c(
    "CRAN", "RSPM", "https://packagemanager.posit.co/cran/latest",
    "https://packagemanager.posit.co/cran/latest/", "Internal",
    "https://other.test/cran", "", "Missing"
  )

  expect_equal(
    boosterpak:::resolve_pin_repositories(values, repos),
    c("CRAN", "CRAN", "CRAN", "CRAN", "Internal", NA, NA, "CRAN")
  )
  # Without a Package Manager repository, or with two, an unknown name matches nothing.
  expect_equal(
    boosterpak:::resolve_pin_repositories("RSPM", c(Internal = "https://example.test/repo")),
    NA_character_
  )
  two <- c(
    A = "https://packagemanager.posit.co/cran/latest",
    B = "https://p3m.dev/cran/latest"
  )
  expect_equal(boosterpak:::resolve_pin_repositories("RSPM", two), NA_character_)
})

test_that("lockfile pins named RSPM or given as URLs are compared with Package Manager", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(
      lock_pin("cli", "3.6.6", repository = "RSPM"),
      lock_pin("duckdb", "1.5.6", repository = "https://packagemanager.posit.co/cran/latest/"),
      lock_pin("arrow", "21.0.0.1", repository = "https://packagemanager.posit.co/cran/latest"),
      lock_pin("V8", "4.4.2", repository = "Internal")
    ),
    repos = c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      Internal = "https://example.test/repo"
    )
  )
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  requests <- mock_lockfile_check(stats::setNames(
    list(test_index(
      c(cli = "3.6.6", duckdb = "1.5.6", arrow = "25.0.1"),
      needs = "arrow"
    )),
    latest
  ))

  # V8 comes from Internal, which is not Package Manager, so it is reported
  # even with verbose = FALSE.
  expect_message(
    expect_warning(
      result <- check_binary_repos(lockfile = path, verbose = FALSE),
      "2 of 3 pins available as binary"
    ),
    "1 repository pin not compared"
  )

  expect_equal(requests$contriburls, latest)
  summary <- attr(result, "lockfile")
  expect_equal(summary$pins, 3L)
  expect_equal(summary$available, 2L)
  expect_equal(summary$unchecked, 1L)
  expect_equal(summary$repositories$pins, 3L)
  expect_equal(summary$offenders$package, "arrow")
})

test_that("lockfile messages show braces in names as text", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(
    lock_pin("cli", "3.6.6"),
    lock_pin("x{1+1}", "1.0")
  ))
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  mock_lockfile_check(stats::setNames(
    list(test_index(c(cli = "3.6.6"))),
    latest
  ))

  expect_warning(
    check_binary_repos(lockfile = path, verbose = FALSE),
    "x{1+1} 1.0 (not in the index)",
    fixed = TRUE
  )
})

test_that("snapshot messages show braces in repository names as text", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(lock_pin("cli", "3.6.6")),
    repos = c(`Snap{2}` = "https://packagemanager.posit.co/cran/2026-10-14")
  )
  dated <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/2026-10-14/src/contrib"
  mock_lockfile_check(stats::setNames(list(test_index(c(cli = "3.6.6"))), dated))

  expect_message(
    check_binary_repos(lockfile = path, verbose = TRUE, snapshot_dates = "2026-10-14"),
    "Snap{2} 2026-10-14: 1 of 1 pins available as binary (best)",
    fixed = TRUE
  )
})

test_that("lockfile snapshot checks keep distro URLs and drop trailing slashes", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(lock_pin("cli", "3.6.6"), lock_pin("duckdb", "1.5.2")),
    repos = c(Noble = "https://packagemanager.posit.co/cran/__linux__/noble/latest/")
  )
  base <- "https://packagemanager.posit.co/cran/__linux__/noble"
  requests <- mock_lockfile_check(stats::setNames(
    list(
      test_index(c(cli = "3.6.6", duckdb = "1.5.2")),
      test_index(c(cli = "3.6.6", duckdb = "1.5.6"))
    ),
    paste0(base, c("/latest", "/2026-10-14"), "/src/contrib")
  ))

  expect_no_warning(
    result <- check_binary_repos(
      lockfile = path,
      verbose = FALSE,
      snapshot_dates = "2026-10-14"
    )
  )

  expect_equal(
    requests$contriburls,
    c(paste0(base, "/latest/src/contrib"), paste0(base, "/2026-10-14/src/contrib"))
  )
  expect_equal(result$repo, paste0(base, "/latest"))
  snapshots <- attr(result, "lockfile")$snapshots
  expect_equal(snapshots$repository, "Noble")
  expect_equal(snapshots$date, "2026-10-14")
  expect_equal(snapshots$available, 1L)
})

test_that("lockfile snapshot checks skip URLs that cannot name a snapshot", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(lock_pin("cli", "3.6.6")),
    repos = c(Odd = "https://packagemanager.posit.co/cran/a/b/latest")
  )
  odd <- "https://packagemanager.posit.co/cran/a/b/latest/src/contrib"
  requests <- mock_lockfile_check(stats::setNames(
    list(test_index(c(cli = "3.6.6"))),
    odd
  ))

  expect_warning(
    result <- check_binary_repos(
      lockfile = path,
      verbose = FALSE,
      snapshot_dates = "2026-10-14"
    ),
    "Odd: the repository URL has no snapshot segment to change",
    fixed = TRUE
  )

  expect_equal(requests$contriburls, odd)
  expect_equal(nrow(attr(result, "lockfile")$snapshots), 0L)
})

test_that("compare_pins_to_index separates available, outdated and absent pins", {
  index <- test_index(c(cli = "3.6.6", duckdb = "1.5.6"), needs = "duckdb")
  pins <- data.frame(
    package = c("cli", "duckdb", "gone"),
    version = c("3.6.6", "1.5.2", "1.0"),
    stringsAsFactors = FALSE
  )

  comparison <- boosterpak:::compare_pins_to_index(pins, index)

  expect_equal(comparison$available, c(TRUE, FALSE, FALSE))
  expect_equal(comparison$current, c("3.6.6", "1.5.6", NA))
  expect_equal(comparison$needs_compilation, c(FALSE, TRUE, FALSE))
})

test_that("check_binary_repos compares lockfile pins with the repository index", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(
      lock_pin("cli", "3.6.6"),
      lock_pin("duckdb", "1.5.2"),
      lock_pin("arrow", "21.0.0.1"),
      lock_pin("V8", "4.4.2"),
      lock_pin("gone", "1.0.0"),
      lock_pin("localpkg", "0.1", repository = NULL),
      lock_pin("inhouse", "1.0", repository = "Internal")
    ),
    repos = c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      Internal = "https://example.test/repo"
    )
  )
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  requests <- mock_lockfile_check(stats::setNames(
    list(test_index(
      c(cli = "3.6.6", duckdb = "1.5.6", arrow = "25.0.1", V8 = "4.4.2"),
      needs = c("duckdb", "arrow", "V8")
    )),
    latest
  ))

  expect_message(
    expect_warning(
      result <- check_binary_repos(lockfile = path, verbose = FALSE),
      "2 of 5 pins available as binary"
    ),
    "1 repository pin not compared"
  )

  # One index request per Package Manager repository, at the binary URL.
  expect_equal(requests$contriburls, latest)
  expect_equal(nrow(result), 1L)
  expect_equal(result$repo, sub("/src/contrib$", "", latest))
  expect_true(result$binary)

  summary <- attr(result, "lockfile")
  expect_equal(summary$lockfile, path)
  expect_equal(summary$pins, 5L)
  expect_equal(summary$available, 2L)
  expect_equal(summary$unavailable, 3L)
  expect_equal(summary$needs_compilation, 2L)
  expect_equal(summary$not_in_index, 1L)
  expect_equal(summary$unchecked, 1L)
  expect_equal(summary$repositories$repository, "CRAN")
  expect_equal(summary$repositories$available, 2L)
  expect_null(summary$snapshots)
  expect_equal(summary$offenders$package, c("arrow", "duckdb", "gone"))
  expect_equal(summary$offenders$current, c("25.0.1", "1.5.6", NA))
  expect_equal(summary$offenders$needs_compilation, c(TRUE, TRUE, FALSE))
})

test_that("check_binary_repos lists the worst lockfile offenders", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(
    lock_pin("cli", "3.6.6"),
    lock_pin("arrow", "21.0.0.1")
  ))
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  mock_lockfile_check(stats::setNames(
    list(test_index(c(cli = "3.6.6", arrow = "25.0.1"), needs = "arrow")),
    latest
  ))

  expect_warning(
    check_binary_repos(lockfile = path, verbose = FALSE),
    "arrow 21.0.0.1 (index: 25.0.1)",
    fixed = TRUE
  )
})

test_that("check_binary_repos reports a lockfile whose pins are all binaries", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(
    lock_pin("cli", "3.6.6"),
    lock_pin("V8", "4.4.2")
  ))
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  mock_lockfile_check(stats::setNames(
    list(test_index(c(cli = "3.6.6", V8 = "4.4.2"), needs = "V8")),
    latest
  ))

  expect_no_warning(
    result <- check_binary_repos(lockfile = path, verbose = FALSE)
  )
  summary <- attr(result, "lockfile")
  expect_equal(summary$available, 2L)
  expect_equal(summary$unavailable, 0L)
  expect_equal(nrow(summary$offenders), 0L)
  expect_message(
    check_binary_repos(lockfile = path, verbose = TRUE),
    "2 of 2 pins available as binary"
  )
})

test_that("lockfile checks use the binary URL recorded for each snapshot", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(lock_pin("cli", "3.6.6"), lock_pin("duckdb", "1.5.2")),
    repos = c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      Snap = "https://packagemanager.posit.co/cran/2026-10-14"
    )
  )
  base <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28"
  requests <- mock_lockfile_check(list(
    "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib" =
      test_index(c(cli = "3.6.6", duckdb = "1.5.2")),
    "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/2026-10-14/src/contrib" =
      test_index(c(cli = "3.6.6", duckdb = "1.5.2"))
  ))

  expect_no_warning(result <- check_binary_repos(lockfile = path, verbose = FALSE))

  expect_equal(
    requests$contriburls,
    c(
      paste0(base, "/latest/src/contrib"),
      paste0(base, "/2026-10-14/src/contrib")
    )
  )
  expect_equal(
    result$repo,
    c(paste0(base, "/latest"), paste0(base, "/2026-10-14"))
  )
  expect_equal(attr(result, "lockfile")$repositories$repository, c("CRAN", "Snap"))
})

test_that("lockfile checks probe the recorded URL when boosterpak does not rewrite it", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(lock_pin("cli", "3.6.6")))
  generic <- "https://packagemanager.posit.co/cran/latest/src/contrib"
  indexes <- stats::setNames(list(test_index(c(cli = "3.6.6"))), generic)

  requests <- mock_lockfile_check(indexes, configured = FALSE)
  expect_no_warning(check_binary_repos(lockfile = path, verbose = FALSE))
  expect_equal(requests$contriburls, generic)

  requests <- mock_lockfile_check(indexes, glibc = FALSE)
  expect_no_warning(check_binary_repos(lockfile = path, verbose = FALSE))
  expect_equal(requests$contriburls, generic)
})

test_that("snapshot checks use the same URL form as the latest row when not rewritten", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(lock_pin("cli", "3.6.6")))
  # The recorded URL is generic and boosterpak does not rewrite it, so the
  # dated snapshot must keep the generic form instead of gaining __linux__.
  latest <- "https://packagemanager.posit.co/cran/latest/src/contrib"
  dated <- "https://packagemanager.posit.co/cran/2026-10-14/src/contrib"
  requests <- mock_lockfile_check(
    stats::setNames(list(test_index(c(cli = "3.6.6")), test_index(c(cli = "3.6.6"))), c(latest, dated)),
    configured = FALSE
  )
  result <- check_binary_repos(
    lockfile = path,
    verbose = FALSE,
    snapshot_dates = "2026-10-14"
  )

  expect_equal(requests$contriburls, c(latest, dated))
  expect_false(any(grepl("__linux__", requests$contriburls, fixed = TRUE)))
  snapshots <- attr(result, "lockfile")$snapshots
  expect_equal(snapshots$repository, "CRAN")
  expect_equal(snapshots$date, "2026-10-14")
  expect_equal(snapshots$available, 1L)
})

test_that("ppm_binary_url swaps only the snapshot segment without the rewrite", {
  local_ppm_hosts()
  generic <- "https://packagemanager.posit.co/cran/latest"
  expect_equal(
    boosterpak:::ppm_binary_url(generic, snapshot = "2026-10-14", rewrite = FALSE),
    "https://packagemanager.posit.co/cran/2026-10-14"
  )
  expect_equal(
    boosterpak:::ppm_binary_url(generic, rewrite = FALSE),
    generic
  )
  distro <- "https://packagemanager.posit.co/cran/__linux__/noble/latest"
  expect_equal(
    boosterpak:::ppm_binary_url(distro, snapshot = "2026-10-14", rewrite = FALSE),
    "https://packagemanager.posit.co/cran/__linux__/noble/2026-10-14"
  )
})

test_that("lockfile checks pick the best snapshot date within each repository", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(
      lock_pin("cli", "3.6.6", repository = "CRAN"),
      lock_pin("duckdb", "1.5.2", repository = "Other")
    ),
    repos = c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      Other = "https://p3m.dev/cran/latest"
    )
  )
  posit <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28"
  p3m <- "https://p3m.dev/cran/__linux__/manylinux_2_28"
  mock_lockfile_check(stats::setNames(
    list(
      test_index(c(cli = "3.6.6")),
      test_index(c(duckdb = "1.5.2")),
      test_index(c(cli = "3.6.6")),
      test_index(c(cli = "3.6.5")),
      test_index(c(duckdb = "1.5.1")),
      test_index(c(duckdb = "1.5.2"))
    ),
    c(
      paste0(posit, "/latest/src/contrib"),
      paste0(p3m, "/latest/src/contrib"),
      paste0(posit, "/2026-10-14/src/contrib"),
      paste0(posit, "/2026-09-01/src/contrib"),
      paste0(p3m, "/2026-10-14/src/contrib"),
      paste0(p3m, "/2026-09-01/src/contrib")
    )
  ))

  messages <- testthat::capture_messages(
    check_binary_repos(
      lockfile = path,
      verbose = TRUE,
      snapshot_dates = c("2026-10-14", "2026-09-01")
    )
  )

  text <- paste(messages, collapse = "\n")
  # CRAN is best on 2026-10-14 and Other on 2026-09-01. A single global best
  # would mark only one of them.
  expect_match(text, "CRAN 2026-10-14: 1 of 1 pins available as binary (best)", fixed = TRUE)
  expect_match(text, "Other 2026-09-01: 1 of 1 pins available as binary (best)", fixed = TRUE)
  expect_false(grepl("CRAN 2026-09-01: 0 of 1 pins available as binary (best)", text, fixed = TRUE))
  expect_false(grepl("Other 2026-10-14: 0 of 1 pins available as binary (best)", text, fixed = TRUE))
})

test_that("the lockfile warning omits the offender list when no pin needs compilation", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(lock_pin("cli", "3.6.6")))
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  mock_lockfile_check(stats::setNames(
    list(test_index(c(cli = "3.6.7"))),
    latest
  ))

  warnings <- testthat::capture_warnings(
    result <- check_binary_repos(lockfile = path, verbose = FALSE)
  )

  summary <- attr(result, "lockfile")
  expect_equal(summary$unavailable, 1L)
  expect_equal(nrow(summary$offenders), 0L)
  expect_length(warnings, 1L)
  expect_true(any(grepl("1 not available as binary", warnings, fixed = TRUE)))
  expect_false(any(grepl("Worst offenders", warnings, fixed = TRUE)))
})

test_that("the lockfile warning says how many offenders it leaves out", {
  local_ppm_hosts()
  packages <- sprintf("pkg%02d", 1:12)
  path <- local_test_lockfile(lapply(packages, lock_pin, version = "1.0.0"))
  latest <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest/src/contrib"
  mock_lockfile_check(stats::setNames(
    list(test_index(stats::setNames(rep("2.0.0", 12), packages), needs = packages)),
    latest
  ))

  warnings <- testthat::capture_warnings(
    result <- check_binary_repos(lockfile = path, verbose = FALSE)
  )

  expect_equal(nrow(attr(result, "lockfile")$offenders), 12L)
  expect_true(any(grepl("pkg01 1.0.0 (index: 2.0.0)", warnings, fixed = TRUE)))
  expect_true(any(grepl("and 2 more", warnings, fixed = TRUE)))
  expect_false(any(grepl("pkg11", warnings, fixed = TRUE)))
})

test_that("lockfile pins from other repositories are not checked", {
  local_ppm_hosts()
  path <- local_test_lockfile(
    list(lock_pin("cli", "3.6.6", repository = "Internal")),
    repos = c(Internal = "https://example.test/repo")
  )
  requests <- mock_lockfile_check(list())

  expect_message(
    result <- check_binary_repos(lockfile = path, verbose = FALSE),
    "1 repository pin not compared"
  )

  expect_length(requests$contriburls, 0L)
  expect_equal(nrow(result), 0L)
  summary <- attr(result, "lockfile")
  expect_equal(summary$pins, 0L)
  expect_equal(summary$unchecked, 1L)
})

test_that("snapshot_dates compares pins with only the dates given", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(
    lock_pin("cli", "3.6.6"),
    lock_pin("duckdb", "1.5.2")
  ))
  base <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28"
  requests <- mock_lockfile_check(stats::setNames(
    list(
      test_index(c(cli = "3.6.6", duckdb = "1.5.2")),
      test_index(c(cli = "3.6.6", duckdb = "1.5.2")),
      test_index(c(cli = "3.6.6", duckdb = "1.5.6"))
    ),
    paste0(base, c("/latest", "/2026-10-14", "/2026-09-01"), "/src/contrib")
  ))

  # 2026-08-01 is not served, so it is reported and left out.
  expect_warning(
    result <- check_binary_repos(
      lockfile = path,
      verbose = FALSE,
      snapshot_dates = c("2026-10-14", "2026-09-01", "2026-08-01")
    ),
    "CRAN (2026-08-01): could not read the package index",
    fixed = TRUE
  )

  expect_equal(
    requests$contriburls,
    c(
      paste0(base, "/latest/src/contrib"),
      paste0(base, "/2026-10-14/src/contrib"),
      paste0(base, "/2026-09-01/src/contrib"),
      paste0(base, "/2026-08-01/src/contrib")
    )
  )
  snapshots <- attr(result, "lockfile")$snapshots
  expect_equal(snapshots$date, c("2026-10-14", "2026-09-01"))
  expect_equal(snapshots$pins, c(2L, 2L))
  expect_equal(snapshots$available, c(2L, 1L))

  expect_message(
    check_binary_repos(
      lockfile = path,
      verbose = TRUE,
      snapshot_dates = c("2026-10-14", "2026-09-01")
    ),
    "2026-10-14: 2 of 2 pins available as binary \\(best\\)"
  )
})

test_that("snapshot listing marks one best date per repository and never zero", {
  local_ppm_hosts()
  path <- local_test_lockfile(list(lock_pin("cli", "3.6.6")))
  base <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28"
  mock_lockfile_check(stats::setNames(
    list(
      test_index(c(cli = "3.6.6")),
      test_index(c(cli = "3.6.6")),
      test_index(c(cli = "3.6.6")),
      test_index(c(cli = "3.6.5")),
      test_index(c(cli = "3.6.5"))
    ),
    paste0(base, c("/latest", "/2026-10-14", "/2026-09-01", "/2026-08-01", "/2026-07-01"), "/src/contrib")
  ))

  # Both dates reach the top count, so only the first one in the order given is
  # marked. The two 2026-08/07 dates have no exact pin, so neither is marked.
  text <- paste(
    testthat::capture_messages(suppressWarnings(check_binary_repos(
      lockfile = path,
      verbose = TRUE,
      snapshot_dates = c("2026-10-14", "2026-09-01")
    ))),
    collapse = ""
  )
  expect_match(text, "CRAN 2026-10-14: 1 of 1 pins available as binary (best)", fixed = TRUE)
  expect_match(text, "* CRAN 2026-09-01: 1 of 1 pins available as binary", fixed = TRUE)
  expect_false(grepl("CRAN 2026-09-01: 1 of 1 pins available as binary (best)", text, fixed = TRUE))

  text <- paste(
    testthat::capture_messages(suppressWarnings(check_binary_repos(
      lockfile = path,
      verbose = TRUE,
      snapshot_dates = c("2026-08-01", "2026-07-01")
    ))),
    collapse = ""
  )
  expect_match(text, "* CRAN 2026-08-01: 0 of 1 pins available as binary", fixed = TRUE)
  expect_false(grepl("(best)", text, fixed = TRUE))
})

test_that("check_binary_repos reads the lockfile but only checks on Linux", {
  path <- local_test_lockfile(list(lock_pin("cli", "3.6.6")))
  local_mocked_bindings(
    is_linux = function() FALSE,
    fetch_package_index = function(...) stop("unexpected request"),
    fetch_package_headers = function(...) stop("unexpected request")
  )

  expect_message(
    result <- check_binary_repos(lockfile = path, verbose = TRUE),
    "only supports Linux"
  )
  expect_equal(nrow(result), 0L)
})

test_that("check_binary_repos sees binaries on Package Manager", {
  skip_on_cran()
  skip_if_not(identical(R.version$os, "linux-gnu"))
  skip_if(grepl("development", R.version$status))
  skip_if_not_installed("curl")
  skip_if_offline("p3m.dev")
  local_ppm_hosts()
  local_default_download_options()
  withr::local_options(HTTPUserAgent = sprintf(
    "R/%s R (%s)",
    getRversion(),
    paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
  ))
  manylinux <- "https://p3m.dev/cran/__linux__/manylinux_2_28/latest"
  generic <- "https://p3m.dev/cran/latest"

  binary <- check_binary_repos(c(CRAN = manylinux), verbose = FALSE)
  expect_equal(binary$status, 200L)
  expect_equal(binary$package_type, "binary")
  expect_match(binary$binary_tag, "manylinux_2_28", fixed = TRUE)
  expect_true(binary$binary)

  expect_warning(
    source <- check_binary_repos(c(CRAN = generic), verbose = FALSE),
    "serving source packages"
  )
  expect_equal(source$package_type, "source")
  expect_false(source$binary)
})

# A valid file URL has three slashes before a Windows drive letter
# (file:///C:/...) and two before a Unix root path (file:///tmp/... as
# "file://" + "/tmp/...").
file_url <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  paste0("file://", if (startsWith(path, "/")) "" else "/", path)
}

test_that("fetch_package_index reads a repository package index", {
  repo <- withr::local_tempdir()
  contrib <- file.path(repo, "src", "contrib")
  dir.create(contrib, recursive = TRUE)
  writeLines(
    c("Package: cli", "Version: 3.6.6", "", "Package: other", "Version: 1.0"),
    file.path(contrib, "PACKAGES")
  )
  contriburl <- file_url(contrib)

  found <- boosterpak:::fetch_package_index(contriburl)
  expect_null(found$error)
  expect_equal(boosterpak:::index_version(found$index, "cli"), "3.6.6")
  expect_true(is.na(boosterpak:::index_version(found$index, "absent")))

  unreadable <- boosterpak:::fetch_package_index(
    file_url(file.path(repo, "nowhere"))
  )
  expect_null(unreadable$index)
  expect_type(unreadable$error, "character")
})

test_that("fetch_package_headers reports request failures", {
  skip_if_not_installed("curl")

  response <- boosterpak:::fetch_package_headers("http://127.0.0.1:1/cli_1.0.tar.gz")

  expect_type(response$error, "character")
  expect_null(response$status)
})
