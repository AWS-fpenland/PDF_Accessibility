# Private CI/CD Pipeline — Getting Started Guide

Deploy the PDF Accessibility solution from your own private repository with full CI/CD integration, multi-environment support, and automated branch-based deployments.

## Prerequisites

| Tool | Minimum Version | Check Command |
|---|---|---|
| AWS CLI | v2.x | `aws --version` |
| AWS CDK | v2.x | `cdk --version` |
| Docker | 20.x+ | `docker --version` |
| jq | 1.6+ | `jq --version` |
| Git | 2.x | `git --version` |

**IAM Permissions** needed to run the setup script:
- `sts:GetCallerIdentity`
- `iam:CreateRole`, `iam:CreatePolicy`, `iam:AttachRolePolicy`, `iam:GetRole`
- `codebuild:CreateProject`, `codebuild:StartBuild`, `codebuild:BatchGetBuilds`, `codebuild:CreateWebhook`
- `codeconnections:GetConnection` (for GitHub/Bitbucket/GitLab)
- `secretsmanager:CreateSecret`, `secretsmanager:UpdateSecret` (for pdf2pdf)
- `bedrock:CreateDataAutomationProject` (for pdf2html)
- `s3:CreateBucket`, `s3api:PutBucketVersioning` (for pdf2html)
- `logs:DescribeLogStreams`, `logs:GetLogEvents`

## Step 1: Clone the Public Repository

### GitHub (Private)

```bash
git clone https://github.com/ASUCICREPO/PDF_Accessibility.git my-pdf-accessibility
cd my-pdf-accessibility
git remote rename origin upstream
# Create your private repo on GitHub, then:
git remote add origin https://github.com/YOUR_ORG/your-private-repo.git
git push -u origin main
```

### AWS CodeCommit

```bash
git clone https://github.com/ASUCICREPO/PDF_Accessibility.git my-pdf-accessibility
cd my-pdf-accessibility
git remote rename origin upstream
# Create a CodeCommit repo in your AWS account, then:
git remote add origin https://git-codecommit.us-east-1.amazonaws.com/v1/repos/your-repo
git push -u origin main
```

### Bitbucket

```bash
git clone https://github.com/ASUCICREPO/PDF_Accessibility.git my-pdf-accessibility
cd my-pdf-accessibility
git remote rename origin upstream
git remote add origin https://bitbucket.org/YOUR_ORG/your-private-repo.git
git push -u origin main
```

### GitLab

```bash
git clone https://github.com/ASUCICREPO/PDF_Accessibility.git my-pdf-accessibility
cd my-pdf-accessibility
git remote rename origin upstream
git remote add origin https://gitlab.com/YOUR_ORG/your-private-repo.git
git push -u origin main
```

### Pulling Future Updates from Upstream

```bash
git fetch upstream
git merge upstream/main --no-edit
git push origin main
```

## Step 2: Set Up AWS CodeConnections (GitHub/Bitbucket/GitLab only)

CodeCommit uses IAM authentication natively — skip this step if using CodeCommit.

### GitHub

