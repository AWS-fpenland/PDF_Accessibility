import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_cloudwatch as cloudwatch,
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

        dashboard = cloudwatch.Dashboard(
            self, "UsageMetricsDashboard",
            dashboard_name="PDF-Accessibility-Usage-Metrics"
        )

        # === HEADER ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="# PDF Accessibility Platform - Usage & Cost Metrics",
                width=24, height=1
            )
        )

        # === SECTION 1: AGGREGATE TOTALS ===
        # These are the working widgets — SUM wraps SEARCH to collapse all users into one line
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
                    label="Total Files"
                )],
                width=12, height=6
            )
        )

        # === SECTION 2: PER-USER BREAKDOWN ===
        # Same SEARCH without SUM — each UserId gets its own line in the graph
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Per-User Usage",
                width=24, height=1
            )
        )
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Files Processed by User",
                left=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'SampleCount', 3600)",
                    label=""
                )],
                width=12, height=6,
                legend_position=cloudwatch.LegendPosition.RIGHT
            ),
            cloudwatch.GraphWidget(
                title="Pages Processed by User",
                left=[cloudwatch.MathExpression(
                    expression="SEARCH('{PDFAccessibility,Service,UserId} MetricName=\"PagesProcessed\"', 'Sum', 3600)",
                    label=""
                )],
                width=12, height=6,
                legend_position=cloudwatch.LegendPosition.RIGHT
            )
        )

        # === SECTION 3: BEDROCK METRICS ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Amazon Bedrock Usage",
                width=24, height=1
            )
        )
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Bedrock Model Invocations",
                left=[cloudwatch.Metric(
                    namespace="AWS/Bedrock", metric_name="Invocations",
                    statistic="Sum", period=Duration.hours(1)
                )],
                width=8, height=6
            ),
            cloudwatch.GraphWidget(
                title="Bedrock Input Tokens",
                left=[cloudwatch.Metric(
                    namespace="AWS/Bedrock", metric_name="InputTokens",
                    statistic="Sum", period=Duration.hours(1)
                )],
                width=8, height=6
            ),
            cloudwatch.GraphWidget(
                title="Bedrock Output Tokens",
                left=[cloudwatch.Metric(
                    namespace="AWS/Bedrock", metric_name="OutputTokens",
                    statistic="Sum", period=Duration.hours(1)
                )],
                width=8, height=6
            )
        )

        # === SECTION 4: ADOBE API (PDF-to-PDF only) ===
        if pdf2pdf_bucket:
            dashboard.add_widgets(
                cloudwatch.TextWidget(
                    markdown="## Adobe PDF Services API Usage",
                    width=24, height=1
                )
            )
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title="Adobe API Calls by Operation",
                    left=[cloudwatch.MathExpression(
                        expression="SEARCH('{PDFAccessibility,Service,Operation} MetricName=\"AdobeAPICalls\"', 'Sum', 3600)",
                        label=""
                    )],
                    width=12, height=6,
                    legend_position=cloudwatch.LegendPosition.RIGHT
                ),
                cloudwatch.SingleValueWidget(
                    title="Total Adobe API Calls (24h)",
                    metrics=[cloudwatch.MathExpression(
                        expression="SUM(SEARCH('{PDFAccessibility,Service,Operation} MetricName=\"AdobeAPICalls\"', 'Sum', 86400))",
                        label="Calls"
                    )],
                    width=12, height=6
                )
            )

        # === SECTION 5: PROCESSING PERFORMANCE ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Processing Performance",
                width=24, height=1
            )
        )
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Processing Duration (avg ms)",
                left=[cloudwatch.Metric(
                    namespace="AWS/Lambda", metric_name="Duration",
                    statistic="Average", period=Duration.minutes(5)
                )],
                width=12, height=6
            ),
            cloudwatch.GraphWidget(
                title="ECS Task CPU Utilization" if pdf2pdf_bucket else "Lambda Concurrent Executions",
                left=[cloudwatch.Metric(
                    namespace="AWS/ECS" if pdf2pdf_bucket else "AWS/Lambda",
                    metric_name="CPUUtilization" if pdf2pdf_bucket else "ConcurrentExecutions",
                    statistic="Average", period=Duration.minutes(5)
                )],
                width=12, height=6
            )
        )

        # === SECTION 6: ERROR MONITORING ===
        dashboard.add_widgets(
            cloudwatch.TextWidget(
                markdown="## Error Monitoring",
                width=24, height=1
            )
        )
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Errors",
                left=[cloudwatch.Metric(
                    namespace="AWS/Lambda", metric_name="Errors",
                    statistic="Sum", period=Duration.hours(1)
                )],
                width=12, height=6
            ),
            cloudwatch.GraphWidget(
                title="Step Function Failed Executions",
                left=[cloudwatch.Metric(
                    namespace="AWS/States", metric_name="ExecutionsFailed",
                    statistic="Sum", period=Duration.hours(1)
                )],
                width=12, height=6
            )
        )

        # Output dashboard URL
        cdk.CfnOutput(
            self, "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name=PDF-Accessibility-Usage-Metrics",
            description="CloudWatch Dashboard URL for Usage Metrics"
        )
