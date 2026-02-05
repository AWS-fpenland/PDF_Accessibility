# PDF Accessibility Observability - Quick Reference

## 📊 Dashboard Widgets

| Widget | Metric | Purpose |
|--------|--------|---------|
| Pages Processed | `PDFAccessibility/PagesProcessed` | Total pages remediated |
| Files Processed | `AWS/Lambda/Invocations` | Total files processed |
| Bedrock Invocations | `AWS/Bedrock/Invocations` | Model API calls |
| Bedrock Tokens | `AWS/Bedrock/InputTokens`, `OutputTokens` | Token usage by model |
| Adobe API Calls | `PDFAccessibility/AdobeAPICalls` | Adobe service usage |
| Processing Duration | `PDFAccessibility/ProcessingDuration` | Performance by stage |
| Errors | `PDFAccessibility/ErrorCount` | Error tracking |
| Estimated Cost | `PDFAccessibility/EstimatedCost` | Cost per file/user |

## 🔧 Metrics Helper Functions

```python
from metrics_helper import *

# Track pages
track_pages_processed(page_count, user_id, file_name, "pdf2pdf")

# Track Adobe API
track_adobe_api_call("AutoTag", user_id, file_name)

# Track Bedrock
track_bedrock_invocation(model_id, input_tokens, output_tokens, user_id, file_name)

# Track duration with context manager
with MetricsContext("processing", user_id, file_name):
    # Your code here - duration tracked automatically
    process_file()

# Estimate cost
cost = estimate_cost(
    pages=100,
    adobe_calls=2,
    bedrock_input_tokens=5000,
    bedrock_output_tokens=2000,
    lambda_duration_ms=30000,
    user_id=user_id,
    file_name=file_name
)
```

## 💰 Cost Formulas

### PDF-to-PDF
```
Cost = (Adobe × $0.05) 
     + (Bedrock Input Tokens / 1000 × $0.00025)
     + (Bedrock Output Tokens / 1000 × $0.00125)
     + (Lambda GB-sec × $0.0000166667)
     + (ECS vCPU-hr × $0.04048 + GB-hr × $0.004445)
```

### PDF-to-HTML
```
Cost = (Pages × $0.01)
     + (Bedrock Input Tokens / 1000 × $0.00025)
     + (Bedrock Output Tokens / 1000 × $0.00125)
     + (Lambda GB-sec × $0.0000166667)
```

## 🏷️ User Attribution

### Set User Tag on Upload
```python
s3_client.upload_file(
    file_path, bucket, key,
    ExtraArgs={'Tagging': f'UserId={user_id}'}
)
```

### Get User from Tags
```python
def get_user_from_s3_tags(bucket: str, key: str) -> str:
    response = s3_client.get_object_tagging(Bucket=bucket, Key=key)
    for tag in response.get('TagSet', []):
        if tag['Key'] == 'UserId':
            return tag['Value']
    return None
```

## 📈 Metric Dimensions

| Dimension | Values | Usage |
|-----------|--------|-------|
| Service | `pdf2pdf`, `pdf2html` | Separate solutions |
| UserId | User identifier | Per-user tracking |
| FileName | File name | Per-file tracking |
| Stage | `split`, `extract`, `remediate`, `merge` | Performance analysis |
| Model | Bedrock model ID | Model-specific costs |
| Operation | `AutoTag`, `ExtractPDF` | Adobe API breakdown |
| ErrorType | Exception class name | Error categorization |

## 🚀 Deployment Commands

### Deploy Dashboard Only
```bash
cdk deploy PDFAccessibilityUsageMetrics
```

### Deploy with Main Stack
```python
# In app.py
from cdk.usage_metrics_stack import UsageMetricsDashboard

app = cdk.App()
pdf_stack = PDFAccessibility(app, "PDFAccessibility")
UsageMetricsDashboard(app, "PDFAccessibilityUsageMetrics",
    pdf2pdf_bucket=pdf_stack.bucket.bucket_name)
app.synth()
```

