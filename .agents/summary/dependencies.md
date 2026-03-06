# Dependencies and External Services

## External Service Dependencies

### 1. Adobe PDF Services API

**Purpose**: PDF structure tagging and content extraction

**Service Type**: Third-party REST API

**Authentication**: OAuth 2.0 client credentials

**Required Credentials**:
- Client ID
- Client Secret

**Pricing Model**: Enterprise contract or trial account

**Rate Limits**: Contract-dependent

**APIs Used**:
- **Autotag API**: Adds accessibility tags
- **Extract API**: Extracts images and structure

**Failure Impact**: 
- **Critical**: PDF-to-PDF solution cannot function without it
- **Mitigation**: Retry logic with exponential backoff

**Documentation**: https://developer.adobe.com/document-services/docs/overview/pdf-services-api/

---

### 2. AWS Bedrock

**Purpose**: AI-powered content generation

**Service Type**: AWS managed service

**Authentication**: IAM role-based

**Models Used**:
- **Amazon Nova Pro** (`amazon.nova-pro-v1:0`)
  - Multimodal (text + vision)
  - Alt text generation
  - Title generation
  - Remediation suggestions

**Pricing**:
- Input tokens: $0.0008 per 1K tokens
- Output tokens: $0.0032 per 1K tokens

**Rate Limits**:
- Requests per minute: Model-dependent
- Tokens per minute: Model-dependent

**Failure Impact**:
- **High**: AI-powered features unavailable
- **Mitigation**: Fall back to rule-based fixes

**Required Permissions**:
```json
{
    "Effect": "Allow",
    "Action": [
        "bedrock:InvokeModel"
    ],
    "Resource": "arn:aws:bedrock:*::foundation-model/amazon.nova-pro-v1:0"
}
```

---

### 3. AWS Bedrock Data Automation

**Purpose**: PDF parsing and structure extraction

**Service Type**: AWS managed service

**Authentication**: IAM role-based

**Pricing**: Per-page processing fee

**Rate Limits**: Project-level quotas

**Failure Impact**:
- **Critical**: PDF-to-HTML solution cannot function without it
- **Mitigation**: Retry logic, timeout handling

**Required Permissions**:
```json
{
    "Effect": "Allow",
    "Action": [
        "bedrock:CreateDataAutomationProject",
        "bedrock:InvokeDataAutomationAsync",
        "bedrock:GetDataAutomationStatus"
    ],
    "Resource": "*"
}
```

---

## AWS Service Dependencies

### 4. Amazon S3

**Purpose**: Object storage for PDFs and outputs

**Pricing**:
- Storage: $0.023 per GB/month (Standard)
- PUT requests: $0.005 per 1,000 requests
- GET requests: $0.0004 per 1,000 requests

**Features Used**:
- Event notifications
- Versioning
- Server-side encryption (SSE-S3)
- Object tagging
- Lifecycle policies (optional)

**Required Permissions**:
```json
{
    "Effect": "Allow",
    "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:PutObjectTagging"
    ],
    "Resource": [
        "arn:aws:s3:::bucket-name",
        "arn:aws:s3:::bucket-name/*"
    ]
}
```

---

### 5. AWS Lambda

**Purpose**: Serverless compute for lightweight operations

**Runtimes Used**:
- Python 3.12
- Java 11
- Node.js 18 (via container)

**Pricing**:
- Requests: $0.20 per 1M requests
- Duration: $0.0000166667 per GB-second

**Limits**:
- Timeout: 15 minutes (max)
- Memory: 10 GB (max)
- Deployment package: 250 MB (unzipped)
- Container image: 10 GB

**Functions Deployed**:
- PDF Splitter (Python)
- PDF Merger (Java)
- Title Generator (Python)
- Pre/Post Accessibility Checkers (Python)
- S3 Object Tagger (Python)
- PDF2HTML Pipeline (Python container)

---

### 6. Amazon ECS Fargate

**Purpose**: Containerized compute for heavy processing

