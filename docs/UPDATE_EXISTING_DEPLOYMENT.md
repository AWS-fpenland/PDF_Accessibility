# Updating Existing Deployment from New Environment

## Scenario
You previously deployed the PDF Accessibility stacks from a different machine/environment and now want to update them from your current environment with the new observability features.

## Solution Options

### Option 1: Direct CDK Deploy (Recommended)

CDK can update existing stacks even from a different environment. The stack names and resources are tracked in CloudFormation.

```bash
cd /mnt/c/code/PDF_Accessibility

# 1. Bootstrap CDK in your account/region (if not already done)
cdk bootstrap

# 2. Deploy updates to existing stacks
cdk deploy --all

# Or deploy specific stacks
cdk deploy PDFAccessibility
cdk deploy PDFAccessibilityUsageMetrics
```

**What happens:**
- CDK detects existing stacks by name
- Creates changeset with only the differences
- Updates existing resources
- Adds new resources (metrics layer, dashboard)
- No data loss or downtime

### Option 2: Import Existing Stack State

If you get errors about stack already exists, explicitly import the state:

```bash
# 1. Get existing stack info
aws cloudformation describe-stacks --stack-name PDFAccessibility > existing-stack.json

# 2. Synthesize your local CDK
cdk synth

# 3. Deploy with explicit stack name
cdk deploy PDFAccessibility --exclusively
```

### Option 3: Use CloudFormation Directly

If CDK has issues, use CloudFormation change sets:

```bash
# 1. Synthesize CDK to CloudFormation template
cdk synth PDFAccessibility > template.yaml

# 2. Create change set
aws cloudformation create-change-set \
    --stack-name PDFAccessibility \
    --change-set-name observability-update \
    --template-body file://template.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# 3. Review changes
aws cloudformation describe-change-set \
    --stack-name PDFAccessibility \
    --change-set-name observability-update

# 4. Execute change set
aws cloudformation execute-change-set \
    --stack-name PDFAccessibility \
    --change-set-name observability-update
```

## Pre-Deployment Checklist

### 1. Verify AWS Credentials
```bash
aws sts get-caller-identity
```
Ensure you're using the same AWS account where stacks were originally deployed.

### 2. Check Existing Stacks
```bash
aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `PDFAccessibility`)].{Name:StackName,Status:StackStatus}'
```

### 3. Verify Region
```bash
echo $AWS_DEFAULT_REGION
# Or
aws configure get region
```
Must match the region where stacks were deployed.

### 4. Check for Drift
```bash
aws cloudformation detect-stack-drift --stack-name PDFAccessibility
```

## What Gets Updated

### New Resources Added
- ✅ Lambda Layer: `MetricsLayer`
- ✅ CloudWatch Dashboard: `PDF-Accessibility-Usage-Metrics`
- ✅ New Stack: `PDFAccessibilityUsageMetrics`

### Existing Resources Modified
- ✅ All Lambda functions: Add metrics layer
- ✅ Lambda execution roles: Add CloudWatch PutMetricData permission
- ✅ Lambda code: Updated with metrics tracking

### No Changes To
- ✅ S3 buckets (data preserved)
- ✅ VPC and networking
- ✅ ECS cluster
- ✅ Step Functions state machine
- ✅ Secrets Manager secrets

## Handling Common Issues

### Issue 1: "Stack already exists"
```bash
# Solution: Use --exclusively flag
cdk deploy PDFAccessibility --exclusively
```

### Issue 2: "No updates to perform"
```bash
# CDK detected no changes - this is OK
# Your stacks are already up to date
```

### Issue 3: "Insufficient permissions"
```bash
# Check your IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name YOUR_USERNAME

# You need: CloudFormation, Lambda, IAM, S3, ECS, StepFunctions permissions
```

### Issue 4: "Resource already exists"
This happens if resources were created outside CDK. Options:

**A. Import into CDK:**
```bash
cdk import PDFAccessibility
```

