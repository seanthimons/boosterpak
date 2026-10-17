# Pin the suite to the generic repository path; Linux binary tests opt in.
local_mocked_bindings(
  is_glibc_linux = function() FALSE,
  .package = "boosterpak",
  .env = teardown_env()
)
# status() checks the developer's git credential store for GitHub projects.
# Tests never run `git credential fill`; tests of that check mock it again.
local_mocked_bindings(
  gitcreds_lookup = function() NULL,
  .package = "boosterpak",
  .env = teardown_env()
)