**Pricing**:
- vCPU: $0.04048 per vCPU per hour
- Memory: $0.004445 per GB per hour

**Configuration**:
- CPU: 2 vCPU
- Memory: 4 GB
- Platform: Linux/AMD64

**Containers Deployed**:
- Adobe Autotag Processor (Python)
- Alt Text Generator (Node.js)

**Cold Start Optimization**:
- VPC endpoints for ECR (reduces 10-15s)
- zstd compression (2-3x faster than gzip)

---

### 7. AWS Step Functions

**Purpose**: Workflow orchestration

**Pricing**:
- State transitions: $0.025 per 1,000 transitions

**Features Used**:
- Map state (parallel execution)
- Error handling and retries
- CloudWatch integration

**Workflow**: PDF-to-PDF chunk processing

---

### 8. Amazon ECR

**Purpose**: Container image registry

**Pricing**:
- Storage: $0.10 per GB/month
- Data transfer: Standard AWS rates

**Images Stored**:
- Adobe Autotag container
- Alt Text Generator container
- PDF2HTML Lambda container

---

### 9. AWS Secrets Manager

**Purpose**: Secure credential storage

**Pricing**:
- Secret: $0.40 per secret per month
- API calls: $0.05 per 10,000 calls

**Secrets Stored**:
- Adobe PDF Services credentials

---

### 10. Amazon CloudWatch

**Purpose**: Monitoring, logging, and metrics

**Pricing**:
- Logs ingestion: $0.50 per GB
- Logs storage: $0.03 per GB/month
- Custom metrics: $0.30 per metric per month
- Dashboard: $3.00 per dashboard per month

**Features Used**:
- Log groups for all Lambda/ECS
- Custom metrics namespace: `PDFAccessibility`
- Usage metrics dashboard

---

### 11. Amazon VPC

**Purpose**: Network isolation for ECS tasks

**Pricing**:
- NAT Gateway: $0.045 per hour + $0.045 per GB processed
- VPC Endpoints: $0.01 per hour per AZ

**Configuration**:
- 2 Availability Zones
- Public and private subnets
- NAT Gateway for egress
- VPC endpoints for ECR and S3

---

### 12. AWS IAM

**Purpose**: Access control and permissions

**Pricing**: Free

**Roles Created**:
- Lambda execution roles
- ECS task roles
- ECS task execution roles
- Step Functions execution role

---

### 13. AWS CodeBuild

**Purpose**: CI/CD pipeline for deployment

**Pricing**:
- Build minutes: $0.005 per minute (general1.small)

**Usage**: Automated deployment via `deploy.sh`

---

## Python Dependencies

### Core Libraries

#### boto3
- **Version**: Latest
- **Purpose**: AWS SDK for Python
- **Used By**: All Python components
- **License**: Apache 2.0

#### aws-cdk-lib
- **Version**: 2.147.2
- **Purpose**: AWS CDK framework
- **Used By**: Infrastructure code
- **License**: Apache 2.0

### PDF Processing

#### pypdf
- **Version**: 4.3.1
- **Purpose**: PDF manipulation
- **Used By**: PDF Splitter, Title Generator
- **License**: BSD

#### PyMuPDF (fitz)
- **Version**: 1.24.14
- **Purpose**: PDF text extraction
- **Used By**: Title Generator
- **License**: AGPL

### HTML Processing

#### beautifulsoup4
- **Version**: Latest
- **Purpose**: HTML parsing
- **Used By**: PDF2HTML, Auditor, Remediator
- **License**: MIT

#### lxml
- **Version**: Latest
- **Purpose**: XML/HTML processing
- **Used By**: PDF2HTML, Auditor
- **License**: BSD

### Image Processing

#### Pillow
- **Version**: Latest
- **Purpose**: Image manipulation
- **Used By**: PDF2HTML, Alt Text Generator
- **License**: HPND

### Adobe SDK

#### pdfservices-sdk
- **Version**: 4.1.0
- **Purpose**: Adobe PDF Services API client
- **Used By**: Adobe Autotag container
- **License**: Proprietary (Adobe)

