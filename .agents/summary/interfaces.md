# Interfaces and APIs

## External APIs

### 1. Adobe PDF Services API

**Purpose**: PDF structure tagging and content extraction

**Authentication**: OAuth 2.0 with client credentials

**Credentials Storage**: AWS Secrets Manager (`adobe-pdf-services-credentials`)

**Operations Used**:

#### Autotag API
- **Endpoint**: Adobe PDF Services REST API
- **Method**: POST
- **Function**: Adds accessibility tags to PDF
- **Input**: PDF file
- **Output**: Tagged PDF with structure tree
- **Tags Added**: 
  - Headings (H1-H6)
  - Paragraphs (P)
  - Lists (L, LI)
  - Tables (Table, TR, TH, TD)
  - Figures (Figure)
  - Links (Link)

**Options**:
```python
{
    "generate_report": True,
    "shift_headings": False
}
```

#### Extract API
- **Endpoint**: Adobe PDF Services REST API
- **Method**: POST
- **Function**: Extracts content and structure
- **Input**: PDF file
- **Output**: ZIP file containing:
  - `structuredData.json`: Document structure
  - `images/`: Extracted images
  - Excel file with image metadata

**Rate Limits**: Enterprise contract dependent

**Error Handling**:
- Exponential backoff retry
- CloudWatch error logging
- Fallback to basic processing

---

### 2. AWS Bedrock API

**Purpose**: AI-powered content generation and image analysis

**Authentication**: IAM role-based

**Models Used**:

#### Amazon Nova Pro
- **Model ID**: `amazon.nova-pro-v1:0`
- **Capabilities**: 
  - Text generation
  - Image analysis (multimodal)
  - Context understanding
- **Use Cases**:
  - Alt text generation
  - Title generation
  - Remediation suggestions
  - Table caption generation

**API Operations**:

#### InvokeModel
```python
{
    "modelId": "amazon.nova-pro-v1:0",
    "contentType": "application/json",
    "accept": "application/json",
    "body": {
        "messages": [
            {
                "role": "user",
                "content": [
                    {"text": "prompt"},
                    {"image": {"source": {"bytes": image_bytes}}}
                ]
            }
        ],
        "inferenceConfig": {
            "max_new_tokens": 512,
            "temperature": 0.7
        }
    }
}
```

**Response**:
```json
{
    "output": {
        "message": {
            "content": [{"text": "generated text"}]
        }
    },
    "usage": {
        "inputTokens": 100,
        "outputTokens": 50
    }
}
```

**Pricing**:
- Input: $0.0008 per 1K tokens
- Output: $0.0032 per 1K tokens

**Rate Limits**: 
- Requests per minute: Model-dependent
- Tokens per minute: Model-dependent

---

### 3. AWS Bedrock Data Automation API

**Purpose**: PDF parsing and structure extraction

**Authentication**: IAM role-based

**Operations**:

#### CreateDataAutomationProject
```python
{
    "projectName": "pdf-accessibility-project",
    "projectStage": "LIVE"
}
```

#### InvokeDataAutomationAsync
```python
{
    "projectArn": "arn:aws:bedrock:region:account:data-automation-project/name",
    "inputConfiguration": {
        "s3Uri": "s3://bucket/input.pdf"
    },
    "outputConfiguration": {
        "s3Uri": "s3://bucket/output/"
    }
}
```

**Output Structure**:
```json
{
    "pages": [
        {
            "pageNumber": 1,
            "elements": [
                {
                    "type": "text",
                    "content": "...",
                    "boundingBox": {...},
                    "confidence": 0.95
                },
                {
                    "type": "image",
                    "s3Path": "s3://...",
                    "boundingBox": {...}
                }
            ]
        }
    ]
}
```

**Capabilities**:
- Text extraction with layout
- Image extraction
- Table detection
- Element positioning
- Confidence scores

---

## Internal APIs

### 4. Content Accessibility Utility API

**Location**: `pdf2html/content_accessibility_utility_on_aws/api.py`

**Purpose**: Main entry point for PDF accessibility processing

#### process_pdf_accessibility()
```python
def process_pdf_accessibility(
    pdf_path: str,
    output_dir: str,
    config: Optional[Dict] = None
) -> Dict[str, Any]
```

**Parameters**:
- `pdf_path`: Path to input PDF
- `output_dir`: Directory for outputs
- `config`: Configuration options

**Returns**:
```python
{
    "html_path": "path/to/remediated.html",
    "report_path": "path/to/report.html",
    "audit_results": {...},
    "remediation_results": {...},
    "usage_data": {...}
}
```