### Create Metrics Lambda Layer
```bash
mkdir -p lambda-layer/python
cp lambda/shared/metrics_helper.py lambda-layer/python/
cd lambda-layer && zip -r metrics-layer.zip python/

aws lambda publish-layer-version \
    --layer-name pdf-accessibility-metrics \
    --zip-file fileb://metrics-layer.zip \
    --compatible-runtimes python3.12
```

## 🔍 Query Metrics

### CLI
```bash
# List metrics
aws cloudwatch list-metrics --namespace PDFAccessibility

# Get metric data
aws cloudwatch get-metric-statistics \
    --namespace PDFAccessibility \
    --metric-name PagesProcessed \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

### Python
```python
import boto3
cloudwatch = boto3.client('cloudwatch')

response = cloudwatch.get_metric_statistics(
    Namespace='PDFAccessibility',
    MetricName='PagesProcessed',
    Dimensions=[{'Name': 'UserId', 'Value': 'user123'}],
    StartTime=start_time,
    EndTime=end_time,
    Period=3600,
    Statistics=['Sum']
)
```

## 📋 Integration Checklist

- [ ] Deploy usage metrics dashboard
- [ ] Create metrics Lambda layer
- [ ] Update Lambda functions with metrics calls
- [ ] Update ECS tasks with metrics calls
- [ ] Implement S3 user tagging
- [ ] Update frontend to pass user context
- [ ] Validate metrics in CloudWatch
- [ ] Set up cost alerts
- [ ] Create user usage reports
- [ ] Document for end users

## 🎯 Key Metrics to Monitor

### Daily
- Total pages processed
- Total files processed
- Error rate
- Average processing time
- Estimated daily cost

### Weekly
- Cost per user
- Pages per user
- Top error types
- Performance trends
- Bedrock token usage

### Monthly
- Total platform cost
- Cost per page trend
- User growth
- Service utilization
- Capacity planning

## 🚨 Recommended Alarms

```python
# High error rate
cloudwatch.Alarm(
    metric=error_metric,
    threshold=10,
    evaluation_periods=1,
    comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
)

# High cost
cloudwatch.Alarm(
    metric=cost_metric,
    threshold=100,  # $100/day
    evaluation_periods=1,
    comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
)

# Long processing time
cloudwatch.Alarm(
    metric=duration_metric,
    threshold=300000,  # 5 minutes
    evaluation_periods=2,
    comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
)
```

## 📚 Documentation

- **Analysis**: `docs/OBSERVABILITY_ANALYSIS.md`
- **Integration**: `docs/METRICS_INTEGRATION_GUIDE.md`
- **Summary**: `docs/OBSERVABILITY_SUMMARY.md`
- **This Guide**: `docs/OBSERVABILITY_QUICK_REFERENCE.md`

## 🆘 Troubleshooting

### Metrics Not Appearing
1. Check IAM permissions for `cloudwatch:PutMetricData`
2. Verify namespace is `PDFAccessibility`
3. Check CloudWatch Logs for errors
4. Validate metric dimensions are strings

### Cost Estimates Inaccurate
1. Update pricing in `metrics_helper.py`
2. Verify token counts are correct
3. Check regional pricing differences
4. Compare with AWS Cost Explorer

### User Attribution Missing
1. Verify S3 object tags are set
2. Check tag propagation through Step Functions
3. Validate `get_user_from_s3_tags()` implementation
4. Ensure frontend passes user context

## 💡 Pro Tips

1. **Use MetricsContext** for automatic duration and error tracking
2. **Batch metrics** when possible to reduce API calls
3. **Add user_id early** in the processing pipeline
4. **Monitor token usage** to optimize Bedrock costs
5. **Set up alarms** for cost anomalies
6. **Review dashboard weekly** for trends
7. **Export metrics** to S3 for long-term analysis
8. **Use dimensions** for flexible querying
