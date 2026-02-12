# Metrics Implementation Analysis & Status

## Current State Summary

### ✅ Working Metrics

1. **PagesProcessed** - Tracking pages across all users
   - Dimensions: `Service`, `UserId` (when available)
   - Aggregates correctly in dashboard
   - Data visible in hourly graphs

2. **FileSize** - Tracking file sizes
   - Dimensions: `Service`, `UserId`
   - Working correctly

3. **ProcessingDuration** - Tracking processing time
   - Dimensions: `Service`, `Stage`, `UserId`
   - Working correctly

4. **AdobeAPICalls** - Adobe API usage tracking
   - Dimensions: `Service`, `Operation`, `FileName`
   - ⚠️ Still has FileName dimension (needs update)
   - Metrics ARE being emitted after IAM fix

### ⚠️ Issues Identified

#### 1. Log Insights Queries (Per-User Widgets)
**Problem**: Queries look for structured JSON fields (`userId`, `fileName`) but logs are plain text

**Current Log Format**:
```
Tagged object with UserId: a4289468-d0a1-702b-8c6a-ee09a21d3dc6
```

**Query Expects**:
```json
{"userId": "a4289468...", "fileName": "..."}
```

**Solution**: Either:
- A) Use CloudWatch metrics (already working) instead of Log Insights
- B) Add structured logging to emit JSON logs

#### 2. Adobe Metrics Still Have FileName Dimension
**Problem**: `AdobeAPICalls` metric still includes `FileName` dimension
**Impact**: Creates separate metric streams per file
**Solution**: Update `adobe-autotag-container/metrics_helper.py` to remove FileName

#### 3. Inconsistent Metric Dimensions
**Problem**: Mix of old metrics (with FileName) and new metrics (without)
**Impact**: Dashboard queries need to handle both
**Solution**: Wait for old metrics to age out OR update queries to aggregate both

## Recommended Approach: Use CloudWatch Metrics for Per-User Tracking

### Why Metrics > Log Insights for User Tracking

1. **Already Working**: Metrics have UserId dimension
2. **Efficient**: Pre-aggregated, no query cost
3. **Real-time**: Immediate visibility
4. **Consistent**: Same data source as other widgets

### Implementation

Replace Log Insights widgets with metric-based widgets:

```python
# Files by User
cloudwatch.GraphWidget(
    title="Files Processed by User",
    left=[cloudwatch.MathExpression(
        expression="SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'SampleCount', 86400)",
        label="Files per User"
    )],
    width=12, height=6,
    legend_position=cloudwatch.LegendPosition.RIGHT
)

# Pages by User  
cloudwatch.GraphWidget(
    title="Pages Processed by User",
    left=[cloudwatch.MathExpression(
        expression="SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'Sum', 86400)",
        label="Pages per User"
    )],
    width=12, height=6,
    legend_position=cloudwatch.LegendPosition.RIGHT
)
```

This will show one line per user automatically.

## Adobe API Metrics Dashboard Widget

```python
cloudwatch.GraphWidget(
    title="Adobe API Calls by Operation",
    left=[cloudwatch.MathExpression(
        expression="SEARCH('{PDFAccessibility,Service,Operation} MetricName=\"AdobeAPICalls\"', 'Sum', 3600)",
        label="API Calls"
    )],
    width=12, height=6,
    legend_position=cloudwatch.LegendPosition.RIGHT
)
```

## Action Items

### High Priority
1. ✅ Fix IAM permissions for ECS (DONE)
2. ⚠️ Replace Log Insights widgets with metric-based widgets
3. ⚠️ Add Adobe API metrics widget to dashboard
4. ⚠️ Remove FileName from Adobe metrics in docker container

### Medium Priority
5. Wait for old metrics (with FileName) to age out (15 months retention)
6. Add cost estimation metrics
7. Add error tracking metrics

### Low Priority  
8. Add structured logging if detailed log analysis needed
9. Create Athena views for historical analysis
10. Set up CloudWatch alarms for anomalies

## Metrics Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     S3 Upload Event                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Lambda: pdf-splitter-lambda                                  │
│  1. Read S3 metadata (user-sub)                             │
│  2. Apply UserId tag to S3 object                           │
│  3. Emit metrics: PagesProcessed, FileSize                  │
│     Dimensions: Service, UserId                             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  ECS Task: adobe-autotag-container                          │
│  1. Read UserId from S3 tags                                │
│  2. Call Adobe API (AutoTag, ExtractPDF)                    │
│  3. Emit metrics: AdobeAPICalls, ProcessingDuration         │
│     Dimensions: Service, Operation, UserId                  │
└─────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  CloudWatch Metrics                                          │
│  - Aggregated by Service, UserId                            │
│  - Dashboard queries with SEARCH expressions                │
│  - Per-user breakdown available                             │
└─────────────────────────────────────────────────────────────┘
```

## Key Principles

1. **Metrics over Logs**: Use CloudWatch Metrics for quantitative data
2. **Consistent Dimensions**: Service + UserId (no FileName)
3. **SEARCH Expressions**: Aggregate across all dimension values
4. **SUM() for Totals**: Wrap SEARCH in SUM() for single values
5. **User Attribution**: Via S3 object tags (metadata → tags → metrics)
