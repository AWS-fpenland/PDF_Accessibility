# PDF Accessibility - Observability Analysis

## Current State Analysis

### PDF-to-PDF Solution

#### Existing Logging
1. **CloudWatch Log Groups**
   - `/aws/lambda/{SplitPDFFunction}` - PDF splitting logs
   - `/aws/lambda/{JavaLambdaFunction}` - PDF merging logs
   - `/aws/lambda/{AddTitleFunction}` - Title addition logs
   - `/aws/lambda/{A11yPrecheck}` - Pre-remediation accessibility checks
   - `/aws/lambda/{A11yPostcheck}` - Post-remediation accessibility checks
   - `/ecs/MyFirstTaskDef/PythonContainerLogGroup` - Adobe API & extraction
   - `/ecs/MySecondTaskDef/JavaScriptContainerLogGroup` - LLM alt-text generation
   - `/aws/states/MyStateMachine_PDFAccessibility` - Step Functions execution logs

#### Existing Dashboard
- **File Status Widget**: Tracks file processing status across all components
- **Component-specific Log Widgets**: Individual log queries per Lambda/ECS task
- **Filtering**: Basic filename-based filtering

#### Missing Metrics
- ❌ Page count tracking
- ❌ Adobe API call counts/costs
- ❌ Bedrock invocation metrics (token usage, model costs)
- ❌ Processing duration per file
- ❌ Error rates and types
- ❌ User attribution
- ❌ Cost per file/user

### PDF-to-HTML Solution

#### Existing Logging
1. **CloudWatch Log Groups**
   - `/aws/lambda/Pdf2HtmlPipeline` - Main processing logs

#### Missing Metrics
- ❌ Page count tracking
- ❌ Bedrock Data Automation API calls
- ❌ Bedrock model invocations for remediation
- ❌ Processing duration
- ❌ Error tracking
- ❌ User attribution
- ❌ Cost per file/user

## Gaps Identified

### Critical Gaps
1. **No Custom Metrics**: Only log-based queries, no CloudWatch custom metrics
2. **No Cost Tracking**: No per-file or per-user cost calculation
3. **No User Attribution**: No mechanism to track which user processed which file
4. **Limited Bedrock Visibility**: No token usage or model invocation tracking
5. **No Adobe API Metrics**: No tracking of Adobe API calls or quotas

### Architectural Gaps
1. **No Centralized Metrics Store**: Each component logs independently
2. **No Usage Aggregation**: No rollup of metrics across files/users
3. **No Real-time Dashboards**: Current dashboard is log-query based (slow)

## Recommended Enhancements

### 1. Custom CloudWatch Metrics
Emit metrics at key processing points:
- `PDFAccessibility/PagesProcessed` (per file, per user)
- `PDFAccessibility/AdobeAPICalls` (per operation type)
- `PDFAccessibility/BedrockInvocations` (per model)
- `PDFAccessibility/BedrockTokens` (input/output, per model)
- `PDFAccessibility/ProcessingDuration` (per stage)
- `PDFAccessibility/ErrorCount` (per error type)

### 2. User Attribution
Add user context to all operations:
- S3 object tagging with user ID
- Lambda environment variable injection
- CloudWatch metric dimensions for user segmentation

### 3. Cost Calculation
Track billable events:
- Adobe API calls × pricing
- Bedrock tokens × model pricing
- Lambda duration × memory
- ECS task duration × vCPU/memory
- S3 storage and requests

### 4. Enhanced Dashboard
Create comprehensive dashboard with:
- Real-time metrics (not log queries)
- Cost breakdown by user/file
- Service usage trends
- Error rate monitoring
- Performance metrics

## Implementation Strategy

### Phase 1: Instrumentation (Immediate)
1. Add custom metric emission to all Lambda functions
2. Add page count extraction and tracking
3. Add Adobe API call counting
4. Add Bedrock token tracking

### Phase 2: User Attribution (Short-term)
1. Implement S3 object tagging for user context
2. Propagate user context through Step Functions
3. Add user dimension to all metrics

### Phase 3: Cost Tracking (Medium-term)
1. Create cost calculation Lambda
2. Aggregate metrics into cost estimates
3. Store cost data in DynamoDB or S3

### Phase 4: Advanced Dashboard (Medium-term)
1. Create real-time metrics dashboard
2. Add cost visualization
3. Add user usage reports
4. Add alerting for anomalies

## Metric Schema

### Dimensions
- `Service`: pdf2pdf | pdf2html
- `UserId`: User identifier
- `FileName`: Original file name
- `Stage`: split | extract | remediate | merge | finalize
- `Model`: Bedrock model ID
- `Operation`: Adobe operation type

### Metrics
```
PDFAccessibility/PagesProcessed (Count)
PDFAccessibility/AdobeAPICalls (Count) - Dimensions: Operation
PDFAccessibility/BedrockInvocations (Count) - Dimensions: Model
PDFAccessibility/BedrockInputTokens (Count) - Dimensions: Model
PDFAccessibility/BedrockOutputTokens (Count) - Dimensions: Model
PDFAccessibility/ProcessingDuration (Milliseconds) - Dimensions: Stage
PDFAccessibility/ErrorCount (Count) - Dimensions: ErrorType
PDFAccessibility/FileSize (Bytes)
PDFAccessibility/EstimatedCost (USD)
```

## Cost Calculation Formula

### PDF-to-PDF
```
Total Cost = 
  + Adobe API Cost (per operation)
  + Bedrock Cost (tokens × model price)
  + Lambda Cost (duration × memory × $0.0000166667/GB-sec)
  + ECS Cost (duration × vCPU × $0.04048/hr + memory × $0.004445/GB-hr)
  + S3 Cost (storage + requests)
  + Step Functions Cost (state transitions × $0.000025)
```

### PDF-to-HTML
```
Total Cost = 
  + Bedrock Data Automation Cost (per page)
  + Bedrock Model Cost (tokens × model price)
  + Lambda Cost (duration × memory × $0.0000166667/GB-sec)
  + S3 Cost (storage + requests)
```

## Next Steps
1. Review and approve enhancement plan
2. Implement Phase 1 instrumentation
3. Deploy enhanced observability stack
4. Validate metrics collection
5. Build cost tracking system
