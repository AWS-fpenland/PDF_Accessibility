# PDF Accessibility Solutions - AI Assistant Guide

**Version**: 1.0  
**Last Updated**: 2026-03-02  
**Codebase Commit**: `8d6102bc644641c94f5a695a32ea50c19b3c8d68`

## Purpose

This document provides AI coding assistants with essential context about the PDF Accessibility Solutions codebase. It focuses on information not typically found in README.md or CONTRIBUTING.md, including file organization, coding patterns, testing procedures, and package-specific guidance.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Directory Structure](#directory-structure)
3. [Coding Patterns and Conventions](#coding-patterns-and-conventions)
4. [Development Workflow](#development-workflow)
5. [Testing Guidelines](#testing-guidelines)
6. [Package-Specific Guidance](#package-specific-guidance)
7. [Common Tasks](#common-tasks)
8. [Troubleshooting](#troubleshooting)

---

## Project Overview

### What This Project Does

PDF Accessibility Solutions provides two complementary approaches to making PDF documents accessible according to WCAG 2.1 Level AA standards:

1. **PDF-to-PDF Remediation**: Maintains PDF format while adding accessibility features (tags, alt text, structure)
2. **PDF-to-HTML Remediation**: Converts PDFs to accessible HTML with full WCAG compliance

### Key Technologies

- **Infrastructure**: AWS CDK (Python & JavaScript)
- **Compute**: AWS Lambda (Python, Java, Node.js), ECS Fargate
- **AI/ML**: Amazon Bedrock (Nova Pro), Bedrock Data Automation
- **Storage**: Amazon S3
- **Orchestration**: AWS Step Functions
- **Monitoring**: CloudWatch Logs & Metrics

### Architecture Pattern

Event-driven, serverless architecture:
- S3 events trigger processing pipelines
- Step Functions orchestrate parallel processing
- ECS Fargate handles heavy compute tasks
- Lambda handles lightweight operations

---

## Directory Structure

```
PDF_Accessibility/
├── .agents/summary/          # AI assistant documentation (this guide's source)
├── cdk/                      # CDK infrastructure (Python)
│   ├── usage_metrics_stack.py
│   └── cdk_stack.py
├── lambda/                   # Lambda functions
│   ├── pdf-splitter-lambda/  # Python: Splits PDFs into pages
│   ├── pdf-merger-lambda/    # Java: Merges processed PDFs
│   ├── title-generator-lambda/  # Python: Generates titles
│   ├── pre-remediation-accessibility-checker/  # Python
│   ├── post-remediation-accessibility-checker/ # Python
│   ├── s3_object_tagger/     # Python: Tags S3 objects
│   └── shared/               # Shared utilities (metrics_helper.py)
├── pdf2html/                 # PDF-to-HTML solution
│   ├── cdk/                  # CDK infrastructure (JavaScript)
│   ├── content_accessibility_utility_on_aws/  # Core library
│   │   ├── audit/            # Accessibility auditing
│   │   ├── remediate/        # Accessibility remediation
│   │   ├── pdf2html/         # PDF to HTML conversion
│   │   ├── batch/            # Batch processing
│   │   └── utils/            # Utilities
│   ├── lambda_function.py    # Lambda entry point
│   ├── metrics_helper.py     # Metrics tracking
│   └── Dockerfile            # Lambda container image
├── adobe-autotag-container/  # ECS: Adobe API integration (Python)
├── alt-text-generator-container/  # ECS: Alt text generation (Node.js)
├── docs/                     # Documentation
├── app.py                    # Main CDK app (PDF-to-PDF)
├── deploy.sh                 # Unified deployment script
└── deploy-local.sh           # Local deployment script
```

### Key File Locations

**Infrastructure**:
- PDF-to-PDF CDK: `app.py`, `cdk/usage_metrics_stack.py`
- PDF-to-HTML CDK: `pdf2html/cdk/lib/pdf2html-stack.js`

**Core Logic**:
- PDF-to-PDF: Lambda functions in `lambda/` + ECS containers
- PDF-to-HTML: `pdf2html/content_accessibility_utility_on_aws/`

**Shared Code**:
- Metrics: `lambda/shared/metrics_helper.py` (duplicated in containers)
- Configuration: `pdf2html/content_accessibility_utility_on_aws/utils/config.py`

**Deployment**:
- One-click: `deploy.sh`
- Local: `deploy-local.sh`
- CI/CD: `buildspec-unified.yml`

---

## Coding Patterns and Conventions

### Python Code Style

**Formatting**:
- Follow PEP 8
- Use 4 spaces for indentation
- Max line length: 100 characters (flexible)
- Use type hints where practical

**Naming Conventions**:
- Functions: `snake_case`
- Classes: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Private methods: `_leading_underscore`

**Example Pattern**:
```python
from typing import Dict, List, Optional
import boto3
from metrics_helper import MetricsContext

def process_pdf_document(
    bucket: str,
    key: str,
    user_id: Optional[str] = None
) -> Dict[str, any]:
    """Process a PDF document for accessibility.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        user_id: Optional user identifier for metrics
        
    Returns:
        Dictionary with processing results
    """
    with MetricsContext(user_id=user_id, solution="PDF2PDF") as metrics:
        try:
            # Processing logic
            metrics.track_pages_processed(page_count)
            return {"status": "success"}
        except Exception as e:
            metrics.track_error(str(e))
            raise
```

### JavaScript Code Style

**Formatting**:
- Use 2 spaces for indentation
- Semicolons required
- Use `const` by default, `let` when needed
- Async/await for asynchronous code

**Example Pattern**:
```javascript
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');

async function generateAltText(imageBuffer, context) {
  const client = new BedrockRuntimeClient({ region: process.env.AWS_REGION });
  
  const payload = {
    messages: [{
      role: 'user',
      content: [
        { text: `Generate alt text for this image. Context: ${context}` },
        { image: { source: { bytes: imageBuffer } } }
      ]
    }],
    inferenceConfig: { maxTokens: 512, temperature: 0.7 }
  };
  
  const response = await client.send(new InvokeModelCommand({
    modelId: 'amazon.nova-pro-v1:0',
    body: JSON.stringify(payload)
  }));
  
  return JSON.parse(response.body).output.message.content[0].text;
}
```

### Java Code Style

**Formatting**:
- Follow Google Java Style Guide
- Use 4 spaces for indentation
- Braces on same line

**Example Pattern** (PDF Merger):
```java
public class App implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private final S3Client s3Client = S3Client.builder().build();
    
    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        String bucket = (String) input.get("bucket");
        List<String> chunks = (List<String>) input.get("chunks");
        
        try {
            PDDocument mergedDoc = new PDDocument();
            for (String chunk : chunks) {
                PDDocument doc = downloadPDF(bucket, chunk);
                for (PDPage page : doc.getPages()) {
                    mergedDoc.addPage(page);
                }
                doc.close();
            }
            
            String outputKey = uploadPDF(bucket, mergedDoc);
            return Map.of("status", "success", "output_key", outputKey);
        } catch (IOException e) {
            context.getLogger().log("Error: " + e.getMessage());
            throw new RuntimeException(e);
        }
    }
}
```

### Error Handling Pattern

**Consistent Error Handling**:
```python
def operation_with_retry(max_retries=3, backoff_rate=2.0):
    """Decorator for operations with exponential backoff retry."""
    def decorator(func):
        def wrapper(*args, **kwargs):
            delay = 1
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_retries - 1:
                        logger.error(f"Failed after {max_retries} attempts: {e}")
                        raise
                    logger.warning(f"Attempt {attempt + 1} failed, retrying in {delay}s")
                    time.sleep(delay)
                    delay *= backoff_rate
        return wrapper
    return decorator
```

### Metrics Publishing Pattern

**Always use MetricsContext**:
```python
with MetricsContext(user_id=user_id, solution="PDF2PDF") as metrics:
    start_time = time.time()
    
    # Track input
    metrics.track_file_size(file_size_bytes)
    
    # Perform operation
    result = process_document()
    
    # Track output
    metrics.track_pages_processed(page_count)
    metrics.track_processing_duration(time.time() - start_time)
    
    # Track API calls
    metrics.track_adobe_api_call()
    metrics.track_bedrock_invocation(input_tokens, output_tokens)
    
    # Estimate costs
    metrics.estimate_cost(
        adobe_calls=1,
        bedrock_input_tokens=input_tokens,
        bedrock_output_tokens=output_tokens
    )
```

---

## Development Workflow

### Setting Up Local Environment

**Prerequisites**:
- Python 3.9+ (recommend 3.12)
- Node.js 18+
- Java 11+ (for PDF merger)
- Docker (for container builds)
- AWS CLI configured

**Setup Steps**:
```bash
# Clone repository
git clone https://github.com/ASUCICREPO/PDF_Accessibility.git
cd PDF_Accessibility

# Python setup
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# CDK setup
npm install -g aws-cdk
cdk bootstrap  # First time only

# PDF2HTML setup
cd pdf2html
pip install -e .
cd ..
```

### Making Changes

**Workflow**:
1. Create feature branch: `git checkout -b feature/your-feature`
2. Make changes
3. Test locally (see Testing Guidelines)
4. Commit with descriptive message
5. Push and create PR

**Commit Message Format**:
```
type(scope): description

feat(pdf-splitter): add support for encrypted PDFs
fix(remediation): correct heading hierarchy detection
docs(readme): update deployment instructions
```

### Local Testing

**Test Lambda Locally**:
```bash
# PDF Splitter example
cd lambda/pdf-splitter-lambda
python -c "from main import lambda_handler; lambda_handler({'Records': [...]}, None)"
```

**Test CDK Synth**:
```bash
cdk synth  # Generates CloudFormation templates
cdk diff   # Shows changes before deployment
```

**Test PDF2HTML Library**:
```bash
cd pdf2html
python -m content_accessibility_utility_on_aws.cli convert input.pdf output/
```

---

## Testing Guidelines

### Unit Testing

**Framework**: pytest

**Test Structure**:
```
tests/
├── unit/
│   ├── test_pdf_splitter.py
│   ├── test_auditor.py
│   └── test_remediation.py
├── integration/
│   └── test_end_to_end.py
└── fixtures/
    └── sample.pdf
```

**Example Unit Test**:
```python
import pytest
from unittest.mock import Mock, patch
from pdf_splitter import split_pdf_into_pages

@pytest.fixture
def mock_s3_client():
    with patch('boto3.client') as mock:
        yield mock.return_value

def test_split_pdf_into_pages(mock_s3_client):
    # Arrange
    bucket = "test-bucket"
    key = "test.pdf"
    
    # Act
    result = split_pdf_into_pages(bucket, key)
    
    # Assert
    assert result['page_count'] > 0
    assert mock_s3_client.put_object.called
```

### Integration Testing

**Test with LocalStack** (for AWS services):
```bash
# Start LocalStack
docker run -d -p 4566:4566 localstack/localstack

# Run integration tests
AWS_ENDPOINT_URL=http://localhost:4566 pytest tests/integration/
```

### End-to-End Testing

**Manual E2E Test**:
1. Deploy to test environment
2. Upload test PDF to S3
3. Monitor CloudWatch Logs
4. Verify output in S3
5. Check CloudWatch metrics

**Test PDFs**: Use `tests/fixtures/` for consistent test data

---

## Package-Specific Guidance

### lambda/pdf-splitter-lambda

**Purpose**: Splits large PDFs into individual pages for parallel processing

**Key Functions**:
- `lambda_handler()`: Entry point
- `split_pdf_into_pages()`: Core splitting logic

**Dependencies**: `pypdf`, `boto3`

**Testing**: Mock S3 operations, use small test PDFs

**Common Issues**:
- Memory limits with large PDFs → Increase Lambda memory
- Timeout → Increase timeout or split into smaller chunks

---

### adobe-autotag-container

**Purpose**: Adds accessibility tags using Adobe PDF Services API

**Key Functions**:
- `main()`: Entry point
- `autotag_pdf_with_options()`: Calls Adobe API
- `extract_images_from_extract_api()`: Extracts images

**Dependencies**: `pdfservices-sdk`, `boto3`

**Configuration**:
- Adobe credentials from Secrets Manager
- Environment variables: `AWS_REGION`, `BUCKET_NAME`

**Testing**: Use Adobe trial account, mock Secrets Manager

**Common Issues**:
- Adobe API rate limits → Implement backoff
- Credential errors → Verify Secrets Manager access

---

### alt-text-generator-container

**Purpose**: Generates alt text for images using Bedrock

**Key Functions**:
- `startProcess()`: Entry point
- `generateAltText()`: Calls Bedrock
- `modifyPDF()`: Embeds alt text

**Dependencies**: `pdf-lib`, `@aws-sdk/client-bedrock-runtime`

**Configuration**:
- Bedrock model: `amazon.nova-pro-v1:0`
- Environment variables: `AWS_REGION`, `BUCKET_NAME`

**Testing**: Mock Bedrock responses, use sample images

**Common Issues**:
- Bedrock throttling → Implement rate limiting
- Large images → Resize before sending to Bedrock

---

### pdf2html/content_accessibility_utility_on_aws

**Purpose**: Core library for PDF-to-HTML conversion and remediation

**Key Modules**:
- `audit/`: Accessibility auditing (WCAG checks)
- `remediate/`: Accessibility remediation (fixes)
- `pdf2html/`: PDF to HTML conversion (BDA integration)
- `utils/`: Shared utilities

**Entry Points**:
- CLI: `cli.py`
- API: `api.py`
- Lambda: `../lambda_function.py`

**Configuration**: `utils/config.py` with environment variables

**Testing**: Use pytest with fixtures in `tests/`

**Common Issues**:
- BDA timeouts → Increase polling timeout
- Complex tables → May require manual review
- Image context → Improve surrounding text extraction

---

### cdk/

**Purpose**: Infrastructure as Code for PDF-to-PDF solution

**Key Files**:
- `app.py`: Main CDK app
- `usage_metrics_stack.py`: CloudWatch dashboard

**Deployment**:
```bash
cdk synth  # Generate CloudFormation
cdk deploy --all  # Deploy all stacks
```

**Testing**: `cdk synth` to validate, `cdk diff` to preview changes

**Common Issues**:
- Resource limits → Request quota increases
- VPC configuration → Verify subnet availability

---

## Common Tasks

### Adding a New Lambda Function

1. Create directory in `lambda/`
2. Add `main.py` (or `App.java`) with handler
3. Add `requirements.txt` (or `pom.xml`)
4. Add `Dockerfile` if using container
5. Update `app.py` to define Lambda resource
6. Add IAM permissions
7. Add CloudWatch log group
8. Deploy with `cdk deploy`

**Example CDK Code**:
```python
new_lambda = lambda_.Function(
    self, "NewFunction",
    runtime=lambda_.Runtime.PYTHON_3_12,
    handler="main.lambda_handler",
    code=lambda_.Code.from_asset("lambda/new-function"),
    timeout=Duration.minutes(5),
    memory_size=1024,
    environment={
        "BUCKET_NAME": bucket.bucket_name
    }
)
bucket.grant_read_write(new_lambda)
```

### Adding a New Accessibility Check

1. Create check class in `pdf2html/content_accessibility_utility_on_aws/audit/checks/`
2. Inherit from `AccessibilityCheck`
3. Implement `check()` method
4. Register in `audit/checks/__init__.py`
5. Add test in `tests/unit/audit/checks/`

**Example Check**:
```python
from audit.base_check import AccessibilityCheck

class NewCheck(AccessibilityCheck):
    def check(self, soup):
        issues = []
        elements = soup.find_all('element-type')
        for elem in elements:
            if not self._meets_criteria(elem):
                issues.append(self._create_issue(
                    type='new_issue_type',
                    severity='serious',
                    wcag_criteria=['X.X.X'],
                    element=elem,
                    message='Issue description',
                    suggestion='How to fix'
                ))
        return issues
```

### Adding a New Remediation Strategy

1. Create strategy file in `pdf2html/content_accessibility_utility_on_aws/remediate/remediation_strategies/`
2. Implement remediation function
3. Register in `remediate/remediation_strategies/__init__.py`
4. Map issue type to strategy in `remediate/remediation_manager.py`
5. Add test

**Example Strategy**:
```python
def remediate_new_issue(html_updater, issue, bedrock_client=None):
    """Remediate new issue type."""
    element = html_updater.get_element_by_selector(issue.selector)
    
    if bedrock_client:
        # AI-powered fix
        fix = bedrock_client.generate_fix(element, issue)
        html_updater.update_element_content(issue.selector, fix)
    else:
        # Rule-based fix
        html_updater.update_element_attribute(issue.selector, 'attr', 'value')
    
    return RemediationFix(
        issue_id=issue.id,
        status=RemediationStatus.FIXED,
        method='ai_generated' if bedrock_client else 'rule_based',
        original_element=str(element),
        fixed_element=str(html_updater.get_element_by_selector(issue.selector))
    )
```

### Updating Dependencies

**Python**:
```bash
pip install --upgrade package-name
pip freeze > requirements.txt
```

**JavaScript**:
```bash
npm update package-name
npm audit fix
```

**Java**:
Update version in `pom.xml`, then:
```bash
mvn clean install
```

### Adding CloudWatch Metrics

1. Use `MetricsContext` in your code
2. Call appropriate tracking method
3. Metrics automatically published to `PDFAccessibility` namespace
4. Update dashboard in `cdk/usage_metrics_stack.py` if needed

---

## Troubleshooting

### Common Issues

**Issue**: Lambda timeout  
**Solution**: Increase timeout in CDK, optimize code, or split into smaller operations

**Issue**: ECS task fails to start  
**Solution**: Check VPC endpoints, verify ECR image exists, check IAM permissions

**Issue**: Adobe API errors  
**Solution**: Verify credentials in Secrets Manager, check API rate limits

**Issue**: Bedrock throttling  
**Solution**: Implement exponential backoff, reduce request rate, request quota increase

**Issue**: BDA timeout  
**Solution**: Increase polling timeout, process smaller page ranges

**Issue**: S3 access denied  
**Solution**: Verify IAM permissions, check bucket policy

### Debugging Tips

**Enable Debug Logging**:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

**Check CloudWatch Logs**:
```bash
aws logs tail /aws/lambda/function-name --follow
```

**Test IAM Permissions**:
```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::account:role/role-name \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::bucket/key
```

**Validate CDK**:
```bash
cdk synth --strict  # Strict validation
cdk doctor          # Check CDK environment
```

---

## Additional Resources

**Detailed Documentation**: See `.agents/summary/` directory:
- `index.md`: Knowledge base index
- `architecture.md`: System architecture
- `components.md`: Component details
- `interfaces.md`: API specifications
- `data_models.md`: Data structures
- `workflows.md`: Process flows
- `dependencies.md`: External dependencies

**External Documentation**:
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Adobe PDF Services API](https://developer.adobe.com/document-services/docs/)
- [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

**Support**:
- Email: ai-cic@amazon.com
- GitHub Issues: https://github.com/ASUCICREPO/PDF_Accessibility/issues

---

**Last Updated**: 2026-03-02  
**Maintained By**: Arizona State University's AI Cloud Innovation Center
