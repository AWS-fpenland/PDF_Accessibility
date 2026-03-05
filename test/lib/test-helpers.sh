#!/usr/bin/env bash
# =============================================================================
# test-helpers.sh — Shared test utilities for bats-core property-based tests
# =============================================================================

# Resolve the project root relative to this file
TEST_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_HELPERS_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the helpers under test
source "$LIB_DIR/pipeline-helpers.sh"

# ---------------------------------------------------------------------------
# PBT Configuration
# ---------------------------------------------------------------------------
PBT_ITERATIONS="${PBT_ITERATIONS:-100}"
PBT_SEED="${PBT_SEED:-$RANDOM}"

# Log seed for reproducibility
pbt_log_seed() {
  echo "# PBT seed: $PBT_SEED (iterations: $PBT_ITERATIONS)" >&3 2>/dev/null || true
}

# Run a property test function N times with seeded randomness.
# Arguments: $1 = test function name
# The function is called with the current iteration index.
run_property_test() {
  local test_fn="$1"
  RANDOM=$PBT_SEED
  pbt_log_seed
  for ((i = 0; i < PBT_ITERATIONS; i++)); do
    "$test_fn" "$i"
  done
}

# ---------------------------------------------------------------------------
# Random Generators
# ---------------------------------------------------------------------------

# Random alphanumeric string of given length (default 8)
random_string() {
  local len="${1:-8}"
  tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c "$len" || \
    cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c "$len"
}

# Random lowercase string
random_lower_string() {
  local len="${1:-8}"
  tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c "$len" || \
    cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c "$len"
}

# Random 12-digit AWS account ID
random_account_id() {
  printf '%012d' $((RANDOM * RANDOM % 1000000000000))
}

# Random AWS region from a realistic set
random_region() {
  local regions=(
    "us-east-1" "us-east-2" "us-west-1" "us-west-2"
    "eu-west-1" "eu-west-2" "eu-central-1"
    "ap-southeast-1" "ap-southeast-2" "ap-northeast-1"
  )
  echo "${regions[$((RANDOM % ${#regions[@]}))]}"
}

# ---------------------------------------------------------------------------
# Random URL Generators (per provider)
# ---------------------------------------------------------------------------

# Generate a valid GitHub URL with random org/repo
random_github_url() {
  local org
  org="$(random_lower_string 6)"
  local repo
  repo="$(random_lower_string 8)"
  local suffix=""
  if (( RANDOM % 2 == 0 )); then suffix=".git"; fi
  echo "https://github.com/${org}/${repo}${suffix}"
}

# Generate a valid CodeCommit URL with random region/repo
random_codecommit_url() {
  local region
  region="$(random_region)"
  local repo
  repo="$(random_lower_string 8)"
  echo "https://git-codecommit.${region}.amazonaws.com/v1/repos/${repo}"
}

# Generate a valid Bitbucket URL with random org/repo
random_bitbucket_url() {
  local org
  org="$(random_lower_string 6)"
  local repo
  repo="$(random_lower_string 8)"
  local suffix=""
  if (( RANDOM % 2 == 0 )); then suffix=".git"; fi
  echo "https://bitbucket.org/${org}/${repo}${suffix}"
}

# Generate a valid GitLab URL with random org/repo
random_gitlab_url() {
  local org
  org="$(random_lower_string 6)"
  local repo
  repo="$(random_lower_string 8)"
  local suffix=""
  if (( RANDOM % 2 == 0 )); then suffix=".git"; fi
  echo "https://gitlab.com/${org}/${repo}${suffix}"
}

# Generate a valid URL for a random provider
random_valid_url() {
  local provider="$1"
  case "$provider" in
    github)     random_github_url ;;
    codecommit) random_codecommit_url ;;
    bitbucket)  random_bitbucket_url ;;
    gitlab)     random_gitlab_url ;;
    *)          echo "https://invalid.example.com/repo" ;;
  esac
}

# Generate a random invalid URL (not matching any provider pattern)
random_invalid_url() {
  local variants=(
    "http://github.com/org/repo"
    "https://github.com/"
    "https://github.com/org"
    "ftp://github.com/org/repo"
    "https://notgithub.com/org/repo"
    "git@github.com:org/repo.git"
    "https://bitbucket.org/"
    "https://codecommit.us-east-1.amazonaws.com/repos/test"
    ""
    "not-a-url"
  )
  echo "${variants[$((RANDOM % ${#variants[@]}))]}"
}

# ---------------------------------------------------------------------------
# Random Provider
# ---------------------------------------------------------------------------

random_provider() {
  local providers=("github" "codecommit" "bitbucket" "gitlab")
  echo "${providers[$((RANDOM % ${#providers[@]}))]}"
}

# ---------------------------------------------------------------------------
# Random Branch Names
# ---------------------------------------------------------------------------

random_branch() {
  local branches=("main" "dev" "test" "staging" "feature/my-thing" "release/1.0" "hotfix/bug-123")
  echo "${branches[$((RANDOM % ${#branches[@]}))]}"
}

# ---------------------------------------------------------------------------
# Random Environment Names
# ---------------------------------------------------------------------------

random_env_name() {
  local envs=("prod" "dev" "test" "staging" "qa" "uat")
  echo "${envs[$((RANDOM % ${#envs[@]}))]}"
}

# ---------------------------------------------------------------------------
# Temp File Helpers
# ---------------------------------------------------------------------------

# Create a temp file and echo its path. Caller is responsible for cleanup.
create_temp_file() {
  local prefix="${1:-pbt-test}"
  mktemp "/tmp/${prefix}.XXXXXX"
}

# Create a temp directory and echo its path.
create_temp_dir() {
  local prefix="${1:-pbt-test}"
  mktemp -d "/tmp/${prefix}.XXXXXX"
}

# ---------------------------------------------------------------------------
# Assertion Helpers
# ---------------------------------------------------------------------------

# Assert two values are equal, with descriptive failure message
assert_equal() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "ASSERTION FAILED${msg:+: $msg}" >&2
    echo "  expected: '$expected'" >&2
    echo "  actual:   '$actual'" >&2
    return 1
  fi
}

# Assert a string starts with a prefix
assert_starts_with() {
  local prefix="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$actual" != "${prefix}"* ]]; then
    echo "ASSERTION FAILED${msg:+: $msg}" >&2
    echo "  expected to start with: '$prefix'" >&2
    echo "  actual: '$actual'" >&2
    return 1
  fi
}

# Assert a command exits with a specific code
assert_exit_code() {
  local expected_code="$1"
  shift
  local actual_code=0
  "$@" || actual_code=$?
  if [[ "$actual_code" -ne "$expected_code" ]]; then
    echo "ASSERTION FAILED: expected exit code $expected_code, got $actual_code" >&2
    echo "  command: $*" >&2
    return 1
  fi
}
