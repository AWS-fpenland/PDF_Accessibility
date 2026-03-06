# Key Workflows and Processes

## PDF-to-PDF Remediation Workflow

### End-to-End Process

```mermaid
flowchart TD
    Start([User Uploads PDF]) --> S3Upload[PDF saved to S3 pdf/ folder]
    S3Upload --> S3Event[S3 Event Notification]
    S3Event --> Splitter[PDF Splitter Lambda]
    
    Splitter --> Split{Split into<br/>pages}
    Split --> Chunk1[Page 1 PDF]
    Split --> Chunk2[Page 2 PDF]
    Split --> ChunkN[Page N PDF]
    
    Chunk1 & Chunk2 & ChunkN --> StepFn[Step Functions<br/>Orchestrator]
    
    StepFn --> PreCheck[Pre-Remediation<br/>Accessibility Check]
    PreCheck --> MapState[Map State:<br/>Parallel Processing]
    
    MapState --> Adobe1[Adobe Autotag<br/>ECS Task 1]
    MapState --> Adobe2[Adobe Autotag<br/>ECS Task 2]
    MapState --> AdobeN[Adobe Autotag<br/>ECS Task N]
    
    Adobe1 --> Alt1[Alt Text Generator<br/>ECS Task 1]
    Adobe2 --> Alt2[Alt Text Generator<br/>ECS Task 2]
    AdobeN --> AltN[Alt Text Generator<br/>ECS Task N]
    
    Alt1 & Alt2 & AltN --> MapComplete[All Chunks<br/>Processed]
    
    MapComplete --> TitleGen[Title Generator<br/>Lambda]
    TitleGen --> PostCheck[Post-Remediation<br/>Accessibility Check]
    PostCheck --> Merger[PDF Merger<br/>Lambda]
    Merger --> Result[Save to S3<br/>result/ folder]
    Result --> End([User Downloads<br/>Compliant PDF])
```

### Detailed Steps

#### 1. Upload and Trigger (0-5 seconds)
- User uploads PDF to S3 `pdf/` folder
- S3 generates PUT event notification
- Event triggers PDF Splitter Lambda
- S3 Object Tagger adds user metadata

#### 2. PDF Splitting (5-30 seconds)
- Lambda downloads PDF from S3
- Splits PDF into individual pages using pypdf
- Uploads each page to `temp/` folder
- Publishes metrics (pages processed, file size)
- Triggers Step Functions with chunk list

#### 3. Pre-Remediation Check (10-20 seconds)
- Lambda downloads original PDF
- Runs accessibility audit
- Generates baseline report
- Saves report to S3

#### 4. Parallel Chunk Processing (2-10 minutes per chunk)

**Map State Configuration**:
- Max concurrency: 10
- Retry attempts: 3
- Timeout: 30 minutes per chunk

**For Each Chunk**:

##### 4a. Adobe Autotag (1-5 minutes)
- ECS Fargate task starts
- Downloads chunk from S3
- Retrieves Adobe credentials from Secrets Manager
- Calls Adobe Autotag API
  - Adds structure tags (headings, lists, tables)
  - Identifies reading order
- Calls Adobe Extract API
  - Extracts images
  - Generates image metadata Excel file
- Creates SQLite database with image info
- Uploads tagged PDF to S3
- Publishes metrics (API calls, duration)

##### 4b. Alt Text Generation (1-5 minutes)
- ECS Fargate task starts
- Downloads tagged PDF and image metadata
- For each image:
  - Extracts surrounding text context
  - Determines if decorative or informative
  - If informative:
    - Encodes image as base64
    - Calls Bedrock Nova Pro with image + context
    - Receives AI-generated alt text
  - Embeds alt text in PDF structure
- Uploads final PDF to S3
- Publishes metrics (Bedrock calls, tokens)

#### 5. Title Generation (30-60 seconds)
- Lambda downloads first processed chunk
- Extracts text from first few pages
- Calls Bedrock Nova Pro with prompt
- Receives generated title
- Embeds title in PDF metadata
- Saves updated PDF

#### 6. Post-Remediation Check (10-20 seconds)
- Lambda downloads processed PDF
- Runs accessibility audit
- Compares with pre-check results
- Generates compliance report
- Saves report to S3

#### 7. PDF Merging (30-120 seconds)
- Java Lambda starts
- Downloads all processed chunks
- Merges in correct page order using Apache PDFBox
- Adds "COMPLIANT" prefix to filename
- Uploads to `result/` folder
- Publishes completion metrics

#### 8. Notification and Cleanup
- User receives notification (if UI deployed)
- Temporary files remain in `temp/` folder
- Optional: S3 lifecycle policy cleans up temp files after 7 days

### Total Processing Time
- **Small PDF (1-10 pages)**: 3-8 minutes
- **Medium PDF (11-50 pages)**: 8-20 minutes
- **Large PDF (51-200 pages)**: 20-60 minutes

---

## PDF-to-HTML Remediation Workflow

### End-to-End Process

