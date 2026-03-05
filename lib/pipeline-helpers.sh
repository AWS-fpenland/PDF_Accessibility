#!/usr/bin/env bash
# =============================================================================
# pipeline-helpers.sh — Pure functions for the private CI/CD pipeline setup
# =============================================================================
# Sourced by deploy-private.sh. Contains testable logic with no side effects
# (no AWS CLI calls, no prompts). AWS-interacting wrappers live in the main script.
# =============================================================================

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: This file should be sourced, not executed directly." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# URL Validation
# ---------------------------------------------------------------------------

# Validate a repository URL against the expected format for a given provider.
# Arguments: $1 = provider (github|codecommit|bitbucket|gitlab), $2 = url
# Returns: 0 if valid, 1 if invalid
validate_repo_url() {
  local provider="$1"
  local url="$2"

  case "$provider" in
    github)
      [[ "$url" =~ ^https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(\.git)?$ ]] && return 0
      ;;
    codecommit)
      [[ "$url" =~ ^https://git-codecommit\.[a-z0-9-]+\.amazonaws\.com/v1/repos/[a-zA-Z0-9._-]+$ ]] && return 0
      ;;
    bitbucket)
      [[ "$url" =~ ^https://bitbucket\.org/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(\.git)?$ ]] && return 0
      ;;
    gitlab)
      [[ "$url" =~ ^https://gitlab\.com/[a-zA-Z0-9._/-]+(\.git)?$ ]] && return 0
      ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Branch Resolution
# ---------------------------------------------------------------------------

# Resolve a branch name, defaulting to "main" when input is empty.
# Arguments: $1 = branch (may be empty)
# Outputs: resolved branch name to stdout
resolve_branch() {
  local input="${1:-}"
  if [[ -n "$input" ]]; then
    echo "$input"
  else
    echo "main"
  fi
}

# ---------------------------------------------------------------------------
# Connection Validation
# ---------------------------------------------------------------------------

# Check whether a CodeConnections connection status is AVAILABLE.
# Arguments: $1 = status string
# Returns: 0 if AVAILABLE, 1 otherwise
validate_connection_status() {
  local status="$1"
  [[ "$status" == "AVAILABLE" ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

# Generate the JSON trust policy for a CodeBuild service role.
# Outputs: JSON string to stdout
generate_trust_policy() {
  cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "codebuild.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------
# S3 Bucket Naming
# ---------------------------------------------------------------------------

# Generate the S3 bucket name for pdf2html deployments.
# Arguments: $1 = account_id, $2 = region
# Outputs: bucket name to stdout
generate_bucket_name() {
  local account_id="$1"
  local region="$2"
  echo "pdf2html-bucket-${account_id}-${region}"
}

# ---------------------------------------------------------------------------
# Build Status
# ---------------------------------------------------------------------------

# Check whether a build status indicates failure.
# Arguments: $1 = status string
# Returns: 0 if failure status (FAILED|FAULT|STOPPED|TIMED_OUT), 1 otherwise
is_failure_status() {
  local status="$1"
  case "$status" in
    FAILED|FAULT|STOPPED|TIMED_OUT) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Parameter Resolution
# ---------------------------------------------------------------------------

# Merge parameters from env vars, config file, and CLI args.
# Precedence: CLI > env > config > defaults
# Arguments: (implementation-specific)
# Outputs: resolved key=value pairs to stdout
resolve_params() {
  # Merge parameters with precedence: CLI > env > config > defaults
  # Reads from: CONFIG_FILE (path), CLI_* vars, and existing env vars
  # Sets global variables for each parameter

  local config_file="${CONFIG_FILE:-}"

  # Load config file values (lowest precedence after defaults)
  if [[ -n "$config_file" && -f "$config_file" ]]; then
    local config_output
    config_output="$(parse_config_file "$config_file")" || return 1
    while IFS='=' read -r key value; do
      [[ -z "$key" ]] && continue
      # Only set if not already set by env var or CLI
      local cli_var="CLI_${key}"
      if [[ -z "${!cli_var:-}" && -z "${!key:-}" ]]; then
        export "$key=$value"
      fi
    done <<< "$config_output"
  fi

  # CLI overrides take highest precedence
  [[ -n "${CLI_PRIVATE_REPO_URL:-}" ]] && export PRIVATE_REPO_URL="$CLI_PRIVATE_REPO_URL"
  [[ -n "${CLI_SOURCE_PROVIDER:-}" ]] && export SOURCE_PROVIDER="$CLI_SOURCE_PROVIDER"
  [[ -n "${CLI_DEPLOYMENT_TYPE:-}" ]] && export DEPLOYMENT_TYPE="$CLI_DEPLOYMENT_TYPE"
  [[ -n "${CLI_TARGET_BRANCH:-}" ]] && export TARGET_BRANCH="$CLI_TARGET_BRANCH"
  [[ -n "${CLI_CONNECTION_ARN:-}" ]] && export CONNECTION_ARN="$CLI_CONNECTION_ARN"
  [[ -n "${CLI_ADOBE_CLIENT_ID:-}" ]] && export ADOBE_CLIENT_ID="$CLI_ADOBE_CLIENT_ID"
  [[ -n "${CLI_ADOBE_CLIENT_SECRET:-}" ]] && export ADOBE_CLIENT_SECRET="$CLI_ADOBE_CLIENT_SECRET"

  # Apply defaults
  TARGET_BRANCH="$(resolve_branch "${TARGET_BRANCH:-}")"
  export TARGET_BRANCH
}

# Parse a key-value config file, skipping comments and blank lines.
# Arguments: $1 = file path
# Outputs: KEY=VALUE pairs to stdout
parse_config_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: Config file not found: $path" >&2
    return 1
  fi
  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    # Skip blank lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Strip leading/trailing whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Validate KEY=VALUE format
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*=.* ]]; then
      echo "$line"
    else
      echo "ERROR: Malformed line $line_num: $line" >&2
      return 1
    fi
  done < "$path"
}

# Validate that all required parameters are present.
# Arguments: $1 = non_interactive flag (true/false)
# Globals: reads PRIVATE_REPO_URL, SOURCE_PROVIDER, DEPLOYMENT_TYPE
# Outputs: list of missing params to stdout
# Returns: 0 if all present, 1 if any missing
check_required_params() {
  local non_interactive="${1:-false}"
  local missing=()
  [[ -z "${PRIVATE_REPO_URL:-}" ]] && missing+=("PRIVATE_REPO_URL")
  [[ -z "${SOURCE_PROVIDER:-}" ]] && missing+=("SOURCE_PROVIDER")
  [[ -z "${DEPLOYMENT_TYPE:-}" ]] && missing+=("DEPLOYMENT_TYPE")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required parameters: ${missing[*]}"
    return 1
  fi
  return 0
}

# Resolve CLI flag defaults for buildspec and project name.
# Arguments: $1 = buildspec_flag (may be empty), $2 = project_name_flag (may be empty)
# Outputs: two lines — resolved buildspec, resolved project name
resolve_cli_defaults() {
  local buildspec_flag="${1:-}"
  local project_name_flag="${2:-}"
  if [[ -n "$buildspec_flag" ]]; then
    echo "$buildspec_flag"
  else
    echo "buildspec-unified.yml"
  fi
  if [[ -n "$project_name_flag" ]]; then
    echo "$project_name_flag"
  else
    echo "pdfremediation-$(date +%s)"
  fi
}

# ---------------------------------------------------------------------------
# UI Environment
# ---------------------------------------------------------------------------

# Build environment variable assignments for UI deployment.
# Arguments: $1 = pdf2pdf_bucket, $2 = pdf2html_bucket
# Outputs: export statements to stdout
build_ui_env() {
  local pdf2pdf_bucket="${1:-Null}"
  local pdf2html_bucket="${2:-Null}"
  echo "PDF_TO_PDF_BUCKET=${pdf2pdf_bucket}"
  echo "PDF_TO_HTML_BUCKET=${pdf2html_bucket}"
}

# ---------------------------------------------------------------------------
# Cleanup / Resource Filtering
# ---------------------------------------------------------------------------

# Filter a list of project names by a glob pattern.
# Arguments: $1 = newline-separated project list, $2 = glob pattern
# Outputs: matching project names to stdout
filter_projects_by_pattern() {
  local project_list="$1"
  local pattern="$2"
  while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    # Use bash pattern matching (glob)
    # shellcheck disable=SC2254
    case "$project" in
      $pattern) echo "$project" ;;
    esac
  done <<< "$project_list"
}

# ---------------------------------------------------------------------------
# Source Configuration
# ---------------------------------------------------------------------------

# Build CodeBuild source JSON for a given provider.
# Arguments: $1=provider, $2=url, $3=branch, $4=connection_arn, $5=buildspec
# Outputs: JSON string to stdout
configure_source() {
  local provider="$1"
  local url="$2"
  local branch="$3"
  local connection_arn="${4:-}"
  local buildspec="${5:-buildspec-unified.yml}"

  if [[ "$provider" == "codecommit" ]]; then
    cat <<EOF
{"type":"CODECOMMIT","location":"${url}","buildspec":"${buildspec}"}
EOF
  else
    local source_type
    case "$provider" in
      github)    source_type="GITHUB" ;;
      bitbucket) source_type="BITBUCKET" ;;
      gitlab)    source_type="GITLAB" ;;
      *)         echo "ERROR: Unknown provider: $provider" >&2; return 1 ;;
    esac
    cat <<EOF
{"type":"${source_type}","location":"${url}","buildspec":"${buildspec}","auth":{"type":"CODECONNECTIONS","resource":"${connection_arn}"}}
EOF
  fi
}

