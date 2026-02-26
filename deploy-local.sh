#!/bin/bash
set -e

# ========================================================================
# PDF Accessibility Solutions - Local Deployment Script
# ========================================================================
# Mirrors the behavior of deploy.sh but deploys directly from the local
# repo instead of via CodeBuild / GitHub.
# ========================================================================

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
    echo "Deploy PDF Accessibility solutions from local repo."
    echo ""
    echo "Options:"
    echo "  --pdf2pdf       Deploy PDF-to-PDF only"
    echo "  --pdf2html      Deploy PDF-to-HTML only"
    echo "  --all           Deploy both"
    echo "  --profile NAME  AWS CLI profile to use"
    echo "  --region REGION AWS region (default: from AWS config)"
    echo "  -h, --help      Show this help"
    echo ""
    echo "If no solution flag is given, you will be prompted to choose."
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive mode"
    echo "  $0 --all                    # Deploy everything"
    echo "  $0 --pdf2html               # Deploy only pdf2html"
    echo "  $0 --profile myprofile      # Use specific AWS profile"
}

# Parse arguments
DEPLOY_PDF2PDF=false
DEPLOY_PDF2HTML=false
AWS_PROFILE_ARG=""
REGION_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --pdf2pdf)   DEPLOY_PDF2PDF=true; shift ;;
        --pdf2html)  DEPLOY_PDF2HTML=true; shift ;;
        --all)       DEPLOY_PDF2PDF=true; DEPLOY_PDF2HTML=true; shift ;;
        --profile)   AWS_PROFILE_ARG="--profile $2"; export AWS_PROFILE="$2"; shift 2 ;;
        --region)    REGION_ARG="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ============================================================
# Interactive selection if no flags given
# ============================================================
if [ "$DEPLOY_PDF2PDF" = false ] && [ "$DEPLOY_PDF2HTML" = false ]; then
    echo ""
    print_header "Welcome to PDF Accessibility Solutions Local Deployment"
    print_header "======================================================="
    echo ""
    echo "This tool deploys PDF accessibility solutions from your local repo:"
    echo ""
    echo "1. PDF-to-PDF Remediation"
    echo "   - Maintains original PDF format"
    echo "   - Uses Adobe PDF Services API"
    echo "   - ECS + Step Functions processing"
    echo ""
    echo "2. PDF-to-HTML Remediation"
    echo "   - Converts PDFs to accessible HTML"
    echo "   - Uses AWS Bedrock Data Automation"
    echo "   - Serverless Lambda-based processing"
    echo ""

    while true; do
        echo "Which solution would you like to deploy?"
        echo "1) PDF-to-PDF Remediation"
        echo "2) PDF-to-HTML Remediation"
        echo "3) Both"
        echo ""
        read -p "Enter your choice (1, 2, or 3): " SOLUTION_CHOICE

        case $SOLUTION_CHOICE in
            1) DEPLOY_PDF2PDF=true; break ;;
            2) DEPLOY_PDF2HTML=true; break ;;
            3) DEPLOY_PDF2PDF=true; DEPLOY_PDF2HTML=true; break ;;
            *) print_error "Invalid choice. Please enter 1, 2, or 3."; echo "" ;;
        esac
    done
fi

# ============================================================
# Resolve AWS account and region
# ============================================================
print_status "Verifying AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity $AWS_PROFILE_ARG --query "Account" --output text 2>/dev/null || {
    print_error "Failed to get AWS account ID. Please ensure AWS CLI is configured."
    exit 1
})

REGION=${REGION_ARG:-${AWS_DEFAULT_REGION:-$(aws configure get region $AWS_PROFILE_ARG 2>/dev/null || echo "")}}

if [ -z "$REGION" ]; then
    print_error "Could not determine AWS region. Please set your region:"
    print_error "  export AWS_DEFAULT_REGION=us-east-1"
    print_error "  OR use: $0 --region us-east-1"
    exit 1