```mermaid
flowchart TD
    Start([User Uploads PDF]) --> S3Upload[PDF saved to S3<br/>uploads/ folder]
    S3Upload --> S3Event[S3 Event Notification]
    S3Event --> Lambda[PDF2HTML Lambda]
    
    Lambda --> BDACreate[Create BDA Job]
    BDACreate --> BDAProcess[BDA Parses PDF]
    BDAProcess --> BDAWait{Wait for<br/>Completion}
    BDAWait -->|Polling| BDACheck[Check Status]
    BDACheck -->|Processing| BDAWait
    BDACheck -->|Complete| BDAResult[Retrieve Results]
    
    BDAResult --> Convert[Convert to HTML]
    Convert --> Audit[Audit Accessibility]
    
    Audit --> IssueLoop{For Each<br/>Issue}
    IssueLoop --> CheckType{Issue Type}
    
    CheckType -->|Simple| RuleBased[Rule-Based Fix]
    CheckType -->|Complex| AIFix[AI-Generated Fix]
    
    AIFix --> Bedrock[Call Bedrock<br/>Nova Pro]
    Bedrock --> ApplyFix[Apply Fix to HTML]
    RuleBased --> ApplyFix
    
    ApplyFix --> MoreIssues{More<br/>Issues?}
    MoreIssues -->|Yes| IssueLoop
    MoreIssues -->|No| Report[Generate Reports]
    
    Report --> Package[Package Outputs]
    Package --> ZIP[Create ZIP File]
    ZIP --> S3Save[Save to S3<br/>remediated/ folder]
    S3Save --> End([User Downloads ZIP])
```

### Detailed Steps

#### 1. Upload and Trigger (0-5 seconds)
- User uploads PDF to S3 `uploads/` folder
- S3 generates PUT event notification
- Event triggers PDF2HTML Lambda (container)
- S3 Object Tagger adds user metadata

#### 2. PDF to HTML Conversion (30-120 seconds)

##### 2a. BDA Job Creation
- Lambda calls Bedrock Data Automation API
- Creates async parsing job
- Receives job ID

##### 2b. BDA Processing
- BDA parses PDF structure
- Extracts text with layout information
- Identifies images, tables, headings
- Generates structured JSON output
- Saves to S3 output location

##### 2c. Status Polling
- Lambda polls BDA job status every 5 seconds
- Timeout: 5 minutes
- On completion, retrieves results

##### 2d. HTML Generation
- Lambda processes BDA JSON output
- Builds HTML structure from elements
- Preserves layout and styling
- Copies images to output directory
- Saves initial HTML to `output/result.html`

#### 3. Accessibility Audit (10-30 seconds)

##### 3a. HTML Parsing
- Loads HTML with BeautifulSoup
- Builds DOM tree

##### 3b. Check Execution
- Runs all accessibility checks:
  - Image checks (alt text)
  - Heading checks (hierarchy)
  - Table checks (headers, captions)
  - Form checks (labels, fieldsets)
  - Link checks (descriptive text)
  - Structure checks (landmarks, language)
  - Color contrast checks

##### 3c. Issue Collection
- Collects all issues with:
  - Element selector
  - WCAG criteria
  - Severity level
  - Suggested fix
- Generates audit report

#### 4. Remediation (1-5 minutes)

##### 4a. Issue Prioritization
- Groups issues by type
- Prioritizes critical issues
- Determines remediation strategy

##### 4b. Rule-Based Fixes (Simple Issues)
**Examples**:
- Add missing `lang` attribute
- Add `main` landmark
- Fix heading hierarchy
- Add table `scope` attributes
- Associate form labels

**Process**:
- Apply predefined transformation
- Update HTML DOM
- Mark issue as fixed

##### 4c. AI-Generated Fixes (Complex Issues)
**Examples**:
- Generate alt text for images
- Create table captions
- Improve link text
- Generate document title

**Process**:
1. Extract element and context
2. Build AI prompt with:
   - Issue description
   - Element HTML
   - Surrounding context
   - WCAG guidance
3. Call Bedrock Nova Pro
4. Parse AI response
5. Apply fix to HTML
6. Validate fix
7. Mark issue as fixed or manual review

##### 4d. Manual Review Items
**Flagged for Manual Review**:
- Complex table structures
- Ambiguous image context
- Color contrast requiring design changes
- Structural changes affecting layout

#### 5. Report Generation (5-15 seconds)

##### 5a. HTML Report
- Interactive report with:
  - Summary statistics
  - Issue breakdown by severity
  - WCAG criteria mapping
  - Before/after comparisons
  - Manual review items
- Styled with CSS
- JavaScript for filtering

##### 5b. JSON Report
- Machine-readable format
- Complete issue details
- Remediation actions
- Usage statistics

##### 5c. Usage Data
- Bedrock invocations and tokens
- BDA processing time
- Cost estimates
- Processing metrics

#### 6. Packaging and Output (5-10 seconds)

##### 6a. File Collection
- `remediated.html`: Final accessible HTML
- `result.html`: Original conversion (before remediation)
- `images/`: Extracted images with alt text
- `remediation_report.html`: Detailed report
- `usage_data.json`: Usage statistics

