# PDF Accessibility Observability Enhancement - Summary

## What Was Delivered

### 1. Comprehensive Analysis (`docs/OBSERVABILITY_ANALYSIS.md`)
- **Current State Assessment**: Detailed analysis of existing logging and monitoring
- **Gap Identification**: Critical gaps in metrics, cost tracking, and user attribution
- **Metric Schema Design**: Complete metric namespace and dimension structure
- **Cost Calculation Formulas**: Precise formulas for both PDF-to-PDF and PDF-to-HTML
- **Implementation Roadmap**: Phased approach for rolling out enhancements

### 2. Usage Metrics Dashboard (`cdk/usage_metrics_stack.py`)
A comprehensive CloudWatch dashboard that tracks:

#### Overview Metrics
- Pages processed (hourly/daily)
- Files processed (hourly/daily)

#### Service-Specific Metrics
- **Bedrock**: Invocations, input tokens, output tokens (by model)
- **Adobe API**: API calls by operation type (PDF-to-PDF only)

#### Performance Metrics
- Lambda processing duration
- ECS task CPU utilization (PDF-to-PDF only)
- Processing time by stage

#### Error Tracking
- Lambda errors
- Step Function failed executions
- Error breakdown by type and stage

#### Cost Estimation
- Total estimated cost (24h)
- Cost per file (average)
- Cost per page (average)

#### User Usage (with tagging)
- Files processed by user
- Pages processed by user
- Cost per user

### 3. Metrics Helper Library (`lambda/shared/metrics_helper.py`)
Reusable Python utilities for emitting CloudWatch metrics:

#### Core Functions
- `emit_metric()` - Generic metric emission
- `track_pages_processed()` - Page count tracking
- `track_adobe_api_call()` - Adobe API usage
- `track_bedrock_invocation()` - Bedrock model usage with tokens
- `track_processing_duration()` - Stage timing
- `track_error()` - Error tracking
- `track_file_size()` - File size metrics
- `estimate_cost()` - Comprehensive cost calculation

#### Context Manager
- `MetricsContext` - Automatic duration and error tracking

### 4. Integration Guide (`docs/METRICS_INTEGRATION_GUIDE.md`)
Step-by-step instructions for:
- Updating existing Lambda functions
- Adding metrics to ECS tasks
- Implementing user attribution via S3 tags
- Deploying Lambda layers
- Validating metrics collection
- Setting up cost aggregation

## Key Features

### 1. Per-User Usage Tracking
- S3 object tagging for user attribution
- User dimension on all metrics
- User-specific cost calculation
- User usage reports in dashboard

### 2. Comprehensive Cost Tracking
Tracks costs for:
- Adobe PDF Services API calls
- Bedrock model invocations (by token usage)
- Lambda execution time
- ECS Fargate tasks
- Bedrock Data Automation (PDF-to-HTML)
- S3 storage and requests
- Step Functions state transitions

### 3. Real-Time Metrics
- Custom CloudWatch metrics (not just logs)
- Sub-minute granularity
- Immediate visibility into usage
- Alerting capability

### 4. Multi-Dimensional Analysis
Metrics can be sliced by:
- Service (pdf2pdf vs pdf2html)
- User ID
- File name
- Processing stage
- Bedrock model
- Adobe operation type
- Error type

## Current State vs Enhanced State

### Before
❌ Only log-based queries (slow)
❌ No custom metrics
❌ No cost tracking
❌ No user attribution
❌ Limited Bedrock visibility
❌ No Adobe API metrics
❌ No per-file cost calculation

### After
✅ Real-time CloudWatch metrics
✅ Custom metric namespace
✅ Comprehensive cost estimation
✅ Per-user usage tracking
✅ Bedrock token-level tracking
✅ Adobe API call counting
✅ Per-file and per-page cost breakdown
✅ Error tracking by type
✅ Performance monitoring by stage

## Implementation Status

### ✅ Completed
- Observability analysis document
- Usage metrics dashboard CDK stack
- Metrics helper library
- Integration guide
- Cost calculation formulas
- User attribution design

### 🔄 Requires Implementation
- Lambda function updates (add metrics calls)
- ECS task updates (add metrics calls)
- Lambda layer deployment
- S3 tagging implementation
- Frontend user context passing
- Cost aggregation Lambda (optional)

## Quick Start

### 1. Deploy Dashboard (Standalone)
```bash
cd /mnt/c/code/PDF_Accessibility
cdk deploy PDFAccessibilityUsageMetrics
```

### 2. Deploy with Metrics Integration
```python
# Update app.py
from cdk.usage_metrics_stack import UsageMetricsDashboard

app = cdk.App()
pdf_stack = PDFAccessibility(app, "PDFAccessibility")
UsageMetricsDashboard(app, "PDFAccessibilityUsageMetrics",
    pdf2pdf_bucket=pdf_stack.bucket.bucket_name)
app.synth()
```

### 3. Add Metrics to Lambda
```python
# In any Lambda function
from metrics_helper import track_pages_processed, MetricsContext

def lambda_handler(event, context):
    user_id = get_user_from_s3_tags(bucket, key)
    
    with MetricsContext("processing", user_id, file_name):
        # Your processing code
        track_pages_processed(page_count, user_id, file_name)
```

## Cost Estimation Accuracy

### Pricing Sources (as of 2024)
- **Adobe PDF Services**: ~$0.05 per operation
- **Bedrock Claude Haiku**: $0.00025/1K input, $0.00125/1K output
- **Bedrock Claude Sonnet**: $0.003/1K input, $0.015/1K output
- **Lambda**: $0.0000166667/GB-second
- **ECS Fargate**: $0.04048/vCPU-hour + $0.004445/GB-hour
- **Bedrock Data Automation**: ~$0.01/page
- **Step Functions**: $0.000025/state transition

### Accuracy Notes
- Estimates are based on current AWS pricing
- Does not include S3 storage costs (minimal)
- Does not include data transfer costs
- Actual costs may vary by region
- Check AWS Cost Explorer for precise billing

## Dashboard Access

After deployment:
```
https://console.aws.amazon.com/cloudwatch/home?region=<region>#dashboards:name=PDF-Accessibility-Usage-Metrics
```

## Metrics Namespace

All custom metrics are under: `PDFAccessibility`

### Available Metrics
- `PagesProcessed` (Count)
- `AdobeAPICalls` (Count)
- `BedrockInvocations` (Count)
- `BedrockInputTokens` (Count)
- `BedrockOutputTokens` (Count)
- `ProcessingDuration` (Milliseconds)
- `ErrorCount` (Count)
- `FileSize` (Bytes)
- `EstimatedCost` (USD)

## Next Steps

1. **Review** the observability analysis document
2. **Deploy** the usage metrics dashboard
3. **Implement** metrics in Lambda functions (see integration guide)
4. **Add** user tagging to S3 uploads
5. **Validate** metrics are being collected
6. **Monitor** usage and costs
7. **Set up** CloudWatch alarms for anomalies
8. **Create** user usage reports

## Benefits

### For Operations
- Real-time visibility into platform usage
- Proactive error detection
- Performance monitoring
- Capacity planning data

### For Finance
- Per-user cost attribution
- Cost optimization opportunities
- Budget forecasting
- Chargeback/showback capability

### For Users
- Transparency into processing costs
- Usage insights
- Performance expectations

## Support

For questions or issues:
- See `docs/OBSERVABILITY_ANALYSIS.md` for detailed analysis
- See `docs/METRICS_INTEGRATION_GUIDE.md` for implementation steps
- Contact: ai-cic@amazon.com