fi

# If Pdf2HtmlStack exists, use its region for consistency
if [ -z "$REGION_ARG" ]; then
    EXISTING_REGION=$(aws cloudformation describe-stacks --stack-name Pdf2HtmlStack $AWS_PROFILE_ARG --region "$REGION" --query 'Stacks[0].StackId' --output text 2>/dev/null | grep -oP ':\K[a-z]+-[a-z]+-[0-9]+' | head -1)
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
# PDF-to-PDF Deployment
# ============================================================
if [ "$DEPLOY_PDF2PDF" = true ]; then
    print_header "=== Deploying PDF-to-PDF Remediation ==="

    # --- Adobe credentials setup ---
    # Check if secret already exists in Secrets Manager
    EXISTING_SECRET=$(aws secretsmanager get-secret-value --secret-id /myapp/client_credentials \
        $AWS_PROFILE_ARG --region "$REGION" --query 'SecretString' --output text 2>/dev/null || echo "")

    if [ -z "$EXISTING_SECRET" ] || [ "$EXISTING_SECRET" = "None" ]; then
        print_status "Adobe PDF Services API credentials are required."
        print_status "(These will be stored securely in AWS Secrets Manager)"
        echo ""

        if [ -z "$ADOBE_CLIENT_ID" ]; then
            read -p "   Enter Adobe API Client ID: " ADOBE_CLIENT_ID
        fi
        if [ -z "$ADOBE_CLIENT_SECRET" ]; then
            read -sp "   Enter Adobe API Client Secret: " ADOBE_CLIENT_SECRET
            echo
        fi

        JSON_TEMPLATE='{"client_credentials":{"PDF_SERVICES_CLIENT_ID":"","PDF_SERVICES_CLIENT_SECRET":""}}'
        SECRET_JSON=$(echo "$JSON_TEMPLATE" | jq --arg cid "$ADOBE_CLIENT_ID" --arg csec "$ADOBE_CLIENT_SECRET" \
            '.client_credentials.PDF_SERVICES_CLIENT_ID = $cid | .client_credentials.PDF_SERVICES_CLIENT_SECRET = $csec')

        if aws secretsmanager create-secret --name /myapp/client_credentials \
            --secret-string "$SECRET_JSON" $AWS_PROFILE_ARG --region "$REGION" 2>/dev/null; then
            print_success "Adobe credentials stored in Secrets Manager"
        else
            aws secretsmanager update-secret --secret-id /myapp/client_credentials \
                --secret-string "$SECRET_JSON" $AWS_PROFILE_ARG --region "$REGION"
            print_success "Adobe credentials updated in Secrets Manager"
        fi
    else
        print_success "Adobe credentials already configured in Secrets Manager"
    fi

    # --- Install Python CDK dependencies ---
    print_status "Installing Python dependencies..."
    pip3 install -r requirements.txt -q

    # --- Bootstrap CDK if needed ---
    print_status "Ensuring CDK is bootstrapped..."
    cdk bootstrap aws://$ACCOUNT_ID/$REGION $AWS_PROFILE_ARG 2>/dev/null || true

    # --- Sync shared files to Docker build contexts ---
    print_status "Syncing shared files to Docker build contexts..."
    cp lambda/shared/python/metrics_helper.py adobe-autotag-container/metrics_helper.py

    # --- Deploy CDK stacks ---
    print_status "Deploying CDK stacks (PDFAccessibility + UsageMetrics)..."
    print_status "  CDK will automatically build adobe-autotag-container and alt-text-generator-container images"
    print_status "  This may take 3-5 minutes..."

    for i in {1..3}; do
        print_status "CDK deploy attempt $i/3..."
        if cdk deploy PDFAccessibility PDFAccessibilityUsageMetrics --require-approval never $AWS_PROFILE_ARG; then
            print_success "PDF-to-PDF deployed successfully"
            break
        else
            if [ $i -eq 3 ]; then
                print_error "All CDK deploy attempts failed"
                exit 1
            fi
            print_warning "CDK deploy failed on attempt $i, retrying in 30s..."
            sleep 30
        fi
    done
