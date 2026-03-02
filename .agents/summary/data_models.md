# Data Models and Structures

## Core Data Models

### 1. Audit Models

#### AuditReport
**Location**: `pdf2html/content_accessibility_utility_on_aws/utils/report_models.py`

```python
@dataclass
class AuditReport(BaseReport):
    summary: AuditSummary
    issues: List[AuditIssue]
    wcag_summary: Dict[str, Dict[str, Any]]
    config: Config
```

**Fields**:
- `summary`: High-level statistics
- `issues`: List of accessibility issues found
- `wcag_summary`: Issues grouped by WCAG criteria
- `config`: Audit configuration used

---

#### AuditSummary
```python
@dataclass
class AuditSummary(BaseSummary):
    total_issues: int
    by_severity: Dict[Severity, int]
    by_wcag_level: Dict[str, int]
    pages_audited: int
    elements_checked: int
```

**Severity Levels**:
- `CRITICAL`: Blocks accessibility (e.g., missing alt text)
- `SERIOUS`: Major barrier (e.g., skipped heading levels)
- `MODERATE`: Significant issue (e.g., generic link text)
- `MINOR`: Minor improvement (e.g., missing lang attribute)

---

#### AuditIssue
```python
@dataclass
class AuditIssue(BaseIssue):
    id: str
    type: str
    severity: Severity
    wcag_criteria: List[str]
    element: str
    selector: str
    location: Location
    message: str
    suggestion: str
    context: Optional[str]
    status: IssueStatus
```

**Issue Types**:
- `missing_alt_text`
- `empty_alt_text`
- `generic_alt_text`
- `long_alt_text`
- `missing_h1`
- `skipped_heading_level`
- `empty_heading_content`
- `table_missing_headers`
- `table_missing_caption`
- `table_missing_scope`
- `form_missing_label`
- `form_missing_fieldset`
- `empty_link_text`
- `generic_link_text`
- `url_as_link_text`
- `missing_main_landmark`
- `missing_document_language`
- `insufficient_color_contrast`

---

#### Location
```python
@dataclass
class Location:
    page: int
    line: Optional[int]
    column: Optional[int]
    xpath: Optional[str]
```

---

### 2. Remediation Models

#### RemediationReport
```python
@dataclass
class RemediationReport(BaseReport):
    summary: RemediationSummary
    fixes: List[RemediationFix]
    manual_review_items: List[ManualReviewItem]
    config: Config
```

---

#### RemediationSummary
```python
@dataclass
class RemediationSummary(BaseSummary):
    total_issues: int
    fixed_automatically: int
    requires_manual_review: int
    failed: int
    by_method: Dict[str, int]  # ai_generated, rule_based, manual
```

---

#### RemediationFix
```python
@dataclass
class RemediationFix:
    issue_id: str
    issue_type: str
    status: RemediationStatus
    method: str
    original_element: str
    fixed_element: str
    details: RemediationDetails
    timestamp: datetime
```

**RemediationStatus**:
- `FIXED`: Successfully remediated
- `FAILED`: Remediation failed
- `MANUAL_REVIEW`: Requires human review
- `SKIPPED`: Intentionally skipped

---

#### RemediationDetails
```python
@dataclass
class RemediationDetails:
    ai_prompt: Optional[str]
    ai_response: Optional[str]
    ai_model: Optional[str]
    tokens_used: Optional[int]
    confidence: Optional[float]
    fallback_used: bool
    error_message: Optional[str]
```

---

#### ManualReviewItem
```python
@dataclass
class ManualReviewItem:
    issue_id: str
    issue_type: str
    reason: str
    element: str
    selector: str
    suggestion: str
    priority: str  # high, medium, low
```

---

### 3. Configuration Models

#### Config
```python
@dataclass
class Config:
    wcag_level: str = "AA"  # AA or AAA
    include_warnings: bool = True
    check_color_contrast: bool = True
    auto_remediate: bool = True
    use_ai: bool = True
    bedrock_model: str = "amazon.nova-pro-v1:0"
    max_retries: int = 3
    timeout_seconds: int = 300
    output_formats: List[str] = field(default_factory=lambda: ["html", "json"])
```

---

### 4. Usage Tracking Models

#### UsageData
**Location**: `pdf2html/content_accessibility_utility_on_aws/utils/usage_tracker.py`

```python
{
    "session_id": "uuid",
    "user_id": "user123",
    "solution": "PDF2HTML",
    "timestamp": "2026-03-02T15:00:00Z",
    "pdf_info": {
        "filename": "document.pdf",
        "size_bytes": 1024000,
        "pages": 10
    },
    "bedrock_usage": {
        "invocations": 15,
        "input_tokens": 5000,
        "output_tokens": 2000,
        "models_used": ["amazon.nova-pro-v1:0"]
    },
    "bda_usage": {
        "pages_processed": 10,
        "processing_time_seconds": 45
    },
    "processing_metrics": {
        "total_duration_seconds": 120,
        "conversion_time": 45,
        "audit_time": 20,
        "remediation_time": 55
    },
    "cost_estimates": {
        "bedrock": 0.0224,
        "bda": 0.50,
        "lambda": 0.0015,
        "s3": 0.0001,
        "total": 0.524
    }
}
```