# ---------------------------------------------------------------------------
# Multi-Environment: Branch-Environment Mapping
# ---------------------------------------------------------------------------

# Parse a JSON string into branch→environment key-value pairs.
# Arguments: $1 = JSON string
# Outputs: KEY=VALUE pairs to stdout (branch=environment)
# Returns: 0 on success, 1 on parse error
parse_branch_env_map() {
  local json_string="$1"
  # stub — implemented in task 8.1
  return 1
}

# Validate a Branch_Environment_Map for duplicates and empty entries.
# Arguments: reads from stdin or associative array
# Returns: 0 if valid, 1 if invalid (outputs error message to stderr)
validate_branch_env_map() {
  # stub — implemented in task 8.3
  return 0
}

# Resolve a branch name to its target environment.
# Arguments: $1 = branch name, $2 = serialized map (KEY=VALUE lines)
# Outputs: environment name to stdout (empty if no match)
resolve_environment() {
  local branch="$1"
  local map="${2:-}"
  # stub — implemented in task 8.5
  echo ""
}

# Generate an Environment_Prefix from an environment name.
# Arguments: $1 = environment name (e.g., "prod", "dev")
# Outputs: prefix string to stdout
generate_env_prefix() {
  local env_name="$1"
  # stub — implemented in task 8.8
  echo "$env_name"
}

# Generate an environment-prefixed resource name.
# Arguments: $1 = env_prefix, $2 = base_name
# Outputs: prefixed name to stdout
generate_env_resource_name() {
  local env_prefix="$1"
  local base_name="$2"
  # stub — implemented in task 8.8
  echo "${env_prefix}-${base_name}"
}

# Generate CodeBuild webhook filter JSON for a branch pattern.
# Arguments: $1 = branch pattern, $2 = env_name, $3 = is_production (true/false)
# Outputs: JSON filter groups to stdout
configure_webhooks() {
  local branch="$1"
  local env_name="$2"
  local is_production="${3:-false}"
  # stub — implemented in task 8.10
  echo '{"filterGroups":[]}'
}

# Filter a resource list by environment prefix.
# Arguments: $1 = newline-separated resource list, $2 = env_prefix
# Outputs: matching resources to stdout
filter_resources_by_env_prefix() {
  local resource_list="$1"
  local env_prefix="$2"
  # stub — implemented in task 8.13
  echo ""
}

# Delete resources matching a specific environment prefix.
# Arguments: $1 = env_prefix
# Returns: 0 on success, 1 if any deletions failed
cleanup_environment() {
  local env_prefix="$1"
  # stub — implemented in task 8.13
  return 0
}
