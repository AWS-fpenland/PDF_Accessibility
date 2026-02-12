# Observability & Usage Metrics

This document describes the observability features added to the PDF Accessibility platform, including custom CloudWatch metrics, per-user usage tracking, cost estimation, and a dedicated monitoring dashboard.

## Overview

All metrics are published to the `PDFAccessibility` CloudWatch namespace. A dedicated dashboard (`PDF-Accessibility-Usage-Metrics`) provides real-time visibility into usage, costs, and performance across both the PDF-to-PDF and PDF-to-HTML solutions.

### Key Principles

- **Metrics over Log Insights** — CloudWatch metrics provide 15-month retention, real-time dashboards, and alarm support without parsing log formats.
- **Consistent dimensions** — All metrics use `Service` + `UserId` dimensions. `FileName` is intentionally excluded to avoid unbounded cardinality.
- **Graceful degradation** — Metrics emission failures are caught and logged without interrupting PDF processing.

## Metrics Reference

| Metric | Unit | Description |
|--------|------|-------------|
| `PagesProcessed` | Count | Number of PDF pages processed |
| `AdobeAPICalls` | Count | Adobe API invocations |
| `AdobeDocTransactions` | Count | Adobe Document Transactions (10/page for AutoTag, 1/5 pages for ExtractPDF) |
| `BedrockInvocations` | Count | Bedrock model calls |
| `BedrockInputTokens` | Count | Tokens sent to Bedrock |
| `BedrockOutputTokens` | Count | Tokens received from Bedrock |
| `ProcessingDuration` | Milliseconds | Processing time per stage |
| `ErrorCount` | Count | Errors by type and stage |
| `FileSize` | Bytes | Input file sizes |
| `EstimatedCost` | None | Estimated USD cost per job |

### Dimensions

| Dimension | Values | Used By |
|-----------|--------|---------|
| `Service` | `pdf2pdf`, `pdf2html` | All metrics |
| `UserId` | Cognito sub or `anonymous` | All metrics |
| `Stage` | `split`, `autotag`, `alt-text`, `merge`, `title`, `a11y-check` | ProcessingDuration, ErrorCount |
| `Operation` | `AutoTag`, `ExtractPDF` | AdobeAPICalls, AdobeDocTransactions |
| `Model` | Bedrock model ID | BedrockInvocations, token metrics |
| `ErrorType` | Exception class name | ErrorCount |

## Per-User Tracking

User attribution works through S3 object tagging:

1. **Cognito uploads** — The UI sets S3 metadata (`user-sub`, `user-groups`, `upload-timestamp`) on uploaded files.
2. **S3 Object Tagger Lambda** (`PDFAccessibility-S3ObjectTagger`) — Triggers on S3 `ObjectCreated` events in the `pdf/` prefix, reads the `user-sub` metadata, and applies a `UserId` S3 tag.
3. **Processing Lambdas/ECS** — Read the `UserId` tag from the S3 object and pass it as a dimension to all emitted metrics.
4. **Direct uploads** (no Cognito) — Default to `UserId: anonymous`.

## Cost Estimation

Approximate pricing (2024):

| Service | Rate |
|---------|------|
| Adobe API | $0.05 per operation |
| Bedrock Claude Haiku | $0.00025/1K input, $0.00125/1K output |
| Bedrock Claude Sonnet | $0.003/1K input, $0.015/1K output |
| Lambda | $0.0000166667/GB-sec |
| ECS Fargate | $0.04048/vCPU-hr + $0.004445/GB-hr |
| Bedrock Data Automation | $0.01 per page |

The `estimate_cost()` function in `metrics_helper.py` calculates and emits an `EstimatedCost` metric per job.

## Integration

### Metrics Helper Library

The shared library `lambda/shared/python/metrics_helper.py` provides:

- `emit_metric()` — Low-level CloudWatch PutMetricData wrapper
- `track_pages_processed()` — Page count tracking
- `track_adobe_api_call()` — Adobe API call and Document Transaction tracking
- `track_bedrock_invocation()` — Bedrock model invocation and token tracking
- `track_processing_duration()` — Stage timing
- `track_error()` — Error tracking by type and stage
- `track_file_size()` — Input file size tracking
- `estimate_cost()` — Cost estimation and metric emission
- `MetricsContext` — Context manager for automatic duration and error tracking

### Integrated Components

| Component | File | Metrics Tracked |
|-----------|------|-----------------|
| PDF Splitter Lambda | `lambda/pdf-splitter-lambda/main.py` | PagesProcessed, FileSize, ProcessingDuration, ErrorCount |
| Adobe AutoTag (ECS) | `adobe-autotag-container/autotag.py` | AdobeAPICalls, AdobeDocTransactions, BedrockInvocations |
| Alt Text Generator (ECS) | `alt-text-generator-container/alt-text.js` | BedrockInvocations, BedrockInputTokens, BedrockOutputTokens |
| PDF-to-HTML Lambda | `pdf2html/lambda_function.py` | PagesProcessed, ProcessingDuration, EstimatedCost |
| S3 Object Tagger | `lambda/s3_object_tagger/main.py` | User attribution via S3 tags |

### Lambda Layer Deployment

The metrics helper is deployed as a Lambda layer. The `deploy-local.sh` script handles copying `lambda/shared/python/metrics_helper.py` to the build contexts that need it.

## Dashboard

The `PDFAccessibilityUsageMetrics` CDK stack (`cdk/usage_metrics_stack.py`) creates a CloudWatch dashboard with:

- Total pages processed and documents by service
- Adobe API calls and Document Transactions
- Bedrock invocations and token usage
- Processing duration percentiles
- Error rates
- Estimated costs
- Per-user usage breakdown

### Deployment

The dashboard deploys automatically with the main stack:

```bash
cdk deploy --all
```

Or deploy just the dashboard:

```bash
cdk deploy PDFAccessibilityUsageMetrics
```

### Verification

```bash
# Check metrics are flowing
aws cloudwatch list-metrics --namespace PDFAccessibility

# Check dashboard exists
aws cloudwatch list-dashboards
```

## Recommended Alarms

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| High error rate | ErrorCount | > 5 per 5 minutes |
| Processing stalled | PagesProcessed | < 1 per hour (when expected) |
| Cost spike | EstimatedCost | > daily budget threshold |
