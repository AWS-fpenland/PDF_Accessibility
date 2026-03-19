#!/usr/bin/env bash
# =============================================================================
# deploy-private.sh — Private CI/CD Pipeline Setup for PDF Accessibility
# =============================================================================
# Configures AWS CodeBuild to deploy from a private repository with support
# for multi-environment branch-based deployments, non-interactive mode,
# and cleanup/teardown.
# =============================================================================

set -euo pipefail

# Resolve script directory and source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/pipeline-helpers.sh"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_header()  { echo -e "${CYAN}$1${NC}"; }

# ---------------------------------------------------------------------------
# Global State
# ---------------------------------------------------------------------------
NON_INTERACTIVE="false"
CONFIG_FILE=""
CLI_BUILDSPEC=""
CLI_PROJECT_NAME=""
CLI_BRANCH_ENV_MAP=""
CLI_PROFILE=""
DO_CLEANUP="false"
DO_MIGRATE="false"
CLI_ENVIRONMENT=""
DEPLOYED_SOLUTIONS=()
PDF2PDF_BUCKET=""
PDF2HTML_BUCKET=""

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
show_help() {
  cat <<'EOF'
Usage: deploy-private.sh [OPTIONS]

Deploy PDF Accessibility solutions from a private repository.

Options:
  --config <path>           Path to key-value config file
  --non-interactive         Fail with error instead of prompting
  --buildspec <path>        Custom buildspec file (default: buildspec-unified.yml)
  --project-name <name>     Custom CodeBuild project name (default: pdfremediation-{timestamp})
  --branch-env-map <json>   JSON mapping of branches to environments
                            Example: '{"main":"prod","dev":"dev","feature/*":"dev"}'
  --profile <name>          AWS CLI named profile to use for all AWS operations
  --migrate <project>       Migrate an existing CodeBuild project to use a private repo
  --cleanup                 List and delete pipeline resources
  --environment <name>      Target a specific environment for cleanup (with --cleanup)
  --help                    Show this help message

Environment Variables (non-interactive mode):
  PRIVATE_REPO_URL          Git repository URL (required)
  SOURCE_PROVIDER           github, codecommit, bitbucket, or gitlab (required)
  DEPLOYMENT_TYPE           pdf2pdf or pdf2html (required)
  TARGET_BRANCH             Branch name (default: main)
  CONNECTION_ARN            CodeConnections ARN (required for non-CodeCommit)
  ADOBE_CLIENT_ID           Adobe API Client ID (required for pdf2pdf)
  ADOBE_CLIENT_SECRET       Adobe API Client Secret (required for pdf2pdf)
  BUCKET_NAME               Override S3 bucket name for pdf2html
  BDA_PROJECT_ARN           Use existing BDA project for pdf2html
  BRANCH_ENV_MAP            JSON branch-to-environment mapping
  AWS_PROFILE               AWS CLI named profile (same as --profile flag)

Config File Format:
  PRIVATE_REPO_URL=https://github.com/myorg/my-fork.git
  SOURCE_PROVIDER=github
  DEPLOYMENT_TYPE=pdf2pdf
  TARGET_BRANCH=main
  CONNECTION_ARN=arn:aws:codeconnections:us-east-1:123456789:connection/abc-123
EOF
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        CONFIG_FILE="$2"; shift 2 ;;
      --non-interactive)
        NON_INTERACTIVE="true"; shift ;;
      --buildspec)
        CLI_BUILDSPEC="$2"; shift 2 ;;
      --project-name)
        CLI_PROJECT_NAME="$2"; shift 2 ;;
      --branch-env-map)
        CLI_BRANCH_ENV_MAP="$2"; shift 2 ;;
      --profile)
        CLI_PROFILE="$2"; shift 2 ;;
      --migrate)
        DO_MIGRATE="true"; CLI_PROJECT_NAME="$2"; shift 2 ;;
      --cleanup)
        DO_CLEANUP="true"; shift ;;
      --environment)
        CLI_ENVIRONMENT="$2"; shift 2 ;;
      --help)
        show_help; exit 0 ;;
      *)
        print_error "Unknown option: $1"
        show_help; exit 1 ;;
    esac
  done

  # Validate --environment requires --cleanup
  if [[ -n "$CLI_ENVIRONMENT" && "$DO_CLEANUP" != "true" ]]; then
    print_error "--environment requires --cleanup"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Interactive Prompts
# ---------------------------------------------------------------------------
prompt_or_fail() {
  local param_name="$1"
  local prompt_text="$2"
  local current_value="${3:-}"

  if [[ -n "$current_value" ]]; then
    echo "$current_value"
    return 0
  fi

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    print_error "Missing required parameter: $param_name"
    exit 1
  fi

  local response
  read -rp "$prompt_text" response
  echo "$response"
}

