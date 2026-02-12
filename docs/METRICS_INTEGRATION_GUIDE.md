# Integrating Usage Metrics into PDF Accessibility Platform

## Overview
This guide shows how to integrate the new usage metrics tracking into existing Lambda functions and ECS tasks.

## Step 1: Update Lambda Functions

### Split PDF Lambda (lambda/pdf-splitter-lambda/main.py)

Add at the top:
```python
import sys
sys.path.append('/opt/python')  # Lambda layer path
from metrics_helper import track_pages_processed, track_file_size, MetricsContext
```

In `lambda_handler`, add:
```python
def lambda_handler(event, context):
    # Extract user_id from S3 object tags (if implemented)
    user_id = get_user_from_s3_tags(bucket_name, key)
    
    with MetricsContext("split", user_id, key, "pdf2pdf"):
        # Existing code...
        
        # After getting page count
        track_pages_processed(num_pages, user_id, key, "pdf2pdf")
        track_file_size(file_size, user_id, key, "pdf2pdf")
```

### Adobe Processing (adobe-autotag-container/autotag.py)

Add at the top:
```python
from metrics_helper import track_adobe_api_call, track_bedrock_invocation, MetricsContext
```

In Adobe API calls:
```python
def autotag_pdf(file_path, user_id, file_name):
    with MetricsContext("adobe_autotag", user_id, file_name, "pdf2pdf"):
        # Before Adobe API call
        track_adobe_api_call("AutoTag", user_id, file_name)
        
        # Existing Adobe API code...
        result = autotag_job.get_result()
        
        return result

def extract_pdf(file_path, user_id, file_name):
    with MetricsContext("adobe_extract", user_id, file_name, "pdf2pdf"):
        track_adobe_api_call("ExtractPDF", user_id, file_name)
        
        # Existing extraction code...
```

### Bedrock Invocations (alt-text-generator-container/alt-text.js)

Add tracking after Bedrock calls:
```javascript
// After Bedrock invocation
const response = await bedrockClient.send(command);

// Track metrics (call Python helper via subprocess or implement in JS)
await trackBedrockInvocation(
    modelId,
    response.usage.inputTokens,
    response.usage.outputTokens,
    userId,
    fileName
);
```

### PDF-to-HTML Lambda (pdf2html/lambda_function.py)

Add at the top:
```python
import sys
sys.path.append('/opt/python')
from metrics_helper import (
    track_pages_processed, 
    track_bedrock_invocation,
    estimate_cost,
    MetricsContext
)
```

In `lambda_handler`:
```python
def lambda_handler(event, context):
    user_id = get_user_from_s3_tags(bucket, key)
    
    with MetricsContext("pdf2html_processing", user_id, key, "pdf2html"):
        # After BDA processing
        page_count = get_page_count_from_bda_output(output_data)
        track_pages_processed(page_count, user_id, key, "pdf2html")
        
        # After Bedrock remediation calls
        for invocation in bedrock_invocations:
            track_bedrock_invocation(
                invocation['model_id'],
                invocation['input_tokens'],
                invocation['output_tokens'],
                user_id,
                key,
                "pdf2html"
            )
        
        # Estimate total cost
        total_cost = estimate_cost(
            pages=page_count,
            bedrock_input_tokens=total_input_tokens,
            bedrock_output_tokens=total_output_tokens,
            lambda_duration_ms=context.get_remaining_time_in_millis(),
            lambda_memory_mb=context.memory_limit_in_mb,
            user_id=user_id,
            file_name=key,
            service="pdf2html"
        )
```

## Step 2: User Attribution via S3 Tags

### Helper Function for S3 Tags
```python
def get_user_from_s3_tags(bucket: str, key: str) -> Optional[str]:
    """Extract user ID from S3 object tags."""
    try:
        response = s3_client.get_object_tagging(Bucket=bucket, Key=key)
        for tag in response.get('TagSet', []):
            if tag['Key'] == 'UserId':
                return tag['Value']
    except Exception as e:
        print(f"Failed to get user tags: {e}")
    return None

def set_user_tag(bucket: str, key: str, user_id: str):
    """Set user ID tag on S3 object."""
    try:
        s3_client.put_object_tagging(
            Bucket=bucket,
            Key=key,
            Tagging={'TagSet': [{'Key': 'UserId', 'Value': user_id}]}
        )
    except Exception as e:
        print(f"Failed to set user tag: {e}")
```

