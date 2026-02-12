#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "\n${CYAN}$1${NC}"; }

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy/update PDF Accessibility solutions."
    echo ""
    echo "Options:"
    echo "  --pdf2pdf       Deploy PDF-to-PDF only"
    echo "  --pdf2html      Deploy PDF-to-HTML only"
    echo "  --all           Deploy both (default if no option given)"
    echo "  --init          First-time setup (creates secrets, BDA project, buckets)"
    echo "  --profile NAME  AWS CLI profile to use"
    echo "  --region REGION AWS region (default: from AWS config)"
    echo "  -h, --help      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --all                    # Update everything"
    echo "  $0 --pdf2html               # Update only pdf2html"
    echo "  $0 --init --all             # First-time full deployment"
    echo "  $0 --profile myprofile      # Use specific AWS profile"
}

# Parse arguments
DEPLOY_PDF2PDF=false
DEPLOY_PDF2HTML=false
FIRST_TIME=false
AWS_PROFILE_ARG=""
REGION_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --pdf2pdf)   DEPLOY_PDF2PDF=true; shift ;;
        --pdf2html)  DEPLOY_PDF2HTML=true; shift ;;
        --all)       DEPLOY_PDF2PDF=true; DEPLOY_PDF2HTML=true; shift ;;
        --init)      FIRST_TIME=true; shift ;;
        --profile)   AWS_PROFILE_ARG="--profile $2"; export AWS_PROFILE="$2"; shift 2 ;;
        --region)    REGION_ARG="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Default to --all if nothing specified
if [ "$DEPLOY_PDF2PDF" = false ] && [ "$DEPLOY_PDF2HTML" = false ]; then
    DEPLOY_PDF2PDF=true
    DEPLOY_PDF2HTML=true
fi

# Resolve account and region
print_status "Verifying AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity $AWS_PROFILE_ARG --query "Account" --output text)
REGION=${REGION_ARG:-${AWS_DEFAULT_REGION:-$(aws configure get region $AWS_PROFILE_ARG 2>/dev/null || echo "us-east-1")}}

# If Pdf2HtmlStack exists, use its region for consistency
if [ -z "$REGION_ARG" ]; then
    EXISTING_REGION=$(aws cloudformation describe-stacks --stack-name Pdf2HtmlStack $AWS_PROFILE_ARG --region us-east-1 --query 'Stacks[0].StackId' --output text 2>/dev/null | grep -oP ':\K[a-z]+-[a-z]+-[0-9]+' | head -1)
    if [ -n "$EXISTING_REGION" ] && [ "$EXISTING_REGION" != "$REGION" ]; then
        print_warning "Profile region is $REGION but Pdf2HtmlStack exists in $EXISTING_REGION"
        print_warning "Using $EXISTING_REGION for consistency. Override with --region if needed."
        REGION="$EXISTING_REGION"
    fi
