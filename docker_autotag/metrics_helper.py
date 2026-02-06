"""
CloudWatch Metrics Helper for PDF Accessibility Platform

This module provides utilities for emitting custom CloudWatch metrics
to track usage, costs, and performance across the PDF accessibility platform.
"""

import boto3
import time
from typing import Dict, List, Optional
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

NAMESPACE = "PDFAccessibility"

def emit_metric(
    metric_name: str,
    value: float,
    unit: str = "None",
    dimensions: Optional[Dict[str, str]] = None,
    timestamp: Optional[datetime] = None
):
    """
    Emit a single metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        unit: CloudWatch unit (Count, Milliseconds, Bytes, etc.)
        dimensions: Dict of dimension name/value pairs
        timestamp: Metric timestamp (defaults to now)
    """
    metric_data = {
        'MetricName': metric_name,
        'Value': value,
        'Unit': unit,
        'Timestamp': timestamp or datetime.utcnow()
    }
    
    if dimensions:
        metric_data['Dimensions'] = [
            {'Name': k, 'Value': v} for k, v in dimensions.items()
        ]
    
    try:
        cloudwatch.put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[metric_data]
        )
    except Exception as e:
        print(f"Failed to emit metric {metric_name}: {e}")

def track_pages_processed(
    page_count: int,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None,
    service: str = "pdf2pdf"
):
    """Track number of pages processed."""
    dimensions = {"Service": service}
    if user_id:
        dimensions["UserId"] = user_id
    # Don't include FileName - aggregate at service/user level only
    
    emit_metric("PagesProcessed", page_count, "Count", dimensions)

def track_adobe_api_call(
    operation: str,
    page_count: int = 0,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None
):
    """Track Adobe API calls and estimated Document Transactions.
    
    Adobe licensing:
    - AutoTag: 10 Document Transactions per page
    - ExtractPDF: 1 Document Transaction per 5 pages
    """
    dimensions = {
        "Service": "pdf2pdf",
        "Operation": operation
    }
    if user_id:
        dimensions["UserId"] = user_id
    
    emit_metric("AdobeAPICalls", 1, "Count", dimensions)
    
    # Calculate Document Transactions per Adobe licensing
    if page_count > 0:
        if operation == "AutoTag":
            doc_transactions = page_count * 10
        elif operation == "ExtractPDF":
            doc_transactions = -(-page_count // 5)  # ceiling division
        else:
            doc_transactions = 1
        emit_metric("AdobeDocTransactions", doc_transactions, "Count", dimensions)

def track_bedrock_invocation(
    model_id: str,
    input_tokens: int,
    output_tokens: int,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None,
    service: str = "pdf2pdf"
):
    """Track Bedrock model invocations and token usage."""
    dimensions = {
        "Service": service,
        "Model": model_id
    }
    if user_id:
        dimensions["UserId"] = user_id
    
    emit_metric("BedrockInvocations", 1, "Count", dimensions)
    emit_metric("BedrockInputTokens", input_tokens, "Count", dimensions)
    emit_metric("BedrockOutputTokens", output_tokens, "Count", dimensions)

def track_processing_duration(
    stage: str,
    duration_ms: float,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None,
    service: str = "pdf2pdf"
):
    """Track processing duration for a specific stage."""
    dimensions = {
        "Service": service,
        "Stage": stage
    }
    if user_id:
        dimensions["UserId"] = user_id
    # Don't include FileName
    
    emit_metric("ProcessingDuration", duration_ms, "Milliseconds", dimensions)

def track_error(
    error_type: str,
    stage: str,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None,
    service: str = "pdf2pdf"
):
    """Track errors by type and stage."""
    dimensions = {
        "Service": service,
        "Stage": stage,
        "ErrorType": error_type
    }
    if user_id:
        dimensions["UserId"] = user_id
    # Don't include FileName
    
    emit_metric("ErrorCount", 1, "Count", dimensions)

def track_file_size(
    size_bytes: int,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None,
    service: str = "pdf2pdf"
):
    """Track file size."""
    dimensions = {"Service": service}
    if user_id:
        dimensions["UserId"] = user_id
    # Don't include FileName
    
    emit_metric("FileSize", size_bytes, "Bytes", dimensions)

def estimate_cost(
    pages: int = 0,
    adobe_calls: int = 0,
    bedrock_input_tokens: int = 0,
    bedrock_output_tokens: int = 0,
    lambda_duration_ms: int = 0,
    lambda_memory_mb: int = 1024,
    ecs_duration_ms: int = 0,
    ecs_vcpu: float = 0.25,
    ecs_memory_gb: float = 1.0,
    user_id: Optional[str] = None,
    file_name: Optional[str] = None,
    service: str = "pdf2pdf"
) -> float:
    """
    Estimate cost for a processing job and emit metric.
    
    Pricing (approximate, as of 2024):
    - Adobe API: ~$0.05 per operation
    - Bedrock Claude Haiku: $0.00025/1K input, $0.00125/1K output
    - Bedrock Claude Sonnet: $0.003/1K input, $0.015/1K output
    - Lambda: $0.0000166667/GB-sec
    - ECS Fargate: $0.04048/vCPU-hr + $0.004445/GB-hr
    - BDA: ~$0.01 per page
    
    Returns:
        Estimated cost in USD
    """
    cost = 0.0
    
    # Adobe API cost
    cost += adobe_calls * 0.05
    
    # Bedrock cost (assuming Haiku for estimation)
    cost += (bedrock_input_tokens / 1000) * 0.00025
    cost += (bedrock_output_tokens / 1000) * 0.00125
    
    # Lambda cost
    gb_seconds = (lambda_memory_mb / 1024) * (lambda_duration_ms / 1000)
    cost += gb_seconds * 0.0000166667
    
    # ECS cost
    if ecs_duration_ms > 0:
        hours = ecs_duration_ms / (1000 * 3600)
        cost += (ecs_vcpu * hours * 0.04048) + (ecs_memory_gb * hours * 0.004445)
    
    # BDA cost (for pdf2html)
    if service == "pdf2html":
        cost += pages * 0.01
    
    # Emit cost metric
    dimensions = {"Service": service}
    if user_id:
        dimensions["UserId"] = user_id
    
    emit_metric("EstimatedCost", cost, "None", dimensions)
    
    return cost

class MetricsContext:
    """Context manager for tracking operation metrics."""
    
    def __init__(self, stage: str, user_id: Optional[str] = None, 
                 file_name: Optional[str] = None, service: str = "pdf2pdf"):
        self.stage = stage
        self.user_id = user_id
        self.file_name = file_name
        self.service = service
        self.start_time = None
    
    def __enter__(self):
        self.start_time = time.time()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        duration_ms = (time.time() - self.start_time) * 1000
        track_processing_duration(
            self.stage, duration_ms, 
            self.user_id, self.file_name, self.service
        )
        
        if exc_type:
            track_error(
                exc_type.__name__, self.stage,
                self.user_id, self.file_name, self.service
            )
        
        return False