---

### 5. BDA Models

#### BDAElement
**Location**: `pdf2html/content_accessibility_utility_on_aws/remediate/bda_integration/element_parser.py`

```python
{
    "id": "element-001",
    "type": "text" | "image" | "table" | "heading",
    "page": 1,
    "content": "Element content",
    "bounding_box": {
        "x": 100,
        "y": 200,
        "width": 300,
        "height": 50
    },
    "confidence": 0.95,
    "attributes": {
        "font_size": 12,
        "font_family": "Arial",
        "color": "#000000"
    },
    "children": []  # Nested elements
}
```

---

#### BDAPage
```python
{
    "page_number": 1,
    "width": 612,
    "height": 792,
    "elements": [BDAElement],
    "images": [
        {
            "id": "img-001",
            "s3_path": "s3://bucket/images/img-001.png",
            "bounding_box": {...},
            "alt_text": None
        }
    ]
}
```

---

### 6. Metrics Models

#### MetricData
**Location**: `lambda/shared/metrics_helper.py`

```python
{
    "namespace": "PDFAccessibility",
    "metric_name": "PagesProcessed",
    "value": 10,
    "unit": "Count",
    "timestamp": "2026-03-02T15:00:00Z",
    "dimensions": [
        {"name": "Solution", "value": "PDF2PDF"},
        {"name": "UserId", "value": "user123"},
        {"name": "Operation", "value": "adobe_autotag"}
    ]
}
```

---

### 7. Step Functions State

#### ChunkProcessingState
```python
{
    "chunk_id": "chunk-001",
    "s3_key": "temp/document_page_1.pdf",
    "page_number": 1,
    "status": "processing" | "completed" | "failed",
    "adobe_output": "temp/document_page_1_tagged.pdf",
    "alttext_output": "temp/document_page_1_final.pdf",
    "errors": []
}
```

---

#### WorkflowState
```python
{
    "execution_id": "exec-uuid",
    "original_file": "pdf/document.pdf",
    "user_id": "user123",
    "chunks": [ChunkProcessingState],
    "pre_check_results": {...},
    "post_check_results": {...},
    "final_output": "result/COMPLIANT_document.pdf",
    "metrics": {
        "total_pages": 10,
        "processing_time": 120,
        "adobe_calls": 10,
        "bedrock_calls": 50
    }
}
```

---

## WCAG Criteria Mapping

### WCAG 2.1 Level AA Criteria

```python
WCAG_CRITERIA = {
    "1.1.1": {
        "name": "Non-text Content",
        "level": "A",
        "description": "All non-text content has text alternative",
        "issue_types": ["missing_alt_text", "empty_alt_text"]
    },
    "1.3.1": {
        "name": "Info and Relationships",
        "level": "A",
        "description": "Information, structure, and relationships can be programmatically determined",
        "issue_types": ["table_missing_headers", "form_missing_label", "missing_headings"]
    },
    "1.3.2": {
        "name": "Meaningful Sequence",
        "level": "A",
        "description": "Correct reading sequence can be programmatically determined",
        "issue_types": ["skipped_heading_level"]
    },
    "1.4.3": {
        "name": "Contrast (Minimum)",
        "level": "AA",
        "description": "Text has contrast ratio of at least 4.5:1",
        "issue_types": ["insufficient_color_contrast"]
    },
    "2.4.1": {
        "name": "Bypass Blocks",
        "level": "A",
        "description": "Mechanism to bypass blocks of repeated content",
        "issue_types": ["missing_skip_link"]
    },
    "2.4.2": {
        "name": "Page Titled",
        "level": "A",
        "description": "Web pages have titles that describe topic or purpose",
        "issue_types": ["missing_document_title"]
    },
    "2.4.4": {
        "name": "Link Purpose (In Context)",
        "level": "A",
        "description": "Purpose of each link can be determined from link text",
        "issue_types": ["empty_link_text", "generic_link_text", "url_as_link_text"]
    },
    "2.4.6": {
        "name": "Headings and Labels",
        "level": "AA",
        "description": "Headings and labels describe topic or purpose",
        "issue_types": ["empty_heading_content", "generic_heading_text"]
    },
    "3.1.1": {
        "name": "Language of Page",
        "level": "A",
        "description": "Default human language can be programmatically determined",
        "issue_types": ["missing_document_language"]
    },
    "4.1.2": {
        "name": "Name, Role, Value",
        "level": "A",
        "description": "Name and role can be programmatically determined",
        "issue_types": ["missing_aria_labels", "invalid_aria_attributes"]
    }
}
```

---

## File Formats