### Frontend Integration
When uploading files from the UI, add user context:
```python
# In upload handler
s3_client.upload_file(
    file_path,
    bucket,
    key,
    ExtraArgs={
        'Tagging': f'UserId={current_user_id}'
    }
)
```

## Step 3: Deploy Lambda Layer

Create a Lambda layer with the metrics helper:

```bash
# Create layer structure
mkdir -p lambda-layer/python
cp lambda/shared/metrics_helper.py lambda-layer/python/

# Package layer
cd lambda-layer
zip -r metrics-layer.zip python/

# Deploy layer
aws lambda publish-layer-version \
    --layer-name pdf-accessibility-metrics \
    --zip-file fileb://metrics-layer.zip \
    --compatible-runtimes python3.12
```

Update CDK to attach layer to all Lambda functions:
```python
# In app.py
metrics_layer = lambda_.LayerVersion(
    self, "MetricsLayer",
    code=lambda_.Code.from_asset("lambda-layer"),
    compatible_runtimes=[lambda_.Runtime.PYTHON_3_12]
)

# Add to each Lambda
split_pdf_lambda = lambda_.Function(
    self, 'SplitPDF',
    # ... existing config ...
    layers=[metrics_layer]
)
```

## Step 4: Deploy Usage Dashboard

Update `app.py` to include the usage metrics stack:

```python
from cdk.usage_metrics_stack import UsageMetricsDashboard

app = cdk.App()
pdf_stack = PDFAccessibility(app, "PDFAccessibility")

# Deploy usage metrics dashboard
UsageMetricsDashboard(
    app, "PDFAccessibilityUsageMetrics",
    pdf2pdf_bucket=pdf_stack.bucket.bucket_name,
    pdf2html_bucket=None  # Set if deploying pdf2html
)

app.synth()
```

## Step 5: Cost Tracking Lambda (Optional)

Create a scheduled Lambda to aggregate daily costs:

```python
# lambda/cost_aggregator/main.py
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Aggregate daily costs per user."""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=1)
    
    # Query CloudWatch metrics
    response = cloudwatch.get_metric_statistics(
        Namespace='PDFAccessibility',
        MetricName='EstimatedCost',
        Dimensions=[],
        StartTime=start_time,
        EndTime=end_time,
        Period=86400,  # 1 day
        Statistics=['Sum']
    )
    
    # Store in DynamoDB for historical tracking
    table = dynamodb.Table('PDFAccessibilityCosts')
    for datapoint in response['Datapoints']:
        table.put_item(Item={
            'date': datapoint['Timestamp'].isoformat(),
            'total_cost': str(datapoint['Sum']),
            'metric_type': 'daily_total'
        })
```

## Step 6: Validation

After deployment, validate metrics are being emitted:

```bash
# Check custom metrics
aws cloudwatch list-metrics --namespace PDFAccessibility

# Get sample metric data
aws cloudwatch get-metric-statistics \
    --namespace PDFAccessibility \
    --metric-name PagesProcessed \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## Pricing Reference

### PDF-to-PDF Costs
- **Adobe PDF Services**: ~$0.05 per API call
- **Bedrock Claude Haiku**: $0.00025/1K input, $0.00125/1K output tokens
- **Bedrock Claude Sonnet**: $0.003/1K input, $0.015/1K output tokens
- **Lambda**: $0.0000166667 per GB-second
- **ECS Fargate**: $0.04048/vCPU-hour + $0.004445/GB-hour
- **Step Functions**: $0.000025 per state transition

### PDF-to-HTML Costs
- **Bedrock Data Automation**: ~$0.01 per page
- **Bedrock Models**: Same as above
- **Lambda**: Same as above

## Next Steps

1. Deploy metrics layer
2. Update Lambda functions with metrics tracking
3. Implement S3 tagging for user attribution
4. Deploy usage dashboard
5. Monitor metrics in CloudWatch
6. Set up cost alerts
7. Create user usage reports
