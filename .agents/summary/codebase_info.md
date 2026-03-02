# Codebase Information

## Overview

**Project**: PDF Accessibility Solutions  
**Organization**: Arizona State University's AI Cloud Innovation Center (AI CIC)  
**Purpose**: Automated PDF accessibility remediation using AWS services and generative AI

## Statistics

- **Total Files**: 140
- **Lines of Code**: 27,949
- **Primary Languages**: Python (95 files), JavaScript (3 files), Java (2 files), Shell (2 files)
- **Size Category**: Medium (M)

## Language Distribution

| Language | Files | Functions | Classes | LOC |
|----------|-------|-----------|---------|-----|
| Python | 95 | 457 | 74 | ~25,000 |
| JavaScript | 3 | 5 | 1 | ~700 |
| Java | 2 | 7 | 2 | ~200 |
| Shell | 2 | 16 | 0 | ~1,300 |

## Technology Stack

### Infrastructure & Deployment
- **AWS CDK** (Python & JavaScript): Infrastructure as Code
- **AWS CloudFormation**: Stack deployment
- **CodeBuild**: CI/CD pipeline

### AWS Services
- **Compute**: Lambda, ECS Fargate, Step Functions
- **Storage**: S3
- **AI/ML**: Bedrock (Nova Pro model), Bedrock Data Automation
- **Monitoring**: CloudWatch, CloudWatch Dashboards
- **Security**: Secrets Manager, IAM
- **Networking**: VPC, VPC Endpoints

### External Services
- **Adobe PDF Services API**: PDF auto-tagging and extraction

### Python Dependencies
- `aws-cdk-lib==2.147.2`
- `boto3`: AWS SDK
- `beautifulsoup4`: HTML parsing
- `lxml`: XML/HTML processing
- `pypdf`: PDF manipulation
- `PyMuPDF (fitz)`: PDF text extraction
- `Pillow`: Image processing

### JavaScript Dependencies
- `@aws-cdk/aws-lambda-python-alpha`: Lambda Python constructs
- `pdf-lib`: PDF manipulation
- `@aws-sdk/client-bedrock-runtime`: Bedrock API client

## Repository Structure

```
PDF_Accessibility/
├── .agents/                          # AI assistant documentation
├── cdk/                              # CDK infrastructure (Python)
│   ├── usage_metrics_stack.py        # CloudWatch metrics dashboard
│   └── cdk_stack.py                  # Base stack definition
├── lambda/                           # Lambda functions
│   ├── pdf-splitter-lambda/          # Splits PDFs into chunks
│   ├── pdf-merger-lambda/            # Merges processed PDFs (Java)
│   ├── title-generator-lambda/       # Generates PDF titles
│   ├── pre-remediation-accessibility-checker/
│   ├── post-remediation-accessibility-checker/
│   ├── s3_object_tagger/             # Tags S3 objects with user metadata
│   └── shared/                       # Shared utilities (metrics)
├── pdf2html/                         # PDF-to-HTML solution
│   ├── cdk/                          # CDK infrastructure (JavaScript)
│   ├── content_accessibility_utility_on_aws/  # Core library
│   │   ├── audit/                    # Accessibility auditing
│   │   ├── remediate/                # Accessibility remediation
│   │   ├── pdf2html/                 # PDF to HTML conversion
│   │   ├── batch/                    # Batch processing
│   │   └── utils/                    # Utilities
│   ├── lambda_function.py            # Lambda entry point
│   └── Dockerfile                    # Lambda container image
├── adobe-autotag-container/          # ECS container for Adobe API
├── alt-text-generator-container/     # ECS container for alt text (Node.js)
├── docs/                             # Documentation
├── app.py                            # Main CDK app (PDF-to-PDF)
├── deploy.sh                         # Unified deployment script
└── deploy-local.sh                   # Local deployment script

```

## Supported Standards

- **WCAG 2.1 Level AA**: Web Content Accessibility Guidelines
- **PDF/UA**: PDF Universal Accessibility (ISO 14289)

## Development Environment

- **Python**: 3.9+ (Lambda runtime: 3.12)
- **Node.js**: 18+ (for JavaScript Lambda and CDK)
- **Java**: 11+ (for PDF merger Lambda)
- **Docker**: Required for container builds
- **AWS CLI**: Required for deployment

## Build Artifacts

- **CDK Output**: `cdk.out/` directory
- **Docker Images**: Pushed to ECR
- **Lambda Packages**: Zipped and uploaded to S3
- **CloudFormation Templates**: Generated in `cdk.out/`
