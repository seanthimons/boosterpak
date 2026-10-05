# Pin the suite to the generic repository path; Linux binary tests opt in.
local_mocked_bindings(
  is_glibc_linux = function() FALSE,
  .package = "boosterpak",
  .env = teardown_env()
)