fi
print_success "Account: $ACCOUNT_ID, Region: $REGION"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================
# FIRST-TIME SETUP (only with --init)
# ============================================================
if [ "$FIRST_TIME" = true ]; then
    print_header "=== First-Time Setup ==="

    if [ "$DEPLOY_PDF2PDF" = true ]; then
        print_status "Setting up Adobe credentials..."
        if [ -z "$ADOBE_CLIENT_ID" ]; then
            read -p "Enter Adobe API Client ID: " ADOBE_CLIENT_ID
        fi
        if [ -z "$ADOBE_CLIENT_SECRET" ]; then
            read -sp "Enter Adobe API Client Secret: " ADOBE_CLIENT_SECRET
            echo
        fi

        JSON_TEMPLATE='{"client_credentials":{"PDF_SERVICES_CLIENT_ID":"","PDF_SERVICES_CLIENT_SECRET":""}}'
        SECRET_JSON=$(echo "$JSON_TEMPLATE" | jq --arg cid "$ADOBE_CLIENT_ID" --arg csec "$ADOBE_CLIENT_SECRET" \
            '.client_credentials.PDF_SERVICES_CLIENT_ID = $cid | .client_credentials.PDF_SERVICES_CLIENT_SECRET = $csec')

        aws secretsmanager create-secret --name /myapp/client_credentials \
            --secret-string "$SECRET_JSON" $AWS_PROFILE_ARG --region $REGION 2>/dev/null || \
        aws secretsmanager update-secret --secret-id /myapp/client_credentials \
            --secret-string "$SECRET_JSON" $AWS_PROFILE_ARG --region $REGION
        print_success "Adobe credentials configured"
    fi

    if [ "$DEPLOY_PDF2HTML" = true ]; then
        BUCKET_NAME="pdf2html-bucket-$ACCOUNT_ID-$REGION"

        # Create BDA project
        print_status "Creating BDA project..."
        BDA_PROJECT_NAME="pdf2html-bda-project-$(date +%Y%m%d-%H%M%S)"
        BDA_RESPONSE=$(aws bedrock-data-automation create-data-automation-project \
            --project-name "$BDA_PROJECT_NAME" \
            --standard-output-configuration '{
                "document": {
                    "extraction": {"granularity": {"types": ["DOCUMENT", "PAGE", "ELEMENT"]}, "boundingBox": {"state": "ENABLED"}},
                    "generativeField": {"state": "DISABLED"},
                    "outputFormat": {"textFormat": {"types": ["HTML"]}, "additionalFileFormat": {"state": "ENABLED"}}
                }
            }' $AWS_PROFILE_ARG --region $REGION)
        BDA_PROJECT_ARN=$(echo $BDA_RESPONSE | jq -r '.projectArn')
        print_success "BDA project created: $BDA_PROJECT_ARN"

        # Create S3 bucket
        if ! aws s3api head-bucket --bucket $BUCKET_NAME $AWS_PROFILE_ARG 2>/dev/null; then
            print_status "Creating S3 bucket: $BUCKET_NAME"
            if [ "$REGION" = "us-east-1" ]; then
                aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION $AWS_PROFILE_ARG
            else
                aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION $AWS_PROFILE_ARG \
                    --create-bucket-configuration LocationConstraint=$REGION
            fi
            aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled $AWS_PROFILE_ARG
            aws s3api put-object --bucket $BUCKET_NAME --key uploads/ $AWS_PROFILE_ARG
            aws s3api put-object --bucket $BUCKET_NAME --key output/ $AWS_PROFILE_ARG
            aws s3api put-object --bucket $BUCKET_NAME --key remediated/ $AWS_PROFILE_ARG
        fi

        aws s3api put-bucket-cors --bucket $BUCKET_NAME $AWS_PROFILE_ARG --cors-configuration '{
            "CORSRules": [{"AllowedHeaders": ["*"], "AllowedMethods": ["GET", "HEAD", "PUT", "POST", "DELETE"], "AllowedOrigins": ["*"], "ExposeHeaders": []}]
        }'

        # Create ECR repo
        aws ecr describe-repositories --repository-names pdf2html-lambda --region $REGION $AWS_PROFILE_ARG 2>/dev/null || \
            aws ecr create-repository --repository-name pdf2html-lambda --region $REGION $AWS_PROFILE_ARG
        print_success "S3 bucket and ECR repo ready"
    fi

    # Bootstrap CDK
    print_status "Bootstrapping CDK..."
    cdk bootstrap aws://$ACCOUNT_ID/$REGION $AWS_PROFILE_ARG 2>/dev/null || true
fi