**B. Remove from template temporarily:**
Comment out the conflicting resource in `app.py`, deploy, then uncomment and deploy again.

### Issue 5: Lambda Layer Update Fails
```bash
# Delete old layer versions if needed
aws lambda list-layer-versions --layer-name MetricsLayer
aws lambda delete-layer-version --layer-name MetricsLayer --version-number X
```

## Rollback Plan

If deployment fails or causes issues:

### Rollback via CloudFormation
```bash
# List recent stack events
aws cloudformation describe-stack-events \
    --stack-name PDFAccessibility \
    --max-items 20

# Rollback to previous version
aws cloudformation cancel-update-stack --stack-name PDFAccessibility
```

### Rollback via CDK
```bash
# Revert code changes
git revert HEAD

# Redeploy
cdk deploy --all
```

## Verification After Update

### 1. Check Stack Status
```bash
aws cloudformation describe-stacks \
    --stack-name PDFAccessibility \
    --query 'Stacks[0].StackStatus'
```
Should show: `UPDATE_COMPLETE`

### 2. Verify Lambda Layer
```bash
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `PDF`)].{Name:FunctionName,Layers:Layers[*].Arn}'
```
All functions should have the metrics layer.

### 3. Check Dashboard
```bash
aws cloudwatch list-dashboards \
    --query 'DashboardEntries[?contains(DashboardName, `PDF-Accessibility`)].DashboardName'
```

### 4. Test Processing
```bash
# Upload a test file
aws s3 cp test.pdf s3://YOUR-BUCKET/pdf/test.pdf

# Check metrics after processing
aws cloudwatch list-metrics --namespace PDFAccessibility
```

## Best Practices

### 1. Test in Non-Production First
If you have dev/staging environments, update those first.

### 2. Backup Important Data
```bash
# Backup S3 bucket
aws s3 sync s3://your-bucket s3://your-backup-bucket

# Export CloudFormation templates
aws cloudformation get-template \
    --stack-name PDFAccessibility \
    --query 'TemplateBody' > backup-template.json
```

### 3. Deploy During Low Traffic
Schedule updates during maintenance windows.

### 4. Monitor After Deployment
```bash
# Watch CloudWatch Logs
aws logs tail /aws/lambda/SplitPDF --follow

# Monitor CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name PDFAccessibility \
    --max-items 10
```

## Quick Update Script

Save this as `update-deployment.sh`:

```bash
#!/bin/bash
set -e

echo "🔍 Verifying AWS credentials..."
aws sts get-caller-identity

echo "📋 Checking existing stacks..."
aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `PDFAccessibility`)].StackName'

echo "🚀 Deploying updates..."
cdk deploy --all --require-approval never

echo "✅ Deployment complete!"
echo "📊 Dashboard URL:"
aws cloudformation describe-stacks \
    --stack-name PDFAccessibilityUsageMetrics \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text

echo "🔍 Verifying metrics..."
sleep 10
aws cloudwatch list-metrics --namespace PDFAccessibility
```

Run it:
```bash
chmod +x update-deployment.sh
./update-deployment.sh
```

## Alternative: Fresh Deployment

If updating is problematic, you can deploy fresh stacks with new names:

```python
# In app.py, change stack names
app = cdk.App()
pdf_stack = PDFAccessibility(app, "PDFAccessibility-v2")  # New name
UsageMetricsDashboard(app, "PDFAccessibilityUsageMetrics-v2", 
    pdf2pdf_bucket=pdf_stack.bucket.bucket_name)
```

Then:
1. Deploy new stacks
2. Migrate data from old buckets
3. Delete old stacks

## Summary

**Recommended Approach:**
```bash
cd /mnt/c/code/PDF_Accessibility
cdk bootstrap  # If needed
cdk deploy --all
```

This will:
- ✅ Detect and update existing stacks
- ✅ Add new observability features
- ✅ Preserve all existing data
- ✅ Zero downtime

**Time Required:** 5-10 minutes

**Risk Level:** Low (CDK handles updates safely)
