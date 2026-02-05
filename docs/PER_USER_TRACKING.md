# Per-User Metrics Tracking

## Overview

Automated per-user tracking for both UI uploads and direct S3 uploads using a consistent tagging mechanism.

## Architecture

```
┌─────────────────┐         ┌──────────────────┐
│  Cognito UI     │         │  Direct S3       │
│  Upload         │         │  Upload          │
└────────┬────────┘         └────────┬─────────┘
         │                           │
         │ Metadata:                 │ No metadata
         │ user-sub: xxx             │
         │ user-groups: yyy          │
         │                           │
         └───────────┬───────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  S3 ObjectCreated     │
         │  Event                │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  S3 Tagger Lambda     │
         │  - Read metadata      │
         │  - Apply UserId tag   │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  Processing Lambda    │
         │  - Read UserId tag    │
         │  - Track metrics      │
         └───────────────────────┘
```

## How It Works

### 1. UI Uploads (Cognito Authenticated)

When users upload via the web UI:

```javascript
// UI sets metadata on S3 object
const params = {
  Bucket: bucket,
  Key: key,
  Body: file,
  Metadata: {
    'user-sub': userSub,           // Cognito user ID
    'user-groups': userGroups,     // User groups
    'upload-timestamp': timestamp
  }
};
```

### 2. S3 Tagger Lambda

Automatically triggered on ObjectCreated:

```python
# Extract from metadata
user_id = metadata.get('user-sub', 'anonymous')

# Apply as tag
s3_client.put_object_tagging(
    Bucket=bucket,
    Key=key,
    Tagging={'TagSet': [{'Key': 'UserId', 'Value': user_id}]}
)
```

### 3. Processing Lambdas

Read tags for metrics:

```python
# Get user from tags
tags_response = s3_client.get_object_tagging(Bucket=bucket, Key=key)
for tag in tags_response.get('TagSet', []):
    if tag['Key'] == 'UserId':
        user_id = tag['Value']

# Track metrics with user attribution
track_pages_processed(num_pages, user_id, file_name, "pdf2pdf")
```

## Benefits

✅ **Consistent Tracking**: Same mechanism for UI and direct uploads  
✅ **Automatic**: No manual tagging required  
✅ **Backward Compatible**: Direct uploads get 'anonymous' user ID  
✅ **Scalable**: Works with bulk uploads  
✅ **Secure**: Uses Cognito identity for authenticated users

## User Attribution Levels

| Upload Method | User ID Source | Value |
|--------------|----------------|-------|
| Cognito UI | user-sub metadata | `sub-xxx-xxx-xxx` |
| Direct S3 (tagged) | Manual tag | Custom value |
| Direct S3 (untagged) | Default | `anonymous` |

## Metrics Tracked Per User

- **Pages Processed**: Total pages remediated
- **Files Processed**: Number of PDFs processed
- **Processing Duration**: Time spent per file
- **Adobe API Calls**: AutoTag and ExtractPDF calls
- **Bedrock Tokens**: Input/output tokens used
- **Estimated Cost**: Per-user cost breakdown

## CloudWatch Dashboard

Metrics are aggregated by:
- **Service**: pdf2pdf or pdf2html
- **User**: Individual user tracking
- **Time**: Hourly/daily aggregation

## Deployment

The S3 tagger Lambda is automatically deployed with the main stack:

```bash
cd /mnt/c/code/PDF_Accessibility
./deploy-local.sh
```

## Testing

### Test UI Upload
1. Login to web UI with Cognito
2. Upload a PDF
3. Check CloudWatch metrics for your user-sub

### Test Direct Upload
1. Upload PDF directly to S3 bucket
2. Check object tags: `aws s3api get-object-tagging --bucket <bucket> --key <key>`
3. Verify UserId tag is set to 'anonymous'

### Test Manual Tagging
```bash
aws s3api put-object-tagging \
  --bucket <bucket> \
  --key pdf/myfile.pdf \
  --tagging 'TagSet=[{Key=UserId,Value=custom-user-123}]'
```

## Cost Tracking Query

Query per-user costs in CloudWatch Insights:

```
fields @timestamp, UserId, PagesProcessed, EstimatedCost
| filter MetricName = "PagesProcessed"
| stats sum(PagesProcessed) as TotalPages, sum(EstimatedCost) as TotalCost by UserId
| sort TotalCost desc
```

## Troubleshooting

**Tags not appearing:**
- Check S3 tagger Lambda logs: `/aws/lambda/PDFAccessibility-S3ObjectTagger`
- Verify IAM permissions for `s3:PutObjectTagging`

**Metrics missing user attribution:**
- Verify tags exist: `aws s3api get-object-tagging`
- Check processing Lambda logs for tag read errors

**UI uploads not tagged:**
- Verify UI is setting metadata correctly
- Check S3 tagger Lambda is triggered (CloudWatch logs)