fi

# ============================================================
# PDF-to-HTML Deployment
# ============================================================
if [ "$DEPLOY_PDF2HTML" = true ]; then
    print_header "=== Deploying PDF-to-HTML Remediation ==="

    BUCKET_NAME="pdf2html-bucket-$ACCOUNT_ID-$REGION"
    REPO_NAME="pdf2html-lambda"
    REPO_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME"

    # --- Create ECR repository if it doesn't exist ---
    if ! aws ecr describe-repositories --repository-names $REPO_NAME --region "$REGION" $AWS_PROFILE_ARG 2>/dev/null; then
        print_status "Creating ECR repository: $REPO_NAME"
        aws ecr create-repository --repository-name $REPO_NAME --region "$REGION" $AWS_PROFILE_ARG
        print_success "ECR repository created"
    else
        print_success "ECR repository $REPO_NAME already exists"
    fi

    # --- Create S3 bucket if it doesn't exist ---
    if ! aws s3api head-bucket --bucket $BUCKET_NAME $AWS_PROFILE_ARG 2>/dev/null; then
        print_status "Creating S3 bucket: $BUCKET_NAME"
        if [ "$REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket $BUCKET_NAME --region "$REGION" $AWS_PROFILE_ARG
        else
            aws s3api create-bucket --bucket $BUCKET_NAME --region "$REGION" $AWS_PROFILE_ARG \
                --create-bucket-configuration LocationConstraint=$REGION
        fi
        aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled $AWS_PROFILE_ARG
        aws s3api put-object --bucket $BUCKET_NAME --key uploads/ $AWS_PROFILE_ARG
        aws s3api put-object --bucket $BUCKET_NAME --key output/ $AWS_PROFILE_ARG
        aws s3api put-object --bucket $BUCKET_NAME --key remediated/ $AWS_PROFILE_ARG
        print_success "S3 bucket created"
    else
        print_success "S3 bucket $BUCKET_NAME already exists"
    fi

    # Always apply CORS policy
    aws s3api put-bucket-cors --bucket $BUCKET_NAME $AWS_PROFILE_ARG --cors-configuration '{
        "CORSRules": [{"AllowedHeaders": ["*"], "AllowedMethods": ["GET", "HEAD", "PUT", "POST", "DELETE"], "AllowedOrigins": ["*"], "ExposeHeaders": []}]
    }'

    # --- Resolve BDA project ARN ---
    # Try existing CloudFormation stack first
    BDA_PROJECT_ARN=$(aws cloudformation describe-stacks --stack-name Pdf2HtmlStack \
        $AWS_PROFILE_ARG --region "$REGION" \
        --query 'Stacks[0].Parameters[?ParameterKey==`BdaProjectArn`].ParameterValue' \
        --output text 2>/dev/null || echo "")

    # Fallback: most recent BDA project
    if [ -z "$BDA_PROJECT_ARN" ] || [ "$BDA_PROJECT_ARN" = "None" ]; then
        BDA_PROJECT_ARN=$(aws bedrock-data-automation list-data-automation-projects \
            $AWS_PROFILE_ARG --region "$REGION" \
            --query 'projects | sort_by(@, &creationTime) | [-1].projectArn' --output text 2>/dev/null || echo "")
    fi

    # If no BDA project exists, create one
    if [ -z "$BDA_PROJECT_ARN" ] || [ "$BDA_PROJECT_ARN" = "None" ]; then
        print_status "No existing BDA project found. Creating one..."
        BDA_PROJECT_NAME="pdf2html-bda-project-$(date +%Y%m%d-%H%M%S)"
        BDA_RESPONSE=$(aws bedrock-data-automation create-data-automation-project \
            --project-name "$BDA_PROJECT_NAME" \
            --standard-output-configuration '{
                "document": {
                    "extraction": {
                        "granularity": {"types": ["DOCUMENT", "PAGE", "ELEMENT"]},
                        "boundingBox": {"state": "ENABLED"}
                    },
                    "generativeField": {"state": "DISABLED"},
                    "outputFormat": {
                        "textFormat": {"types": ["HTML"]},
                        "additionalFileFormat": {"state": "ENABLED"}
                    }
                }
            }' $AWS_PROFILE_ARG --region "$REGION" 2>/dev/null || {
            print_error "Failed to create BDA project. Ensure you have bedrock-data-automation permissions."
            exit 1
        })
        BDA_PROJECT_ARN=$(echo $BDA_RESPONSE | jq -r '.projectArn')
        print_success "BDA project created: $BDA_PROJECT_ARN"
    else
        print_success "Using existing BDA project: $BDA_PROJECT_ARN"
    fi

    # --- Sync shared files into Docker build context ---
    print_status "Syncing shared files to Docker build context..."
    cp lambda/shared/python/metrics_helper.py pdf2html/metrics_helper.py

    # --- Build and push Docker image ---
    print_status "Building pdf2html Docker image..."
    aws ecr get-login-password --region "$REGION" $AWS_PROFILE_ARG | \
        docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

    docker build --platform linux/amd64 -t $REPO_URI:latest pdf2html/

    print_status "Pushing Docker image to ECR..."
    if ! docker push $REPO_URI:latest; then
        print_warning "Push failed, refreshing ECR login and retrying..."
        aws ecr get-login-password --region "$REGION" $AWS_PROFILE_ARG | \
            docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
        docker push $REPO_URI:latest
    fi
    print_success "Docker image pushed to ECR"

    # Verify image exists
    print_status "Verifying image in ECR..."
    aws ecr describe-images --repository-name $REPO_NAME --region "$REGION" $AWS_PROFILE_ARG \
        --image-ids imageTag=latest > /dev/null
    print_success "Image verified in ECR"

    # --- Bootstrap CDK and deploy pdf2html stack ---
    print_status "Deploying Pdf2HtmlStack..."
    cd pdf2html/cdk
    npm install --silent

    export CDK_DEFAULT_ACCOUNT=$ACCOUNT_ID
    export CDK_DEFAULT_REGION=$REGION

    npx cdk bootstrap aws://$ACCOUNT_ID/$REGION $AWS_PROFILE_ARG 2>/dev/null || true
    npx cdk deploy --app "node bin/app.js" \
        --parameters BdaProjectArn=$BDA_PROJECT_ARN \
        --parameters BucketName=$BUCKET_NAME \
        --require-approval never
    cd ../..

    # --- Force Lambda to pick up the new image digest ---
    print_status "Updating Lambda to use new image..."
    IMAGE_DIGEST=$(aws ecr describe-images --repository-name $REPO_NAME --region "$REGION" $AWS_PROFILE_ARG \
        --query 'imageDetails | sort_by(@, &imagePushedAt) | [-1].imageDigest' --output text)
    aws lambda update-function-code \
        --function-name Pdf2HtmlPipeline \
        --image-uri "$REPO_URI@$IMAGE_DIGEST" \
        $AWS_PROFILE_ARG --region "$REGION" > /dev/null
    print_success "PDF-to-HTML deployed and Lambda updated"
fi

# ============================================================
# Summary
# ============================================================
print_header "=== Deployment Complete ==="
[ "$DEPLOY_PDF2PDF" = true ] && print_success "PDF-to-PDF: deployed (CDK stacks + Docker images)"
[ "$DEPLOY_PDF2HTML" = true ] && print_success "PDF-to-HTML: deployed (Docker image + CDK stack + Lambda)"
echo ""
print_status "Monitor your deployment in the AWS Console:"
print_status "  https://console.aws.amazon.com/cloudformation"
echo ""
