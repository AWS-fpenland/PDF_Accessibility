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
print_header() { echo -e "${CYAN}$1${NC}"; }

DEPLOYED_SOLUTIONS=()
PDF2PDF_BUCKET=""
PDF2HTML_BUCKET=""

echo ""
print_header "🎉 PDF Accessibility Solutions - Local Deployment 🎉"
print_header "====================================================="
echo ""
echo "1. 📄 PDF-to-PDF Remediation"
echo "2. 🌐 PDF-to-HTML Remediation"
echo ""

deploy_pdf2pdf() {
    print_header "🚀 Deploying PDF-to-PDF Remediation..."
    
    # Adobe credentials
    if [ -z "$ADOBE_CLIENT_ID" ]; then
        read -p "Enter Adobe API Client ID: " ADOBE_CLIENT_ID
    fi
    if [ -z "$ADOBE_CLIENT_SECRET" ]; then
        read -p "Enter Adobe API Client Secret: " ADOBE_CLIENT_SECRET
    fi
    
    print_status "🔒 Setting up Adobe credentials in Secrets Manager..."
    JSON_TEMPLATE='{"client_credentials":{"PDF_SERVICES_CLIENT_ID":"","PDF_SERVICES_CLIENT_SECRET":""}}'
    echo "$JSON_TEMPLATE" | jq --arg cid "$ADOBE_CLIENT_ID" --arg csec "$ADOBE_CLIENT_SECRET" \
        '.client_credentials.PDF_SERVICES_CLIENT_ID = $cid | .client_credentials.PDF_SERVICES_CLIENT_SECRET = $csec' > /tmp/client_credentials.json
    
    aws secretsmanager create-secret --name /myapp/client_credentials \
        --secret-string file:///tmp/client_credentials.json 2>/dev/null || \
    aws secretsmanager update-secret --secret-id /myapp/client_credentials \
        --secret-string file:///tmp/client_credentials.json
    rm -f /tmp/client_credentials.json
    print_success "✅ Credentials configured"
    
    print_status "📦 Installing dependencies..."
    pip install -r requirements.txt -q
    
    print_status "🔧 Bootstrapping CDK..."
    cdk bootstrap 2>/dev/null || true
    
    print_status "🚀 Deploying stacks..."
    cdk deploy --all --require-approval never
    
    PDF2PDF_BUCKET=$(aws cloudformation describe-stacks --stack-name "PDFAccessibility" \
        --query 'Stacks[0].Outputs[?contains(OutputKey, `Bucket`)].OutputValue' --output text 2>/dev/null | head -1)
    
    if [ -z "$PDF2PDF_BUCKET" ]; then
        PDF2PDF_BUCKET=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `pdfaccessibility`)] | sort_by(@, &CreationDate) | [-1].Name' --output text)
    fi
    
    DEPLOYED_SOLUTIONS+=("pdf2pdf")
    print_success "✅ PDF-to-PDF deployed: $PDF2PDF_BUCKET"
}

deploy_pdf2html() {
    print_header "🚀 Deploying PDF-to-HTML Remediation..."
    
    BDA_PROJECT_NAME="pdf2html-bda-$(date +%Y%m%d-%H%M%S)"
    print_status "Creating BDA project: $BDA_PROJECT_NAME"
    
    BDA_RESPONSE=$(aws bedrock-data-automation create-data-automation-project \
        --project-name "$BDA_PROJECT_NAME" \
        --standard-output-configuration '{
            "document": {
                "extraction": {"granularity": {"types": ["DOCUMENT", "PAGE", "ELEMENT"]}, "boundingBox": {"state": "ENABLED"}},
                "generativeField": {"state": "DISABLED"},
                "outputFormat": {"textFormat": {"types": ["HTML"]}, "additionalFileFormat": {"state": "ENABLED"}}
            }
        }' --region $REGION)
    
    BDA_PROJECT_ARN=$(echo $BDA_RESPONSE | jq -r '.projectArn')
    BUCKET_NAME="pdf2html-bucket-$ACCOUNT_ID-$REGION"
    print_success "✅ BDA project created"
    
    cd pdf2html
    
    print_status "📦 Creating S3 bucket..."
    if ! aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null; then
        if [ "$REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION
        else
            aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION
        fi
        aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled
        aws s3api put-object --bucket $BUCKET_NAME --key uploads/
        aws s3api put-object --bucket $BUCKET_NAME --key output/
        aws s3api put-object --bucket $BUCKET_NAME --key remediated/
    fi
    
    aws s3api put-bucket-cors --bucket $BUCKET_NAME --cors-configuration '{
        "CORSRules": [{"AllowedHeaders": ["*"], "AllowedMethods": ["GET", "HEAD", "PUT", "POST", "DELETE"], "AllowedOrigins": ["*"], "ExposeHeaders": []}]
    }'
    
    print_status "🐳 Building Docker image..."
    REPO_NAME="pdf2html-lambda"
    aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION 2>/dev/null || \
        aws ecr create-repository --repository-name $REPO_NAME --region $REGION
    
    REPO_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME"
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
    
    docker build --platform linux/amd64 -t $REPO_URI:latest .
    docker push $REPO_URI:latest
    print_success "✅ Docker image pushed"
    
    print_status "🚀 Deploying CDK stack..."
    cd cdk
    npm install
    export CDK_DEFAULT_ACCOUNT=$ACCOUNT_ID
    export CDK_DEFAULT_REGION=$REGION
    npx cdk bootstrap aws://$ACCOUNT_ID/$REGION
    npx cdk deploy --parameters BdaProjectArn=$BDA_PROJECT_ARN --parameters BucketName=$BUCKET_NAME --require-approval never
    
    cd ../..
    PDF2HTML_BUCKET="$BUCKET_NAME"
    DEPLOYED_SOLUTIONS+=("pdf2html")
    print_success "✅ PDF-to-HTML deployed: $PDF2HTML_BUCKET"
}

# Main
while true; do
    echo "Which solution would you like to deploy?"
    echo "1) PDF-to-PDF"
    echo "2) PDF-to-HTML"
    echo "3) Both"
    read -p "Choice (1/2/3): " CHOICE
    
    case $CHOICE in
        1) DEPLOY_PDF2PDF=true; break ;;
        2) DEPLOY_PDF2HTML=true; break ;;
        3) DEPLOY_PDF2PDF=true; DEPLOY_PDF2HTML=true; break ;;
        *) print_error "Invalid choice" ;;
    esac
done

print_status "🔍 Verifying AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REGION=${AWS_DEFAULT_REGION:-$(aws configure get region)}
print_success "✅ Account: $ACCOUNT_ID, Region: $REGION"

[ "$DEPLOY_PDF2PDF" = true ] && deploy_pdf2pdf
[ "$DEPLOY_PDF2HTML" = true ] && deploy_pdf2html

echo ""
print_header "🎊 Deployment Complete!"
print_header "======================="
for solution in "${DEPLOYED_SOLUTIONS[@]}"; do
    [ "$solution" = "pdf2pdf" ] && print_status "   ✅ PDF-to-PDF: $PDF2PDF_BUCKET"
    [ "$solution" = "pdf2html" ] && print_status "   ✅ PDF-to-HTML: $PDF2HTML_BUCKET"
done
echo ""