1. Open the [AWS CodeConnections console](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Create connection**
3. Select **GitHub** as the provider
4. Name the connection (e.g., `my-github-connection`)
5. Click **Connect to GitHub** and authorize AWS in the OAuth flow
6. Complete the handshake — status should show **Available**
7. Copy the **Connection ARN**

### Bitbucket

1. Open the CodeConnections console
2. Click **Create connection** → select **Bitbucket**
3. Name the connection and authorize via OAuth
4. Verify status is **Available**
5. Copy the Connection ARN

### GitLab

1. Open the CodeConnections console
2. Click **Create connection** → select **GitLab**
3. Name the connection and authorize via OAuth
4. Verify status is **Available**
5. Copy the Connection ARN

## Step 3: Deploy — Interactive Mode

```bash
cd my-pdf-accessibility
./deploy-private.sh
```

The script will prompt you for:
1. **Repository URL** — your private repo URL
2. **Source provider** — github, codecommit, bitbucket, or gitlab
3. **Deployment type** — pdf2pdf or pdf2html
4. **Branch** — defaults to `main`
5. **Connection ARN** — (if not CodeCommit)
6. **Adobe credentials** — (if pdf2pdf)

## Step 4: Deploy — Non-Interactive Mode

Set environment variables and use the `--non-interactive` flag:

```bash
export PRIVATE_REPO_URL="https://github.com/myorg/my-fork.git"
export SOURCE_PROVIDER="github"
export DEPLOYMENT_TYPE="pdf2pdf"
export TARGET_BRANCH="main"
export CONNECTION_ARN="arn:aws:codeconnections:us-east-1:123456789:connection/abc-123"
export ADOBE_CLIENT_ID="your-client-id"
export ADOBE_CLIENT_SECRET="your-client-secret"

./deploy-private.sh --non-interactive
```

Or use a config file:

```bash
# Create pipeline.conf
cat > pipeline.conf << 'EOF'
PRIVATE_REPO_URL=https://github.com/myorg/my-fork.git
SOURCE_PROVIDER=github
DEPLOYMENT_TYPE=pdf2pdf
TARGET_BRANCH=main
CONNECTION_ARN=arn:aws:codeconnections:us-east-1:123456789:connection/abc-123
ADOBE_CLIENT_ID=your-client-id
ADOBE_CLIENT_SECRET=your-client-secret
EOF

./deploy-private.sh --config pipeline.conf --non-interactive
```

## Step 5: Multi-Environment Deployment

Deploy different branches to different environments with automatic webhook triggers:

```bash
./deploy-private.sh \
  --branch-env-map '{"main":"prod","dev":"dev","staging":"staging","feature/*":"dev"}' \
  --non-interactive
```

This creates:
- **prod** environment — triggered by pushes to `main` and PR merges to `main`
- **dev** environment — triggered by pushes to `dev` and `feature/*` branches
- **staging** environment — triggered by pushes to `staging`

Each environment gets isolated resources (separate CloudFormation stacks, S3 buckets, IAM roles) prefixed with the environment name.

Default mapping (when `--branch-env-map` is not provided and multi-env is not used):
```json
{"main": "prod", "dev": "dev", "test": "test", "staging": "staging"}
```

## Customization

### Custom Buildspec

```bash
./deploy-private.sh --buildspec my-custom-buildspec.yml
```

### Custom Project Name

```bash
./deploy-private.sh --project-name my-project-name
```

### Using a Named AWS CLI Profile

```bash
./deploy-private.sh --profile my-aws-profile
```

Or via environment variable:
```bash
export AWS_PROFILE=my-aws-profile
./deploy-private.sh
```

Or in a config file:
```
AWS_PROFILE=my-aws-profile
PRIVATE_REPO_URL=https://github.com/myorg/my-fork.git
...
```

### Modifying Infrastructure

Edit CDK stack files in your private repo. On the next build (push or manual trigger), CodeBuild will deploy the updated stacks automatically.

### Modifying Container Code

Edit Docker container code in your private repo. CodeBuild rebuilds and pushes updated images to ECR on each build.

## Cleanup

### Delete All Pipeline Resources

```bash
./deploy-private.sh --cleanup
```

### Delete a Specific Environment

```bash
./deploy-private.sh --cleanup --environment dev
```

### Non-Interactive Cleanup

```bash
./deploy-private.sh --cleanup --non-interactive
```

## Troubleshooting

### Connection Not in AVAILABLE Status

**Symptom:** `Connection is not AVAILABLE (current status: PENDING)`

**Fix:** Complete the OAuth handshake in the AWS Console:
1. Go to CodeConnections console
2. Find your connection
3. Click **Update pending connection**
4. Complete the authorization flow

### Insufficient IAM Permissions

**Symptom:** `AccessDenied` errors during setup

**Fix:** Ensure your AWS CLI user/role has the permissions listed in the Prerequisites section. The script creates IAM roles and policies, which requires `iam:CreateRole` and `iam:CreatePolicy`.

### CDK Bootstrap Failures

**Symptom:** `CDKToolkit stack not found` or bootstrap errors

**Fix:** The buildspec handles CDK bootstrap automatically. If it fails:
```bash
cdk bootstrap aws://ACCOUNT_ID/REGION
```

### Docker Build Failures

**Symptom:** Build fails during Docker image creation

**Fix:**
1. Ensure Docker is running locally if testing
2. Check that Dockerfiles exist in the expected paths
3. Verify ECR repository permissions
4. Check CodeBuild compute type — pdf2html requires `BUILD_GENERAL1_LARGE` for Docker builds

### Build Fails with No Logs

**Symptom:** Build status is FAILED but no logs are shown

**Fix:** Check the CodeBuild console directly:
1. Go to AWS CodeBuild console
2. Find your project (name starts with `pdfremediation-`)
3. Click the failed build
4. Review the build logs in the **Build logs** tab