##### 6b. ZIP Creation
- Creates `final_{filename}.zip`
- Includes all output files
- Preserves directory structure

##### 6c. S3 Upload
- Uploads ZIP to `remediated/` folder
- Sets appropriate metadata
- Publishes completion metrics

#### 7. Cleanup
- Removes temporary files
- Logs completion
- Returns success response

### Total Processing Time
- **Small PDF (1-10 pages)**: 1-3 minutes
- **Medium PDF (11-50 pages)**: 3-8 minutes
- **Large PDF (51-200 pages)**: 8-20 minutes

---

## Deployment Workflow

### One-Click Deployment (deploy.sh)

```mermaid
flowchart TD
    Start([Run deploy.sh]) --> Check[Check Prerequisites]
    Check --> Region[Select AWS Region]
    Region --> Solution{Select Solution}
    
    Solution -->|PDF-to-PDF| Adobe[Enter Adobe Credentials]
    Solution -->|PDF-to-HTML| BDA[Check BDA Access]
    Solution -->|Both| Adobe
    
    Adobe --> Secrets[Store in Secrets Manager]
    BDA --> Project[Create BDA Project]
    Secrets & Project --> CodeBuild[Create CodeBuild Project]
    
    CodeBuild --> Build[Start Build]
    Build --> CDKSynth[CDK Synth]
    CDKSynth --> CDKDeploy[CDK Deploy]
    
    CDKDeploy --> Stack1[Deploy PDF-to-PDF Stack]
    CDKDeploy --> Stack2[Deploy PDF-to-HTML Stack]
    CDKDeploy --> Stack3[Deploy Metrics Stack]
    
    Stack1 & Stack2 & Stack3 --> Verify[Verify Deployment]
    Verify --> UI{Deploy UI?}
    
    UI -->|Yes| UIBuild[Build UI Stack]
    UI -->|No| Complete
    UIBuild --> Complete[Deployment Complete]
    Complete --> End([Show Testing Instructions])
```

### Manual Deployment

```mermaid
flowchart TD
    Start([Developer]) --> Clone[Clone Repository]
    Clone --> Install[Install Dependencies]
    Install --> Config[Configure AWS CLI]
    Config --> Secrets[Create Secrets]
    Secrets --> Synth[cdk synth]
    Synth --> Deploy[cdk deploy --all]
    Deploy --> Verify[Verify Resources]
    Verify --> Test[Run Tests]
    Test --> End([Deployment Complete])
```

---

## Error Handling Workflows

### Retry Logic

```mermaid
flowchart TD
    Start[Operation Starts] --> Try[Attempt Operation]
    Try --> Success{Success?}
    Success -->|Yes| End([Complete])
    Success -->|No| CheckRetries{Retries<br/>Remaining?}
    CheckRetries -->|Yes| Wait[Exponential Backoff]
    Wait --> Retry[Retry Attempt]
    Retry --> Try
    CheckRetries -->|No| Error[Log Error]
    Error --> Metric[Publish Error Metric]
    Metric --> Fail([Fail])
```

**Retry Configuration**:
- Max attempts: 3
- Backoff rate: 2.0
- Initial delay: 1 second
- Max delay: 60 seconds

### Error Recovery

#### Adobe API Failure
1. Log error to CloudWatch
2. Publish error metric
3. Retry with exponential backoff
4. If all retries fail:
   - Mark chunk as failed
   - Continue with other chunks
   - Generate partial result

#### Bedrock Throttling
1. Detect throttling error
2. Implement exponential backoff
3. Reduce request rate
4. Retry operation
5. If persistent:
   - Fall back to rule-based fixes
   - Flag for manual review

#### BDA Timeout
1. Cancel BDA job
2. Retry with smaller page range
3. If timeout persists:
   - Process pages individually
   - Combine results

---

## Monitoring Workflow

### Metrics Collection

```mermaid
flowchart LR
    Lambda[Lambda/ECS] --> Emit[Emit Metrics]
    Emit --> CW[CloudWatch Metrics]
    CW --> Dashboard[Dashboard]
    CW --> Alarms[CloudWatch Alarms]
    Alarms --> SNS[SNS Notifications]
    SNS --> Email[Email/SMS]
```

### Log Aggregation

```mermaid
flowchart LR
    Components[All Components] --> Logs[CloudWatch Logs]
    Logs --> Insights[CloudWatch Insights]
    Insights --> Queries[Custom Queries]
    Queries --> Analysis[Analysis & Debugging]
```

---

## Cost Tracking Workflow

```mermaid
flowchart TD
    Upload[User Uploads PDF] --> Tag[S3 Object Tagger]
    Tag --> Process[Processing Pipeline]
    Process --> Track[Usage Tracker]
    Track --> Metrics[Publish Cost Metrics]
    Metrics --> Dashboard[Cost Dashboard]
    Dashboard --> Report[Per-User Cost Report]
```

**Cost Attribution**:
1. S3 object tagged with user ID
2. All operations track user ID
3. Metrics published with user dimension
4. Dashboard aggregates by user
5. Monthly cost reports generated