# ============================================================
# PDF-to-PDF: CDK handles Docker builds via DockerImageAsset
# ============================================================
if [ "$DEPLOY_PDF2PDF" = true ]; then
    print_header "=== Deploying PDF-to-PDF ==="

    print_status "Installing Python dependencies..."
    pip install -r requirements.txt -q

    # Sync metrics_helper to adobe-autotag-container build context
    print_status "Syncing shared files to Docker build contexts..."
    cp lambda/shared/python/metrics_helper.py adobe-autotag-container/metrics_helper.py

    print_status "Deploying CDK stacks (PDFAccessibility + UsageMetrics)..."
    print_status "  (CDK will automatically rebuild adobe-autotag-container and alt-text-generator-container images)"
    cdk deploy PDFAccessibility PDFAccessibilityUsageMetrics --require-approval never $AWS_PROFILE_ARG
    print_success "PDF-to-PDF deployed"
fi

# ============================================================
# PDF-to-HTML: Manual Docker build required (fromEcr)
# ============================================================
if [ "$DEPLOY_PDF2HTML" = true ]; then
    print_header "=== Deploying PDF-to-HTML ==="

    BUCKET_NAME="pdf2html-bucket-$ACCOUNT_ID-$REGION"
    REPO_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/pdf2html-lambda"

    # Sync metrics_helper into pdf2html Docker context
    print_status "Syncing shared files to Docker build context..."
    cp lambda/shared/python/metrics_helper.py pdf2html/metrics_helper.py

    # Build and push Docker image
    print_status "Building pdf2html Docker image..."
    aws ecr get-login-password --region $REGION $AWS_PROFILE_ARG | \
        docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

    docker build --platform linux/amd64 -t $REPO_URI:latest pdf2html/
    docker push $REPO_URI:latest
    print_success "Docker image pushed to ECR"

    # Get existing BDA project ARN from CloudFormation (avoid creating duplicates)
    BDA_PROJECT_ARN=$(aws cloudformation describe-stacks --stack-name Pdf2HtmlStack \
        $AWS_PROFILE_ARG --region $REGION \
        --query 'Stacks[0].Parameters[?ParameterKey==`BdaProjectArn`].ParameterValue' \
        --output text 2>/dev/null || echo "")

    if [ -z "$BDA_PROJECT_ARN" ] || [ "$BDA_PROJECT_ARN" = "None" ]; then
        # Fallback: get most recent BDA project
        BDA_PROJECT_ARN=$(aws bedrock-data-automation list-data-automation-projects \
            $AWS_PROFILE_ARG --region $REGION \
            --query 'projects | sort_by(@, &creationTime) | [-1].projectArn' --output text 2>/dev/null || echo "")
    fi

    if [ -z "$BDA_PROJECT_ARN" ] || [ "$BDA_PROJECT_ARN" = "None" ]; then
        print_error "No BDA project found. Run with --init first."
        exit 1
    fi
    print_status "Using BDA project: $BDA_PROJECT_ARN"

    # Deploy CDK stack
    print_status "Deploying Pdf2HtmlStack..."
    cd pdf2html/cdk
    npm install --silent
    npx cdk deploy \
        --parameters BdaProjectArn=$BDA_PROJECT_ARN \
        --parameters BucketName=$BUCKET_NAME \
        --require-approval never
    cd ../..

    # Force Lambda to use the new image digest
    print_status "Updating Lambda to use new image..."
    IMAGE_DIGEST=$(aws ecr describe-images --repository-name pdf2html-lambda --region $REGION $AWS_PROFILE_ARG \
        --query 'imageDetails | sort_by(@, &imagePushedAt) | [-1].imageDigest' --output text)
    aws lambda update-function-code \
        --function-name Pdf2HtmlPipeline \
        --image-uri "$REPO_URI@$IMAGE_DIGEST" \
        $AWS_PROFILE_ARG --region $REGION > /dev/null
    print_success "PDF-to-HTML deployed and Lambda updated"
fi

# ============================================================
# Summary
# ============================================================
print_header "=== Deployment Complete ==="
[ "$DEPLOY_PDF2PDF" = true ] && print_success "✅ PDF-to-PDF: updated (CDK stacks + Docker images)"
[ "$DEPLOY_PDF2HTML" = true ] && print_success "✅ PDF-to-HTML: updated (Docker image + CDK stack + Lambda)"
echo ""