collect_parameters() {
  PRIVATE_REPO_URL="$(prompt_or_fail "PRIVATE_REPO_URL" \
    "Enter your private repository URL: " "${PRIVATE_REPO_URL:-}")"

  if [[ -z "${SOURCE_PROVIDER:-}" ]]; then
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      print_error "Missing required parameter: SOURCE_PROVIDER"
      exit 1
    fi
    echo ""
    echo "Select your source provider:"
    echo "  1) github"
    echo "  2) codecommit"
    echo "  3) bitbucket"
    echo "  4) gitlab"
    local choice
    read -rp "Enter choice (1-4): " choice
    case "$choice" in
      1) SOURCE_PROVIDER="github" ;;
      2) SOURCE_PROVIDER="codecommit" ;;
      3) SOURCE_PROVIDER="bitbucket" ;;
      4) SOURCE_PROVIDER="gitlab" ;;
      *) print_error "Invalid choice: $choice"; exit 1 ;;
    esac
  fi

  if [[ -z "${DEPLOYMENT_TYPE:-}" ]]; then
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      print_error "Missing required parameter: DEPLOYMENT_TYPE"
      exit 1
    fi
    echo ""
    echo "Select deployment type:"
    echo "  1) pdf2pdf  — PDF-to-PDF Remediation"
    echo "  2) pdf2html — PDF-to-HTML Remediation"
    local dt_choice
    read -rp "Enter choice (1-2): " dt_choice
    case "$dt_choice" in
      1) DEPLOYMENT_TYPE="pdf2pdf" ;;
      2) DEPLOYMENT_TYPE="pdf2html" ;;
      *) print_error "Invalid choice: $dt_choice"; exit 1 ;;
    esac
  fi

  TARGET_BRANCH="$(resolve_branch "${TARGET_BRANCH:-}")"

  # Conditional: Connection ARN for non-CodeCommit providers
  if [[ "$SOURCE_PROVIDER" != "codecommit" && -z "${CONNECTION_ARN:-}" ]]; then
    CONNECTION_ARN="$(prompt_or_fail "CONNECTION_ARN" \
      "Enter your AWS CodeConnections ARN: " "${CONNECTION_ARN:-}")"
  fi

  # Conditional: Adobe credentials for pdf2pdf
  if [[ "$DEPLOYMENT_TYPE" == "pdf2pdf" ]]; then
    ADOBE_CLIENT_ID="$(prompt_or_fail "ADOBE_CLIENT_ID" \
      "Enter Adobe API Client ID: " "${ADOBE_CLIENT_ID:-}")"
    ADOBE_CLIENT_SECRET="$(prompt_or_fail "ADOBE_CLIENT_SECRET" \
      "Enter Adobe API Client Secret: " "${ADOBE_CLIENT_SECRET:-}")"
  fi
}

# ---------------------------------------------------------------------------
# Input Validation
# ---------------------------------------------------------------------------
validate_inputs() {
  # Validate provider
  case "${SOURCE_PROVIDER:-}" in
    github|codecommit|bitbucket|gitlab) ;;
    *) print_error "Invalid source provider: '${SOURCE_PROVIDER:-}'. Supported: github, codecommit, bitbucket, gitlab"; exit 1 ;;
  esac

  # Validate deployment type
  case "${DEPLOYMENT_TYPE:-}" in
    pdf2pdf|pdf2html) ;;
    *) print_error "Invalid deployment type: '${DEPLOYMENT_TYPE:-}'. Supported: pdf2pdf, pdf2html"; exit 1 ;;
  esac

  # Validate URL format
  if ! validate_repo_url "$SOURCE_PROVIDER" "$PRIVATE_REPO_URL"; then
    print_error "Invalid repository URL for provider '$SOURCE_PROVIDER': $PRIVATE_REPO_URL"
    exit 1
  fi

  # Validate connection for non-CodeCommit
  if [[ "$SOURCE_PROVIDER" != "codecommit" ]]; then
    if [[ -z "${CONNECTION_ARN:-}" ]]; then
      print_error "CONNECTION_ARN is required for provider '$SOURCE_PROVIDER'"
      exit 1
    fi
    # Validate ARN format
    if [[ ! "$CONNECTION_ARN" =~ ^arn:aws:codeconnections:[a-z0-9-]+:[0-9]+:connection/.+$ ]]; then
      print_error "Invalid Connection ARN format: $CONNECTION_ARN"
      print_error "Expected format: arn:aws:codeconnections:{region}:{account}:connection/{id}"
      exit 1
    fi
    # Check connection status
    local conn_status
    conn_status="$(aws codeconnections get-connection \
      --connection-arn "$CONNECTION_ARN" \
      --query 'Connection.ConnectionStatus' \
      --output text 2>/dev/null)" || {
      print_error "Failed to retrieve connection status for: $CONNECTION_ARN"
      exit 1
    }
    if ! validate_connection_status "$conn_status"; then
      print_error "Connection is not AVAILABLE (current status: $conn_status)"
      print_error "Complete the connection handshake in the AWS Console"
      exit 1
    fi
    print_success "Connection verified: AVAILABLE"

    # Ensure the connection is registered as a CodeBuild source credential.
    # This is required for CodeBuild to use the connection when pulling source.
    local existing_cred
    existing_cred="$(aws codebuild list-source-credentials \
      --query "sourceCredentialsInfos[?resource=='${CONNECTION_ARN}'].arn" \
      --output text 2>/dev/null || echo "")"

    if [[ -z "$existing_cred" || "$existing_cred" == "None" ]]; then
      print_status "Registering connection as CodeBuild source credential..."
      local server_type
      case "$SOURCE_PROVIDER" in
        github)    server_type="GITHUB" ;;
        bitbucket) server_type="BITBUCKET" ;;
        gitlab)    server_type="GITLAB" ;;
      esac
      aws codebuild import-source-credentials \
        --server-type "$server_type" \
        --auth-type CODECONNECTIONS \
        --token "$CONNECTION_ARN" > /dev/null 2>&1 || {
        print_error "Failed to register connection as source credential"
        exit 1
      }
      print_success "Connection registered as source credential"
    else
      print_success "Connection already registered as source credential"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Solution-Specific Prerequisites (Task 11.1, 11.2)
# ---------------------------------------------------------------------------
setup_pdf2pdf_prereqs() {
  print_status "Setting up Adobe API credentials in Secrets Manager..."

  local json_template='{
    "client_credentials": {
      "PDF_SERVICES_CLIENT_ID": "",
      "PDF_SERVICES_CLIENT_SECRET": ""
    }
  }'

  local secret_json
  secret_json="$(echo "$json_template" | jq \
    --arg cid "$ADOBE_CLIENT_ID" \
    --arg csec "$ADOBE_CLIENT_SECRET" \
    '.client_credentials.PDF_SERVICES_CLIENT_ID = $cid |
     .client_credentials.PDF_SERVICES_CLIENT_SECRET = $csec')"

  local tmp_file
  tmp_file="$(mktemp)"
  echo "$secret_json" > "$tmp_file"

  if aws secretsmanager create-secret \
      --name /myapp/client_credentials \
      --description "Client credentials for PDF services" \
      --secret-string "file://$tmp_file" 2>/dev/null; then
    print_success "Secret created in Secrets Manager"
  else
    aws secretsmanager update-secret \
      --secret-id /myapp/client_credentials \
      --secret-string "file://$tmp_file" 2>/dev/null
    print_success "Secret updated in Secrets Manager"
  fi
  rm -f "$tmp_file"
}

