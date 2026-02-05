import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    Duration,
)
from constructs import Construct

class UsageMetricsDashboard(Stack):
    def __init__(self, scope: Construct, construct_id: str, 
                 pdf2pdf_bucket: str = None,
                 pdf2html_bucket: str = None,
                 **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        region = Stack.of(self).region
        account = Stack.of(self).account
        
        # Create comprehensive usage dashboard
        dashboard = cloudwatch.Dashboard(
            self, "UsageMetricsDashboard",
            dashboard_name="PDF-Accessibility-Usage-Metrics"
        )
        
        # === SECTION 1: OVERVIEW METRICS ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="# PDF Accessibility Platform - Usage & Cost Metrics",
                width=24, height=1
            )
        )
        
        # Pages processed metrics
        pages_metric = cloudwatch.Metric(
            namespace="PDFAccessibility",
            metric_name="PagesProcessed",
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        # Files processed
        files_metric = cloudwatch.Metric(
            namespace="AWS/Lambda",
            metric_name="Invocations",
            dimensions_map={"FunctionName": "SplitPDF"},
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Pages Processed (Hourly)",
                left=[pages_metric],
                width=12, height=6
            ),
            cloudwatch.GraphWidget(
                title="Files Processed (Hourly)",
                left=[files_metric],
                width=12, height=6
            )
        )
        
        # === SECTION 2: BEDROCK METRICS ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Amazon Bedrock Usage",
                width=24, height=1
            )
        )
        
        # Bedrock invocations
        bedrock_invocations = cloudwatch.Metric(
            namespace="AWS/Bedrock",
            metric_name="Invocations",
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        # Bedrock input tokens
        bedrock_input_tokens = cloudwatch.Metric(
            namespace="AWS/Bedrock",
            metric_name="InputTokens",
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        # Bedrock output tokens
        bedrock_output_tokens = cloudwatch.Metric(
            namespace="AWS/Bedrock",
            metric_name="OutputTokens",
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Bedrock Model Invocations",
                left=[bedrock_invocations],
                width=8, height=6
            ),
            cloudwatch.GraphWidget(
                title="Bedrock Input Tokens",
                left=[bedrock_input_tokens],
                width=8, height=6
            ),
            cloudwatch.GraphWidget(
                title="Bedrock Output Tokens",
                left=[bedrock_output_tokens],
                width=8, height=6
            )
        )
        
        # === SECTION 3: ADOBE API METRICS (PDF-to-PDF) ===
        if pdf2pdf_bucket:
            dashboard.add_widgets(
                cloudwatch.TextWidget(
                    markdown="## Adobe PDF Services API Usage",
                    width=24, height=1
                )
            )
            
            adobe_calls = cloudwatch.Metric(
                namespace="PDFAccessibility",
                metric_name="AdobeAPICalls",
                statistic="Sum",
                period=Duration.hours(1)
            )
            
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title="Adobe API Calls by Operation",
                    left=[adobe_calls],
                    width=12, height=6
                ),
                cloudwatch.SingleValueWidget(
                    title="Total Adobe API Calls (24h)",
                    metrics=[adobe_calls.with_(statistic="Sum", period=Duration.hours(24))],
                    width=12, height=6
                )
            )
        
        # === SECTION 4: PROCESSING DURATION ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Processing Performance",
                width=24, height=1
            )
        )
        
        # Lambda durations
        lambda_duration = cloudwatch.Metric(
            namespace="AWS/Lambda",
            metric_name="Duration",
            statistic="Average",
            period=Duration.minutes(5)
        )
        
        # ECS task duration (for PDF-to-PDF)
        if pdf2pdf_bucket:
            ecs_duration = cloudwatch.Metric(
                namespace="AWS/ECS",
                metric_name="CPUUtilization",
                statistic="Average",
                period=Duration.minutes(5)
            )
            
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title="Lambda Processing Duration (avg)",
                    left=[lambda_duration],
                    width=12, height=6
                ),
                cloudwatch.GraphWidget(
                    title="ECS Task CPU Utilization",
                    left=[ecs_duration],
                    width=12, height=6
                )
            )
        else:
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title="Lambda Processing Duration (avg)",
                    left=[lambda_duration],
                    width=24, height=6
                )
            )
        
        # === SECTION 5: ERROR TRACKING ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Error Monitoring",
                width=24, height=1
            )
        )
        
        lambda_errors = cloudwatch.Metric(
            namespace="AWS/Lambda",
            metric_name="Errors",
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        step_function_errors = cloudwatch.Metric(
            namespace="AWS/States",
            metric_name="ExecutionsFailed",
            statistic="Sum",
            period=Duration.hours(1)
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Errors",
                left=[lambda_errors],
                width=12, height=6
            ),
            cloudwatch.GraphWidget(
                title="Step Function Failed Executions",
                left=[step_function_errors],
                width=12, height=6
            )
        )
        
        # === SECTION 6: COST ESTIMATION ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Estimated Costs (24h)\n\n" +
                "**Note**: These are estimates based on usage metrics. " +
                "Actual costs may vary. Check AWS Cost Explorer for precise billing.",
                width=24, height=2
            )
        )
        
        # Cost estimation widgets (using custom metrics)
        estimated_cost = cloudwatch.Metric(
            namespace="PDFAccessibility",
            metric_name="EstimatedCost",
            statistic="Sum",
            period=Duration.hours(24)
        )
        
        dashboard.add_widgets(
            cloudwatch.SingleValueWidget(
                title="Estimated Total Cost (24h)",
                metrics=[estimated_cost],
                width=8, height=4
            ),
            cloudwatch.SingleValueWidget(
                title="Estimated Cost per File (avg)",
                metrics=[
                    cloudwatch.MathExpression(
                        expression="cost / files",
                        using_metrics={
                            "cost": estimated_cost,
                            "files": files_metric.with_(period=Duration.hours(24))
                        }
                    )
                ],
                width=8, height=4
            ),
            cloudwatch.SingleValueWidget(
                title="Estimated Cost per Page (avg)",
                metrics=[
                    cloudwatch.MathExpression(
                        expression="cost / pages",
                        using_metrics={
                            "cost": estimated_cost,
                            "pages": pages_metric.with_(period=Duration.hours(24))
                        }
                    )
                ],
                width=8, height=4
            )
        )
        
        # === SECTION 7: USER USAGE (if user tagging implemented) ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Per-User Usage\n\n" +
                "**Note**: User-level metrics require S3 object tagging implementation. " +
                "See docs/OBSERVABILITY_ANALYSIS.md for details.",
                width=24, height=2
            )
        )
        
        # Log Insights queries for user usage
        if pdf2pdf_bucket:
            log_groups = [
                f"/aws/lambda/SplitPDF",
                f"/ecs/MyFirstTaskDef/PythonContainerLogGroup",
                f"/ecs/MySecondTaskDef/JavaScriptContainerLogGroup"
            ]
        else:
            log_groups = [f"/aws/lambda/Pdf2HtmlPipeline"]
        
        dashboard.add_widgets(
            cloudwatch.LogQueryWidget(
                title="Files Processed by User (requires user tagging)",
                log_group_names=log_groups,
                query_string='''fields @timestamp, userId, fileName
                    | filter userId != ""
                    | stats count() as fileCount by userId
                    | sort fileCount desc''',
                width=12, height=6
            ),
            cloudwatch.LogQueryWidget(
                title="Pages Processed by User (requires user tagging)",
                log_group_names=log_groups,
                query_string='''fields @timestamp, userId, pageCount
                    | filter userId != "" and pageCount > 0
                    | stats sum(pageCount) as totalPages by userId
                    | sort totalPages desc''',
                width=12, height=6
            )
        )
        
        # Output dashboard URL
        cdk.CfnOutput(
            self, "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name=PDF-Accessibility-Usage-Metrics",
            description="CloudWatch Dashboard URL for Usage Metrics"
        )