### Utilities

#### openpyxl
- **Version**: Latest
- **Purpose**: Excel file parsing
- **Used By**: Adobe Autotag container
- **License**: MIT

#### requests
- **Version**: 2.31.0
- **Purpose**: HTTP client
- **Used By**: Adobe SDK, BDA client
- **License**: Apache 2.0

---

## JavaScript Dependencies

### AWS SDK

#### @aws-sdk/client-bedrock-runtime
- **Version**: Latest
- **Purpose**: Bedrock API client
- **Used By**: Alt Text Generator
- **License**: Apache 2.0

#### @aws-sdk/client-s3
- **Version**: Latest
- **Purpose**: S3 API client
- **Used By**: Alt Text Generator, PDF2HTML CDK
- **License**: Apache 2.0

### PDF Processing

#### pdf-lib
- **Version**: Latest
- **Purpose**: PDF manipulation
- **Used By**: Alt Text Generator
- **License**: MIT

### CDK

#### aws-cdk-lib
- **Version**: Latest
- **Purpose**: AWS CDK framework
- **Used By**: PDF2HTML CDK stack
- **License**: Apache 2.0

#### @aws-cdk/aws-lambda-python-alpha
- **Version**: Latest
- **Purpose**: Python Lambda constructs
- **Used By**: PDF2HTML CDK stack
- **License**: Apache 2.0

---

## Java Dependencies

### PDF Processing

#### org.apache.pdfbox:pdfbox
- **Version**: Latest
- **Purpose**: PDF merging
- **Used By**: PDF Merger Lambda
- **License**: Apache 2.0

### AWS SDK

#### software.amazon.awssdk:s3
- **Version**: Latest
- **Purpose**: S3 operations
- **Used By**: PDF Merger Lambda
- **License**: Apache 2.0

#### com.amazonaws:aws-lambda-java-core
- **Version**: Latest
- **Purpose**: Lambda runtime
- **Used By**: PDF Merger Lambda
- **License**: Apache 2.0

---

## Development Dependencies

### Python

#### pytest
- **Purpose**: Testing framework
- **License**: MIT

#### black
- **Purpose**: Code formatting
- **License**: MIT

#### mypy
- **Purpose**: Type checking
- **License**: MIT

### Node.js

#### eslint
- **Purpose**: Linting
- **License**: MIT

#### prettier
- **Purpose**: Code formatting
- **License**: MIT

---

## Dependency Management

### Python
- **File**: `requirements.txt`
- **Tool**: pip
- **Virtual Environment**: venv

### JavaScript
- **File**: `package.json`, `package-lock.json`
- **Tool**: npm

### Java
- **File**: `pom.xml`
- **Tool**: Maven

---

## Security Considerations

### Dependency Scanning
- Regular updates for security patches
- Vulnerability scanning with AWS Inspector
- Dependabot alerts (GitHub)

### License Compliance
- All dependencies use permissive licenses
- Adobe SDK requires enterprise contract
- AGPL license (PyMuPDF) - consider alternatives for commercial use

### Supply Chain Security
- Pin dependency versions
- Use official package repositories
- Verify package signatures

---

## Version Compatibility

### Python
- **Minimum**: 3.9
- **Recommended**: 3.12
- **Lambda Runtime**: 3.12

### Node.js
- **Minimum**: 18
- **Recommended**: 18 LTS
- **Lambda Runtime**: 18

### Java
- **Minimum**: 11
- **Recommended**: 11
- **Lambda Runtime**: 11

### AWS CDK
- **Version**: 2.147.2
- **Compatibility**: AWS CDK v2

---

## Dependency Update Strategy

### Regular Updates
- Monthly security patch review
- Quarterly minor version updates
- Annual major version updates

### Testing
- Unit tests after updates
- Integration tests with AWS services
- End-to-end workflow validation

### Rollback Plan
- Version pinning in requirements files
- CDK snapshot testing
- Blue/green deployment for major changes