setup_pdf2html_prereqs() {
  print_status "Setting up PDF-to-HTML prerequisites..."

  # Create BDA project
  local bda_name="pdf2html-bda-project-$(date +%Y%m%d-%H%M%S)"
  print_status "Creating Bedrock Data Automation project: $bda_name"

  local bda_response
  bda_response="$(aws bedrock-data-automation create-data-automation-project \
    --project-name "$bda_name" \
    --standard-output-configuration '{
      "document": {
        "extraction": {
          "granularity": { "types": ["DOCUMENT", "PAGE", "ELEMENT"] },
          "boundingBox": { "state": "ENABLED" }
        },
        "generativeField": { "state": "DISABLED" },
        "outputFormat": {
          "textFormat": { "types": ["HTML"] },
          "additionalFileFormat": { "state": "ENABLED" }
        }
      }
    }' \
    --region "$REGION" 2>/dev/null)" || {
    print_error "Failed to create BDA project. Ensure you have bedrock-data-automation permissions."
    exit 1
  }

  BDA_PROJECT_ARN="$(echo "$bda_response" | jq -r '.projectArn')"
  BUCKET_NAME="${BUCKET_NAME:-$(generate_bucket_name "$ACCOUNT_ID" "$REGION")}"

  print_success "BDA project created: $BDA_PROJECT_ARN"

  # Create S3 bucket if needed
  if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    print_status "Creating S3 bucket: $BUCKET_NAME"
    if [[ "$REGION" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
    else
      aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
        --create-bucket-configuration "LocationConstraint=$REGION"
    fi
    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
      --versioning-configuration Status=Enabled
    aws s3api put-object --bucket "$BUCKET_NAME" --key uploads/
    aws s3api put-object --bucket "$BUCKET_NAME" --key output/
    aws s3api put-object --bucket "$BUCKET_NAME" --key remediated/
    print_success "S3 bucket created: $BUCKET_NAME"
  else
    print_success "S3 bucket already exists: $BUCKET_NAME"
  fi
}

# ---------------------------------------------------------------------------
# IAM Role and Policy (Task 11.3, 11.4)
# ---------------------------------------------------------------------------
create_iam_role() {
  local role_name="$1"

  print_status "Setting up IAM role: $role_name"
  if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    print_success "Role '$role_name' already exists, reusing"
    ROLE_ARN="$(aws iam get-role --role-name "$role_name" --output json | jq -r '.Role.Arn')"
    return 0
  fi

  local trust_policy
  trust_policy="$(generate_trust_policy)"

  local create_output
  create_output="$(aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document "$trust_policy" \
    --output json)" || {
    print_error "Failed to create IAM role: $role_name"
    exit 1
  }

  ROLE_ARN="$(echo "$create_output" | jq -r '.Role.Arn')"
  print_success "Role created: $ROLE_ARN"

  print_status "Waiting 15s for IAM propagation..."
  sleep 15
}

create_iam_policy() {
  local policy_name="$1"
  local deployment_type="$2"
  local env_prefix="${3:-}"

  local policy_doc
  if [[ "$deployment_type" == "pdf2pdf" ]]; then
    policy_doc='{
      "Version":"2012-10-17",
      "Statement":[
        {"Sid":"S3","Effect":"Allow","Action":"s3:*","Resource":["arn:aws:s3:::cdk-*","arn:aws:s3:::cdk-*/*","arn:aws:s3:::pdfaccessibility*","arn:aws:s3:::pdfaccessibility*/*"]},
        {"Sid":"ECR","Effect":"Allow","Action":"ecr:*","Resource":"arn:aws:ecr:*:*:repository/cdk-*"},
        {"Sid":"ECRAuth","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"},
        {"Sid":"Lambda","Effect":"Allow","Action":"lambda:*","Resource":"arn:aws:lambda:*:*:function:*"},
        {"Sid":"ECS","Effect":"Allow","Action":"ecs:*","Resource":"*"},
        {"Sid":"EC2","Effect":"Allow","Action":"ec2:*","Resource":"*"},
        {"Sid":"SFN","Effect":"Allow","Action":"states:*","Resource":"arn:aws:states:*:*:stateMachine:*"},
        {"Sid":"IAMRole","Effect":"Allow","Action":["iam:CreateRole","iam:DeleteRole","iam:GetRole","iam:PassRole","iam:AttachRolePolicy","iam:DetachRolePolicy","iam:PutRolePolicy","iam:GetRolePolicy","iam:DeleteRolePolicy","iam:TagRole","iam:UntagRole","iam:ListRolePolicies","iam:ListAttachedRolePolicies","iam:UpdateAssumeRolePolicy","iam:ListRoleTags"],"Resource":["arn:aws:iam::*:role/PDFAccessibility*","arn:aws:iam::*:role/cdk-*"]},
        {"Sid":"IAMPolicy","Effect":"Allow","Action":["iam:CreatePolicy","iam:DeletePolicy","iam:GetPolicy","iam:GetPolicyVersion","iam:CreatePolicyVersion","iam:DeletePolicyVersion","iam:ListPolicyVersions"],"Resource":"arn:aws:iam::*:policy/*"},
        {"Sid":"CFN","Effect":"Allow","Action":"cloudformation:*","Resource":["arn:aws:cloudformation:*:*:stack/PDFAccessibility*/*","arn:aws:cloudformation:*:*:stack/CDKToolkit/*"]},
        {"Sid":"Logs","Effect":"Allow","Action":"logs:*","Resource":["arn:aws:logs:*:*:log-group:/aws/codebuild/*","arn:aws:logs:*:*:log-group:/aws/codebuild/*:*","arn:aws:logs:*:*:log-group:/aws/lambda/*","arn:aws:logs:*:*:log-group:/aws/lambda/*:*","arn:aws:logs:*:*:log-group:/ecs/*","arn:aws:logs:*:*:log-group:/ecs/*:*","arn:aws:logs:*:*:log-group:/aws/states/*","arn:aws:logs:*:*:log-group:/aws/states/*:*"]},
        {"Sid":"CW","Effect":"Allow","Action":["cloudwatch:PutMetricData","cloudwatch:PutDashboard","cloudwatch:DeleteDashboards","cloudwatch:GetDashboard"],"Resource":"*"},
        {"Sid":"SM","Effect":"Allow","Action":["secretsmanager:CreateSecret","secretsmanager:UpdateSecret","secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],"Resource":"arn:aws:secretsmanager:*:*:secret:/myapp/*"},
        {"Sid":"STS","Effect":"Allow","Action":["sts:GetCallerIdentity","sts:AssumeRole"],"Resource":"*"},
        {"Sid":"SSM","Effect":"Allow","Action":["ssm:GetParameter","ssm:GetParameters","ssm:PutParameter"],"Resource":"arn:aws:ssm:*:*:parameter/cdk-bootstrap/*"},
        {"Sid":"CC","Effect":"Allow","Action":["codeconnections:UseConnection","codeconnections:GetConnection","codeconnections:GetConnectionToken","codeconnections:PassConnectionToService"],"Resource":"arn:aws:codeconnections:*:*:connection/*"}
      ]
    }'
  else
    policy_doc='{
      "Version":"2012-10-17",
      "Statement":[
        {"Sid":"S3","Effect":"Allow","Action":"s3:*","Resource":["arn:aws:s3:::cdk-*","arn:aws:s3:::cdk-*/*","arn:aws:s3:::pdf2html-*","arn:aws:s3:::pdf2html-*/*"]},
        {"Sid":"ECR","Effect":"Allow","Action":"ecr:*","Resource":["arn:aws:ecr:*:*:repository/cdk-*","arn:aws:ecr:*:*:repository/pdf2html-*"]},
        {"Sid":"ECRAuth","Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"},
        {"Sid":"Lambda","Effect":"Allow","Action":"lambda:*","Resource":["arn:aws:lambda:*:*:function:Pdf2Html*","arn:aws:lambda:*:*:function:pdf2html*"]},
        {"Sid":"IAMRole","Effect":"Allow","Action":["iam:CreateRole","iam:DeleteRole","iam:GetRole","iam:PassRole","iam:AttachRolePolicy","iam:DetachRolePolicy","iam:PutRolePolicy","iam:GetRolePolicy","iam:DeleteRolePolicy","iam:TagRole","iam:UntagRole","iam:ListRolePolicies","iam:ListAttachedRolePolicies","iam:UpdateAssumeRolePolicy","iam:ListRoleTags"],"Resource":["arn:aws:iam::*:role/Pdf2Html*","arn:aws:iam::*:role/pdf2html*","arn:aws:iam::*:role/cdk-*"]},
        {"Sid":"IAMPolicy","Effect":"Allow","Action":["iam:CreatePolicy","iam:DeletePolicy","iam:GetPolicy","iam:GetPolicyVersion","iam:CreatePolicyVersion","iam:DeletePolicyVersion","iam:ListPolicyVersions"],"Resource":"arn:aws:iam::*:policy/*"},
        {"Sid":"CFN","Effect":"Allow","Action":"cloudformation:*","Resource":["arn:aws:cloudformation:*:*:stack/Pdf2Html*/*","arn:aws:cloudformation:*:*:stack/pdf2html*/*","arn:aws:cloudformation:*:*:stack/CDKToolkit/*"]},
        {"Sid":"Bedrock","Effect":"Allow","Action":["bedrock:CreateDataAutomationProject","bedrock:GetDataAutomationProject","bedrock:DeleteDataAutomationProject","bedrock:UpdateDataAutomationProject","bedrock:ListDataAutomationProjects"],"Resource":"*"},
        {"Sid":"Logs","Effect":"Allow","Action":"logs:*","Resource":["arn:aws:logs:*:*:log-group:/aws/codebuild/*","arn:aws:logs:*:*:log-group:/aws/codebuild/*:*","arn:aws:logs:*:*:log-group:/aws/lambda/Pdf2Html*","arn:aws:logs:*:*:log-group:/aws/lambda/Pdf2Html*:*"]},
        {"Sid":"STS","Effect":"Allow","Action":["sts:GetCallerIdentity","sts:AssumeRole"],"Resource":"*"},
        {"Sid":"SSM","Effect":"Allow","Action":["ssm:GetParameter","ssm:GetParameters","ssm:PutParameter"],"Resource":"arn:aws:ssm:*:*:parameter/cdk-bootstrap/*"},
        {"Sid":"CC","Effect":"Allow","Action":["codeconnections:UseConnection","codeconnections:GetConnection","codeconnections:GetConnectionToken","codeconnections:PassConnectionToService"],"Resource":"arn:aws:codeconnections:*:*:connection/*"}
      ]
    }'
  fi

  print_status "Creating IAM policy: $policy_name"
  local policy_response
  policy_response="$(aws iam create-policy \
    --policy-name "$policy_name" \
    --policy-document "$policy_doc" \
    --description "Scoped policy for $deployment_type CodeBuild deployment" 2>/dev/null || \
    aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/$policy_name" 2>/dev/null)" || {
    print_error "Failed to create or retrieve IAM policy: $policy_name"
    exit 1
  }

  POLICY_ARN="$(echo "$policy_response" | jq -r '.Policy.Arn')"
  print_success "Policy ready: $policy_name"

  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" || {
    print_error "Failed to attach policy to role"
    exit 1
  }
}

# ---------------------------------------------------------------------------
# CodeBuild Project Creation (Task 11.6)
# ---------------------------------------------------------------------------
create_codebuild_project() {
  local project_name="$1"
  local env_prefix="${2:-}"
  local branch="${3:-$TARGET_BRANCH}"
  local env_name="${4:-}"
  local is_production="${5:-false}"

  print_status "Creating CodeBuild project: $project_name"

  # Build source JSON
  local source_json
  source_json="$(configure_source "$SOURCE_PROVIDER" "$PRIVATE_REPO_URL" \
    "$branch" "${CONNECTION_ARN:-}" "$BUILDSPEC_FILE")"

  # Build environment
  local build_image compute_type
  if [[ "$DEPLOYMENT_TYPE" == "pdf2pdf" ]]; then
    build_image="aws/codebuild/amazonlinux-x86_64-standard:5.0"
    compute_type="BUILD_GENERAL1_SMALL"
  else
    build_image="aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type="BUILD_GENERAL1_LARGE"
  fi

  local env_json="{\"type\":\"LINUX_CONTAINER\",\"image\":\"$build_image\",\"computeType\":\"$compute_type\",\"privilegedMode\":true}"

  # Build environment variables
  local env_vars="[{\"name\":\"DEPLOYMENT_TYPE\",\"value\":\"$DEPLOYMENT_TYPE\"}"
  if [[ -n "$env_name" ]]; then
    env_vars+=",{\"name\":\"TARGET_ENVIRONMENT\",\"value\":\"$env_name\"}"
  fi
  if [[ "$DEPLOYMENT_TYPE" == "pdf2html" ]]; then
    env_vars+=",{\"name\":\"ACCOUNT_ID\",\"value\":\"$ACCOUNT_ID\"}"
    env_vars+=",{\"name\":\"REGION\",\"value\":\"$REGION\"}"
    env_vars+=",{\"name\":\"BUCKET_NAME\",\"value\":\"${BUCKET_NAME:-}\"}"
    env_vars+=",{\"name\":\"BDA_PROJECT_ARN\",\"value\":\"${BDA_PROJECT_ARN:-}\"}"
  fi
  env_vars+="]"

  env_json="$(echo "$env_json" | jq --argjson ev "$env_vars" '.environmentVariables = $ev')"

  # Create project
  local create_output
  create_output="$(aws codebuild create-project \
    --name "$project_name" \
    --source "$source_json" \
    --source-version "$branch" \
    --artifacts '{"type":"NO_ARTIFACTS"}' \
    --environment "$env_json" \
    --service-role "$ROLE_ARN" \
    --output json 2>&1)" || {
    # Check if it's a genuine "already exists" case
    if echo "$create_output" | grep -qi "already exists"; then
      print_warning "CodeBuild project '$project_name' already exists, reusing"
    else
      print_error "Failed to create CodeBuild project: $project_name"
      print_error "$create_output"
      exit 1
    fi
  }

  # Verify the project actually exists before proceeding
  if ! aws codebuild batch-get-projects --names "$project_name" \
      --query 'projects[0].name' --output text 2>/dev/null | grep -q "$project_name"; then
    print_error "CodeBuild project '$project_name' not found after creation attempt"
    print_error "Check IAM permissions and source configuration"
    exit 1
  fi

  # Configure webhooks if branch-env-map is in use
  if [[ -n "$env_name" ]]; then
    local webhook_json
    webhook_json="$(configure_webhooks "$branch" "$env_name" "$is_production")"
    local filter_groups
    filter_groups="$(echo "$webhook_json" | jq -c '.filterGroups')"

    aws codebuild create-webhook \
      --project-name "$project_name" \
      --filter-groups "$filter_groups" \
      --output json > /dev/null 2>&1 || {
      print_warning "Webhook may already exist for $project_name"
    }
    print_success "Webhook configured for branch '$branch' → environment '$env_name'"
  fi

  print_success "CodeBuild project ready: $project_name"
}

# ---------------------------------------------------------------------------
# Build Monitoring (Task 12.1, 12.2)
# ---------------------------------------------------------------------------
show_build_logs() {
  local project_name="$1"
  local log_group="/aws/codebuild/$project_name"

  sleep 5
  local latest_stream
  latest_stream="$(aws logs describe-log-streams \
    --log-group-name "$log_group" \
    --order-by LastEventTime --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' --output text 2>/dev/null || echo "")"

  if [[ -n "$latest_stream" && "$latest_stream" != "None" ]]; then
    print_error "Recent build logs:"
    aws logs get-log-events \
      --log-group-name "$log_group" \
      --log-stream-name "$latest_stream" \
      --query 'events[-30:].message' --output text 2>/dev/null || \
      print_error "Could not retrieve logs"
  else
    print_error "Could not retrieve build logs. Check CodeBuild console."
  fi
}

start_and_monitor_build() {
  local project_name="$1"
  local source_version="$2"

  print_status "Starting build for project '$project_name'..."

  local build_response
  build_response="$(aws codebuild start-build \
    --project-name "$project_name" \
    --source-version "$source_version" \
    --output json)" || {
    print_error "Failed to start build"
    exit 1
  }

  local build_id
  build_id="$(echo "$build_response" | jq -r '.build.id')"
  print_success "Build started: $build_id"

  print_status "Monitoring build progress..."
  local dots=0 last_status=""
  while true; do
    local build_status
    build_status="$(aws codebuild batch-get-builds --ids "$build_id" \
      --query 'builds[0].buildStatus' --output text)"

    if [[ "$build_status" != "$last_status" ]]; then
      echo ""
      print_status "Build status: $build_status"
      last_status="$build_status"
      dots=0
    fi

    case "$build_status" in
      SUCCEEDED)
        echo ""
        print_success "Build completed successfully!"
        return 0
        ;;
      FAILED|FAULT|STOPPED|TIMED_OUT)
        echo ""
        print_error "Build failed with status: $build_status"
        show_build_logs "$project_name"
        return 1
        ;;
      IN_PROGRESS)
        printf "."
        dots=$((dots + 1))
        if [[ $dots -eq 60 ]]; then
          echo ""
          print_status "Still building..."
          dots=0
        fi
        sleep 5
        ;;
      *)
        printf "."
        sleep 3
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# UI Deployment (Task 12.3)
# ---------------------------------------------------------------------------
deploy_ui() {
  if [[ ${#DEPLOYED_SOLUTIONS[@]} -eq 0 ]]; then
    print_error "No backend solutions deployed. Cannot deploy UI without backend."
    return 1
  fi

  local pdf2pdf_bucket="${PDF2PDF_BUCKET:-Null}"
  local pdf2html_bucket="${PDF2HTML_BUCKET:-Null}"

  if [[ "$pdf2pdf_bucket" == "Null" && "$pdf2html_bucket" == "Null" ]]; then
    print_error "No backend bucket available for UI deployment."
    return 1
  fi

  local ui_repo_url
  ui_repo_url="$(prompt_or_fail "UI_REPO_URL" \
    "Enter UI repository URL (or press Enter for default): " \
    "${UI_REPO_URL:-}")"
  ui_repo_url="${ui_repo_url:-https://github.com/ASUCICREPO/PDF_accessability_UI}"

  print_status "Deploying UI from: $ui_repo_url"

  local ui_env
  ui_env="$(build_ui_env "$pdf2pdf_bucket" "$pdf2html_bucket")"
  print_status "UI environment:"
  echo "$ui_env" | while read -r line; do print_status "  $line"; done

  local original_dir
  original_dir="$(pwd)"
  local ui_temp="/tmp/pdf-ui-deployment-$$"

  if ! git clone -b main "$ui_repo_url" "$ui_temp" 2>/dev/null; then
    print_error "Failed to clone UI repository"
    return 1
  fi

  cd "$ui_temp" || return 1
  export PDF_TO_PDF_BUCKET="$pdf2pdf_bucket"
  export PDF_TO_HTML_BUCKET="$pdf2html_bucket"

  if [[ -f "deploy.sh" ]]; then
    chmod +x deploy.sh
    ./deploy.sh || { print_error "UI deployment failed"; cd "$original_dir"; rm -rf "$ui_temp"; return 1; }
    print_success "UI deployment completed!"
  else
    print_error "UI deploy.sh not found in repository"
  fi

  cd "$original_dir"
  rm -rf "$ui_temp"
}

# ---------------------------------------------------------------------------
# Cleanup (Task 12.4)
# ---------------------------------------------------------------------------
cleanup_resources() {
  print_header "Cleaning up pipeline resources..."

  local pattern="pdfremediation-*"
  if [[ -n "$CLI_ENVIRONMENT" ]]; then
    local env_prefix
    env_prefix="$(generate_env_prefix "$CLI_ENVIRONMENT")"
    pattern="${env_prefix}-pdfremediation-*"
    print_status "Filtering by environment: $CLI_ENVIRONMENT (prefix: $env_prefix)"
  fi

  # List matching CodeBuild projects
  local all_projects
  all_projects="$(aws codebuild list-projects --query 'projects' --output text 2>/dev/null | tr '\t' '\n')"
  local matching
  matching="$(filter_projects_by_pattern "$all_projects" "$pattern")"

  if [[ -z "$matching" ]]; then
    print_status "No matching resources found."
    return 0
  fi

  echo ""
  print_status "Resources to delete:"
  echo "$matching" | while read -r p; do
    [[ -n "$p" ]] && print_status "  - CodeBuild project: $p"
  done

  # Confirm unless non-interactive
  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    local confirm
    read -rp "Proceed with deletion? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      print_status "Cleanup cancelled."
      return 0
    fi
  fi

  local failed=()
  while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    print_status "Deleting: $project"

    # Delete CodeBuild project
    aws codebuild delete-project --name "$project" 2>/dev/null || {
      print_warning "Failed to delete project: $project"
      failed+=("$project")
    }

    # Derive and delete IAM resources
    local role_name="${project}-codebuild-service-role"
    local policy_pdf2pdf="${project}-pdf2pdf-codebuild-policy"
    local policy_pdf2html="${project}-pdf2html-codebuild-policy"

    for policy_name in "$policy_pdf2pdf" "$policy_pdf2html"; do
      local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/$policy_name"
      aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
      aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
    done

    aws iam delete-role --role-name "$role_name" 2>/dev/null || {
      print_warning "Failed to delete role: $role_name"
      failed+=("$role_name")
    }
  done <<< "$matching"

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo ""
    print_warning "Failed to delete ${#failed[@]} resource(s):"
    for f in "${failed[@]}"; do print_warning "  - $f"; done
    return 1
  fi

  print_success "Cleanup complete!"
}

# ---------------------------------------------------------------------------
# Migrate Existing Project (--migrate)
# ---------------------------------------------------------------------------
migrate_project() {
  local project_name="$CLI_PROJECT_NAME"

  echo ""
  print_header "🔄 Migrating CodeBuild project: $project_name"
  print_header "================================================"
  echo ""

  # Apply AWS profile
  if [[ -n "$CLI_PROFILE" ]]; then
    export AWS_PROFILE="$CLI_PROFILE"
    print_status "Using AWS profile: $AWS_PROFILE"
  fi

  # Get AWS identity
  ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)" || {
    print_error "AWS CLI not configured. Run 'aws configure' first."
    exit 1
  }
  REGION="$(aws configure get region 2>/dev/null || echo "us-east-1")"
  print_success "Account: $ACCOUNT_ID, Region: $REGION"

  # Load config if provided
  if [[ -n "$CONFIG_FILE" ]]; then
    print_status "Loading config from: $CONFIG_FILE"
    eval "$(parse_config_file "$CONFIG_FILE")" || exit 1
  fi

  # Verify project exists
  print_status "Verifying project exists..."
  local project_info
  project_info="$(aws codebuild batch-get-projects --names "$project_name" \
    --query 'projects[0]' --output json 2>/dev/null)" || {
    print_error "Project not found: $project_name"
    exit 1
  }

  if [[ "$project_info" == "null" || -z "$project_info" ]]; then
    print_error "Project not found: $project_name"
    exit 1
  fi

  local current_source
  current_source="$(echo "$project_info" | jq -r '.source.location // "unknown"')"
  print_status "Current source: $current_source"

  # Collect new repo info
  PRIVATE_REPO_URL="$(prompt_or_fail "PRIVATE_REPO_URL" \
    "Enter your private repository URL: " "${PRIVATE_REPO_URL:-}")"
  SOURCE_PROVIDER="${SOURCE_PROVIDER:-}"
  if [[ -z "$SOURCE_PROVIDER" ]]; then
    SOURCE_PROVIDER="$(prompt_or_fail "SOURCE_PROVIDER" \
      "Enter source provider (github/codecommit/bitbucket/gitlab): " "")"
  fi
  TARGET_BRANCH="$(resolve_branch "${TARGET_BRANCH:-}")"

  # Validate URL
  if ! validate_repo_url "$SOURCE_PROVIDER" "$PRIVATE_REPO_URL"; then
    print_error "Invalid repository URL for provider '$SOURCE_PROVIDER': $PRIVATE_REPO_URL"
    exit 1
  fi

  # Handle connection for non-CodeCommit
  if [[ "$SOURCE_PROVIDER" != "codecommit" ]]; then
    if [[ -z "${CONNECTION_ARN:-}" ]]; then
      CONNECTION_ARN="$(prompt_or_fail "CONNECTION_ARN" \
        "Enter your AWS CodeConnections ARN: " "")"
    fi

    # Validate ARN format
    if [[ ! "$CONNECTION_ARN" =~ ^arn:aws:codeconnections:[a-z0-9-]+:[0-9]+:connection/.+$ ]]; then
      print_error "Invalid Connection ARN format: $CONNECTION_ARN"
      exit 1
    fi

    # Ensure source credential is registered
    local existing_cred
    existing_cred="$(aws codebuild list-source-credentials \
      --query "sourceCredentialsInfos[?resource=='${CONNECTION_ARN}'].arn" \
      --output text 2>/dev/null || echo "")"

    if [[ -z "$existing_cred" || "$existing_cred" == "None" ]]; then
      print_status "Registering connection as source credential..."
      local server_type
      case "$SOURCE_PROVIDER" in
        github)    server_type="GITHUB" ;;
        bitbucket) server_type="BITBUCKET" ;;
        gitlab)    server_type="GITLAB" ;;
      esac
      aws codebuild import-source-credentials \
        --server-type "$server_type" \
        --auth-type CODECONNECTIONS \
        --token "$CONNECTION_ARN" > /dev/null 2>&1 || {
        print_error "Failed to register connection as source credential"
        exit 1
      }
      print_success "Connection registered"
    fi
  fi

  # Build new source JSON
  local buildspec
  buildspec="$(echo "$project_info" | jq -r '.source.buildspec // "buildspec-unified.yml"')"
  local new_source
  new_source="$(configure_source "$SOURCE_PROVIDER" "$PRIVATE_REPO_URL" \
    "$TARGET_BRANCH" "${CONNECTION_ARN:-}" "$buildspec")"

  # Confirm migration
  echo ""
  print_status "Migration summary:"
  print_status "  Project:    $project_name"
  print_status "  Old source: $current_source"
  print_status "  New source: $PRIVATE_REPO_URL"
  print_status "  Branch:     $TARGET_BRANCH"
  print_status "  Buildspec:  $buildspec"

  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    local confirm
    read -rp "Proceed with migration? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      print_status "Migration cancelled."
      exit 0
    fi
  fi

  # Update the project source
  print_status "Updating project source..."
  local update_output
  update_output="$(aws codebuild update-project \
    --name "$project_name" \
    --source "$new_source" \
    --source-version "$TARGET_BRANCH" \
    --output json 2>&1)" || {
    print_error "Failed to update project source"
    print_error "$update_output"
    exit 1
  }

  print_success "Project source updated to: $PRIVATE_REPO_URL"

  # Optionally configure webhooks
  if [[ -n "$CLI_BRANCH_ENV_MAP" ]]; then
    print_status "Configuring webhooks for multi-environment..."
    local map_lines
    map_lines="$(parse_branch_env_map "$CLI_BRANCH_ENV_MAP")" || exit 1

    local prod_branch=""
    while IFS='=' read -r branch env_name; do
      [[ -z "$branch" ]] && continue
      [[ "$env_name" == "prod" ]] && prod_branch="$branch"
    done <<< "$map_lines"

    local is_production="false"
    [[ -n "$prod_branch" && "$TARGET_BRANCH" == "$prod_branch" ]] && is_production="true"

    local env_name
    env_name="$(resolve_environment "$TARGET_BRANCH" "$map_lines")" || env_name=""

    if [[ -n "$env_name" ]]; then
      local webhook_json
      webhook_json="$(configure_webhooks "$TARGET_BRANCH" "$env_name" "$is_production")"
      local filter_groups
      filter_groups="$(echo "$webhook_json" | jq -c '.filterGroups')"

      # Delete existing webhook first (update not supported)
      aws codebuild delete-webhook --project-name "$project_name" 2>/dev/null || true

      aws codebuild create-webhook \
        --project-name "$project_name" \
        --filter-groups "$filter_groups" \
        --output json > /dev/null 2>&1 || {
        print_warning "Could not configure webhook"
      }
      print_success "Webhook configured for branch '$TARGET_BRANCH' → environment '$env_name'"
    fi
  fi

  # Offer to trigger a build
  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    local trigger
    read -rp "Trigger a build now? (y/N): " trigger
    if [[ "$trigger" == "y" || "$trigger" == "Y" ]]; then
      start_and_monitor_build "$project_name" "$TARGET_BRANCH"
    fi
  fi

  echo ""
  print_success "Migration complete! Future builds will use: $PRIVATE_REPO_URL"
}

# ---------------------------------------------------------------------------
# Main Orchestration (Task 13)
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"

  # Handle cleanup mode
  if [[ "$DO_CLEANUP" == "true" ]]; then
    # Apply AWS profile if specified (CLI flag > env var > config file)
    if [[ -n "$CLI_PROFILE" ]]; then
      export AWS_PROFILE="$CLI_PROFILE"
      print_status "Using AWS profile: $AWS_PROFILE"
    fi
    # Get account ID for policy ARN construction
    ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)" || {
      print_error "AWS CLI not configured. Run 'aws configure' first."
      exit 1
    }
    cleanup_resources
    exit $?
  fi

  # Handle migrate mode
  if [[ "$DO_MIGRATE" == "true" ]]; then
    migrate_project
    exit $?
  fi

  # Welcome
  echo ""
  print_header "🔒 PDF Accessibility — Private Pipeline Setup"
  print_header "================================================"
  echo ""

  # Apply AWS profile if specified (CLI flag > env var > config file)
  if [[ -n "$CLI_PROFILE" ]]; then
    export AWS_PROFILE="$CLI_PROFILE"
    print_status "Using AWS profile: $AWS_PROFILE"
  elif [[ -n "${AWS_PROFILE:-}" ]]; then
    print_status "Using AWS profile from environment: $AWS_PROFILE"
  fi

  # Get AWS identity
  print_status "Verifying AWS credentials..."
  ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)" || {
    print_error "AWS CLI not configured. Run 'aws configure' first."
    exit 1
  }
  REGION="$(aws configure get region 2>/dev/null || echo "us-east-1")"
  print_success "Account: $ACCOUNT_ID, Region: $REGION"

  # Load config file if provided
  if [[ -n "$CONFIG_FILE" ]]; then
    print_status "Loading config from: $CONFIG_FILE"
    eval "$(parse_config_file "$CONFIG_FILE")" || exit 1
    # Apply profile from config if not already set by CLI flag
    if [[ -z "$CLI_PROFILE" && -n "${AWS_PROFILE:-}" ]]; then
      print_status "Using AWS profile from config: $AWS_PROFILE"
    fi
  fi

  # Also check BRANCH_ENV_MAP env var
  if [[ -z "$CLI_BRANCH_ENV_MAP" && -n "${BRANCH_ENV_MAP:-}" ]]; then
    CLI_BRANCH_ENV_MAP="$BRANCH_ENV_MAP"
  fi

  # Collect parameters (interactive or from env)
  collect_parameters

  # Validate
  local missing_output
  missing_output="$(check_required_params "$NON_INTERACTIVE")" || {
    print_error "$missing_output"
    exit 1
  }

  # Resolve CLI defaults
  local cli_defaults
  cli_defaults="$(resolve_cli_defaults "$CLI_BUILDSPEC" "$CLI_PROJECT_NAME")"
  BUILDSPEC_FILE="$(echo "$cli_defaults" | head -1)"
  PROJECT_NAME="$(echo "$cli_defaults" | tail -1)"

  # Validate inputs (URL, provider, connection)
  validate_inputs

  # Setup prerequisites
  print_header "Setting up prerequisites..."
  if [[ "$DEPLOYMENT_TYPE" == "pdf2pdf" ]]; then
    setup_pdf2pdf_prereqs
  else
    setup_pdf2html_prereqs
  fi

  # Multi-environment or single deployment
  if [[ -n "$CLI_BRANCH_ENV_MAP" ]]; then
    deploy_multi_environment
  else
    deploy_single_environment
  fi

  # Offer UI deployment
  echo ""
  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    local deploy_ui_choice
    read -rp "Deploy Frontend UI? (y/N): " deploy_ui_choice
    if [[ "$deploy_ui_choice" == "y" || "$deploy_ui_choice" == "Y" ]]; then
      deploy_ui
    fi
  fi

  echo ""
  print_success "Pipeline setup complete!"
}

deploy_single_environment() {
  local role_name="${PROJECT_NAME}-codebuild-service-role"
  ROLE_NAME="$role_name"

  create_iam_role "$role_name"

  local policy_name="${PROJECT_NAME}-${DEPLOYMENT_TYPE}-codebuild-policy"
  create_iam_policy "$policy_name" "$DEPLOYMENT_TYPE"

  # Wait for IAM policy attachment to propagate before starting a build.
  # Without this delay CodeBuild may fail with ACCESS_DENIED on CloudWatch Logs
  # because the policy hasn't taken effect yet.
  print_status "Waiting 15s for IAM policy propagation..."
  sleep 15

  create_codebuild_project "$PROJECT_NAME" "" "$TARGET_BRANCH"

  if start_and_monitor_build "$PROJECT_NAME" "$TARGET_BRANCH"; then
    DEPLOYED_SOLUTIONS+=("$DEPLOYMENT_TYPE")
    # Collect bucket info
    if [[ "$DEPLOYMENT_TYPE" == "pdf2pdf" ]]; then
      PDF2PDF_BUCKET="$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `pdfaccessibility`)] | sort_by(@, &CreationDate) | [-1].Name' \
        --output text 2>/dev/null || echo "")"
    else
      PDF2HTML_BUCKET="${BUCKET_NAME:-}"
    fi
  fi
}

deploy_multi_environment() {
  print_header "Multi-environment deployment..."

  # Parse and validate branch-env-map
  local map_lines
  map_lines="$(parse_branch_env_map "$CLI_BRANCH_ENV_MAP")" || exit 1
  validate_branch_env_map "$map_lines" || exit 1

  # Determine production branch (maps to "prod" environment)
  local prod_branch=""
  while IFS='=' read -r branch env_name; do
    [[ -z "$branch" ]] && continue
    if [[ "$env_name" == "prod" ]]; then
      prod_branch="$branch"
    fi
  done <<< "$map_lines"

  # Create resources for each environment
  while IFS='=' read -r branch env_name; do
    [[ -z "$branch" ]] && continue

    local env_prefix
    env_prefix="$(generate_env_prefix "$env_name")"
    local is_production="false"
    [[ "$env_name" == "prod" ]] && is_production="true"

    local env_project_name
    env_project_name="$(generate_env_resource_name "$env_prefix" "$PROJECT_NAME")"
    local env_role_name="${env_project_name}-codebuild-service-role"
    ROLE_NAME="$env_role_name"

    print_header "Setting up environment: $env_name (branch: $branch)"

    create_iam_role "$env_role_name"

    local env_policy_name="${env_project_name}-${DEPLOYMENT_TYPE}-codebuild-policy"
    create_iam_policy "$env_policy_name" "$DEPLOYMENT_TYPE" "$env_prefix"

    create_codebuild_project "$env_project_name" "$env_prefix" "$branch" "$env_name" "$is_production"

    print_success "Environment '$env_name' configured for branch '$branch'"
    echo ""
  done <<< "$map_lines"

  DEPLOYED_SOLUTIONS+=("$DEPLOYMENT_TYPE")
  print_success "All environments configured!"
  print_status "Builds will trigger automatically via webhooks on branch pushes."
  if [[ -n "$prod_branch" ]]; then
    print_status "Production deploys on PR merge to '$prod_branch'."
  fi
}

# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------
main "$@"
