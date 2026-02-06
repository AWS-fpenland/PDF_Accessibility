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
                 split_pdf_log_group: str = None,
                 python_container_log_group: str = None,
                 javascript_container_log_group: str = None,
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
        
        # Pages processed - aggregate across all users
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Pages Processed (Hourly)",
                left=[cloudwatch.MathExpression(
                    expression="SUM(SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'Sum', 3600))",
                    label="Total Pages"
                )],
                width=12, height=6
            ),
            cloudwatch.GraphWidget(
                title="Files Processed (Hourly)", 
                left=[cloudwatch.MathExpression(
                    expression="SUM(SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'SampleCount', 3600))",
                    label="Files"
                )],
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
                title="Files Processed (24h)",
                metrics=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service} MetricName=\"PagesProcessed\"', 'SampleCount', 86400)",
                    label="Files"
                )],
                width=8, height=4
            ),
            cloudwatch.SingleValueWidget(
                title="Pages Processed (24h)",
                metrics=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service} MetricName=\"PagesProcessed\"', 'Sum', 86400)",
                    label="Pages"
                )],
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
        
        # Per-user metrics using CloudWatch Metrics (not Log Insights)
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Files Processed by User (24h)",
                left=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'SampleCount', 86400)",
                    label="Files"
                )],
                width=12, height=6,
                legend_position=cloudwatch.LegendPosition.RIGHT
            ),
            cloudwatch.GraphWidget(
                title="Pages Processed by User (24h)",
                left=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'Sum', 86400)",
                    label="Pages"
                )],
                width=12, height=6,
                legend_position=cloudwatch.LegendPosition.RIGHT
            )
        )
        
        # Adobe API metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Adobe API Calls by Operation",
                left=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service,Operation} MetricName=\"AdobeAPICalls\"', 'Sum', 3600)",
                    label="API Calls"
                )],
                width=12, height=6,
                legend_position=cloudwatch.LegendPosition.RIGHT
            )
        )
        
        # Output dashboard URL
        cdk.CfnOutput(
            self, "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name=PDF-Accessibility-Usage-Metrics",
            description="CloudWatch Dashboard URL for Usage Metrics"
        )