### 1. Audit Report JSON
```json
{
    "version": "1.0",
    "timestamp": "2026-03-02T15:00:00Z",
    "html_file": "document.html",
    "summary": {
        "total_issues": 42,
        "by_severity": {
            "critical": 5,
            "serious": 15,
            "moderate": 18,
            "minor": 4
        },
        "by_wcag_level": {
            "A": 25,
            "AA": 17
        },
        "pages_audited": 10,
        "elements_checked": 523
    },
    "issues": [
        {
            "id": "img-001",
            "type": "missing_alt_text",
            "severity": "critical",
            "wcag_criteria": ["1.1.1"],
            "element": "<img src='image.png' />",
            "selector": "body > div.content > img:nth-child(3)",
            "location": {
                "page": 1,
                "line": 45,
                "column": 12
            },
            "message": "Image is missing alt attribute",
            "suggestion": "Add descriptive alt text that conveys the purpose of the image",
            "context": "Surrounding text: Lorem ipsum...",
            "status": "open"
        }
    ],
    "wcag_summary": {
        "1.1.1": {
            "count": 5,
            "description": "Non-text Content",
            "level": "A"
        }
    },
    "config": {
        "wcag_level": "AA",
        "include_warnings": true,
        "check_color_contrast": true
    }
}
```

---

### 2. Remediation Report JSON
```json
{
    "version": "1.0",
    "timestamp": "2026-03-02T15:00:00Z",
    "html_file": "document_remediated.html",
    "summary": {
        "total_issues": 42,
        "fixed_automatically": 35,
        "requires_manual_review": 7,
        "failed": 0,
        "by_method": {
            "ai_generated": 20,
            "rule_based": 15,
            "manual": 0
        }
    },
    "fixes": [
        {
            "issue_id": "img-001",
            "issue_type": "missing_alt_text",
            "status": "fixed",
            "method": "ai_generated",
            "original_element": "<img src='image.png' />",
            "fixed_element": "<img src='image.png' alt='A graph showing sales trends over time' />",
            "details": {
                "ai_prompt": "Generate alt text for this image...",
                "ai_response": "A graph showing sales trends over time",
                "ai_model": "amazon.nova-pro-v1:0",
                "tokens_used": 150,
                "confidence": 0.92,
                "fallback_used": false
            },
            "timestamp": "2026-03-02T15:01:23Z"
        }
    ],
    "manual_review_items": [
        {
            "issue_id": "table-005",
            "issue_type": "table_irregular_headers",
            "reason": "Complex table structure with merged cells",
            "element": "<table>...</table>",
            "selector": "body > table:nth-child(5)",
            "suggestion": "Manually verify header associations and add scope attributes",
            "priority": "high"
        }
    ]
}
```

---

### 3. Usage Data JSON
```json
{
    "session_id": "550e8400-e29b-41d4-a716-446655440000",
    "user_id": "user123",
    "solution": "PDF2HTML",
    "timestamp": "2026-03-02T15:00:00Z",
    "pdf_info": {
        "filename": "document.pdf",
        "size_bytes": 1024000,
        "pages": 10
    },
    "bedrock_usage": {
        "invocations": 15,
        "input_tokens": 5000,
        "output_tokens": 2000,
        "models_used": ["amazon.nova-pro-v1:0"]
    },
    "bda_usage": {
        "pages_processed": 10,
        "processing_time_seconds": 45
    },
    "processing_metrics": {
        "total_duration_seconds": 120,
        "conversion_time": 45,
        "audit_time": 20,
        "remediation_time": 55
    },
    "cost_estimates": {
        "bedrock": 0.0224,
        "bda": 0.50,
        "lambda": 0.0015,
        "s3": 0.0001,
        "total": 0.524
    }
}
```

---

## Database Schemas

### Image Metadata SQLite (Adobe Container)

**Table**: `image_metadata`

```sql
CREATE TABLE image_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    image_path TEXT NOT NULL,
    page_number INTEGER,
    bounding_box TEXT,  -- JSON string
    alt_text TEXT,
    is_decorative BOOLEAN DEFAULT 0,
    context TEXT,
    confidence REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Usage**: Stores extracted image information from Adobe Extract API for alt text generation.

---

## Enumerations

### Severity
```python
class Severity(Enum):
    CRITICAL = "critical"
    SERIOUS = "serious"
    MODERATE = "moderate"
    MINOR = "minor"
```

### IssueStatus
```python
class IssueStatus(Enum):
    OPEN = "open"
    FIXED = "fixed"
    MANUAL_REVIEW = "manual_review"
    SKIPPED = "skipped"
```

### RemediationStatus
```python
class RemediationStatus(Enum):
    FIXED = "fixed"
    FAILED = "failed"
    MANUAL_REVIEW = "manual_review"
    SKIPPED = "skipped"
```

### RemediationMethod
```python
class RemediationMethod(Enum):
    AI_GENERATED = "ai_generated"
    RULE_BASED = "rule_based"
    MANUAL = "manual"
```