**Process Flow**:
1. Convert PDF to HTML
2. Audit HTML for accessibility
3. Remediate issues
4. Generate reports
5. Package outputs

---

#### convert_pdf_to_html()
```python
def convert_pdf_to_html(
    pdf_path: str,
    output_dir: str,
    bda_project_arn: Optional[str] = None
) -> str
```

**Purpose**: Converts PDF to HTML using BDA

**Returns**: Path to generated HTML file

---

#### audit_html_accessibility()
```python
def audit_html_accessibility(
    html_path: str,
    output_dir: Optional[str] = None
) -> AuditReport
```

**Purpose**: Audits HTML for WCAG compliance

**Returns**: `AuditReport` object with issues

---

#### remediate_html_accessibility()
```python
def remediate_html_accessibility(
    html_path: str,
    audit_report: AuditReport,
    output_dir: str,
    config: Optional[Dict] = None
) -> RemediationReport
```

**Purpose**: Fixes accessibility issues

**Returns**: `RemediationReport` object with fixes applied

---

#### generate_remediation_report()
```python
def generate_remediation_report(
    audit_report: AuditReport,
    remediation_report: RemediationReport,
    output_path: str,
    format: str = "html"
) -> str
```

**Purpose**: Generates accessibility report

**Formats**: `html`, `json`, `csv`, `txt`

**Returns**: Path to generated report

---

### 5. Audit API

**Location**: `pdf2html/content_accessibility_utility_on_aws/audit/api.py`

#### audit_html_accessibility()
```python
def audit_html_accessibility(
    html_path: str,
    config: Optional[Dict] = None
) -> AuditReport
```

**Configuration Options**:
```python
{
    "wcag_level": "AA",  # AA or AAA
    "include_warnings": True,
    "check_color_contrast": True,
    "context_lines": 3
}
```

**AuditReport Structure**:
```python
{
    "summary": {
        "total_issues": 42,
        "critical": 5,
        "serious": 15,
        "moderate": 18,
        "minor": 4
    },
    "issues": [
        {
            "id": "img-001",
            "type": "missing_alt_text",
            "severity": "critical",
            "wcag_criteria": ["1.1.1"],
            "element": "<img src='...' />",
            "selector": "body > div > img:nth-child(2)",
            "location": {"page": 1, "line": 45},
            "message": "Image missing alt attribute",
            "suggestion": "Add descriptive alt text"
        }
    ],
    "wcag_summary": {
        "1.1.1": {"count": 5, "description": "Non-text Content"},
        "1.3.1": {"count": 8, "description": "Info and Relationships"}
    }
}
```

---

### 6. Remediation API

**Location**: `pdf2html/content_accessibility_utility_on_aws/remediate/api.py`

#### remediate_html_accessibility()
```python
def remediate_html_accessibility(
    html_path: str,
    audit_report: AuditReport,
    output_path: str,
    config: Optional[Dict] = None
) -> RemediationReport
```

**Configuration Options**:
```python
{
    "auto_remediate": True,
    "use_ai": True,
    "bedrock_model": "amazon.nova-pro-v1:0",
    "max_retries": 3,
    "skip_manual_review": False
}
```

**RemediationReport Structure**:
```python
{
    "summary": {
        "total_issues": 42,
        "fixed_automatically": 35,
        "requires_manual_review": 7,
        "failed": 0
    },
    "fixes": [
        {
            "issue_id": "img-001",
            "status": "fixed",
            "method": "ai_generated",
            "original": "<img src='...' />",
            "fixed": "<img src='...' alt='Description' />",
            "ai_prompt": "...",
            "ai_response": "..."
        }
    ],
    "manual_review_items": [
        {
            "issue_id": "table-005",
            "reason": "Complex table structure",
            "suggestion": "Manually verify header associations"
        }
    ]
}
```

---

## AWS Service Interfaces

### 7. S3 Interface

**Operations Used**:

#### GetObject
```python
s3_client.get_object(
    Bucket='bucket-name',
    Key='path/to/file.pdf'
)
```

#### PutObject
```python
s3_client.put_object(
    Bucket='bucket-name',
    Key='path/to/output.pdf',
    Body=file_content,
    ServerSideEncryption='AES256',
    Metadata={'user-id': 'user123'}
)
```

#### PutObjectTagging
```python
s3_client.put_object_tagging(
    Bucket='bucket-name',
    Key='path/to/file.pdf',
    Tagging={
        'TagSet': [
            {'Key': 'user-id', 'Value': 'user123'},
            {'Key': 'upload-timestamp', 'Value': '2026-03-02T15:00:00Z'}
        ]
    }
)
```

---

### 8. CloudWatch Interface

**Metrics**:

#### PutMetricData
```python
cloudwatch_client.put_metric_data(
    Namespace='PDFAccessibility',
    MetricData=[
        {
            'MetricName': 'PagesProcessed',
            'Value': 10,
            'Unit': 'Count',
            'Timestamp': datetime.utcnow(),
            'Dimensions': [
                {'Name': 'Solution', 'Value': 'PDF2PDF'},
                {'Name': 'UserId', 'Value': 'user123'}
            ]
        }
    ]
)
```

**Logs**:

#### PutLogEvents
```python
logs_client.put_log_events(
    logGroupName='/aws/lambda/function-name',
    logStreamName='stream-name',
    logEvents=[
        {
            'timestamp': int(time.time() * 1000),
            'message': 'Processing PDF: file.pdf'
        }
    ]
)
```

---

### 9. Secrets Manager Interface

#### GetSecretValue
```python
secrets_client.get_secret_value(
    SecretId='adobe-pdf-services-credentials'
)
```

**Response**:
```json
{
    "SecretString": "{\"client_id\":\"...\",\"client_secret\":\"...\"}"
}
```

---

### 10. Step Functions Interface

#### StartExecution
```python
sfn_client.start_execution(
    stateMachineArn='arn:aws:states:...',
    input=json.dumps({
        'bucket': 'bucket-name',
        'key': 'path/to/file.pdf',
        'chunks': ['chunk1.pdf', 'chunk2.pdf']
    })
)
```

---

## Data Models

### AuditReport
```python
@dataclass
class AuditReport:
    summary: AuditSummary
    issues: List[AuditIssue]
    wcag_summary: Dict[str, WCAGCriterion]
    timestamp: datetime
    html_path: str
```

### AuditIssue
```python
@dataclass
class AuditIssue:
    id: str
    type: str
    severity: Severity  # CRITICAL, SERIOUS, MODERATE, MINOR
    wcag_criteria: List[str]
    element: str
    selector: str
    location: Location
    message: str
    suggestion: str
    context: Optional[str]
```

### RemediationReport
```python
@dataclass
class RemediationReport:
    summary: RemediationSummary
    fixes: List[RemediationFix]
    manual_review_items: List[ManualReviewItem]
    timestamp: datetime
    html_path: str
```

### RemediationFix
```python
@dataclass
class RemediationFix:
    issue_id: str
    status: RemediationStatus  # FIXED, FAILED, MANUAL_REVIEW
    method: str  # ai_generated, rule_based, manual
    original: str
    fixed: str
    ai_prompt: Optional[str]
    ai_response: Optional[str]
    error: Optional[str]
```

---

## Event Schemas

### S3 Event (Lambda Trigger)
```json
{
    "Records": [
        {
            "eventVersion": "2.1",
            "eventSource": "aws:s3",
            "eventName": "ObjectCreated:Put",
            "s3": {
                "bucket": {
                    "name": "bucket-name"
                },
                "object": {
                    "key": "pdf/document.pdf",
                    "size": 1024000
                }
            }
        }
    ]
}
```

### Step Functions Input
```json
{
    "bucket": "pdfaccessibility-bucket",
    "original_key": "pdf/document.pdf",
    "chunks": [
        "temp/document_page_1.pdf",
        "temp/document_page_2.pdf",
        "temp/document_page_3.pdf"
    ],
    "user_id": "user123",
    "timestamp": "2026-03-02T15:00:00Z"
}
```

### Step Functions Output
```json
{
    "status": "SUCCESS",
    "result_key": "result/COMPLIANT_document.pdf",
    "pages_processed": 3,
    "audit_results": {
        "pre_remediation": {...},
        "post_remediation": {...}
    },
    "metrics": {
        "adobe_api_calls": 3,
        "bedrock_invocations": 15,
        "processing_duration_seconds": 120
    }
}
```

---

## Error Responses

### Standard Error Format
```json
{
    "error": {
        "code": "ERROR_CODE",
        "message": "Human-readable error message",
        "details": {
            "file": "document.pdf",
            "operation": "adobe_autotag",
            "timestamp": "2026-03-02T15:00:00Z"
        },
        "retry_after": 60
    }
}
```

### Common Error Codes
- `INVALID_PDF`: PDF file is corrupted or invalid
- `ADOBE_API_ERROR`: Adobe API call failed
- `BEDROCK_THROTTLING`: Bedrock rate limit exceeded
- `BDA_TIMEOUT`: BDA processing timeout
- `INSUFFICIENT_PERMISSIONS`: IAM permissions issue
- `S3_ACCESS_DENIED`: S3 access error
- `PROCESSING_TIMEOUT`: Overall timeout exceeded
