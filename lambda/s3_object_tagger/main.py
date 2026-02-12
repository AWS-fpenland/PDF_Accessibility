"""
Lambda function to tag S3 objects with user information for metrics tracking.

Triggered on S3 ObjectCreated events to:
1. Extract user info from object metadata (UI uploads)
2. Apply UserId tag for consistent metrics tracking
3. Support both Cognito-authenticated and direct uploads
"""
import json
import boto3
import os
from urllib.parse import unquote_plus

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Tag S3 objects with UserId for metrics tracking.
    
    Extracts user-sub from object metadata (set by UI) and applies as UserId tag.
    Falls back to 'anonymous' for direct uploads without metadata.
    """
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing: s3://{bucket}/{key}")
        
        try:
            # Get object metadata
            response = s3_client.head_object(Bucket=bucket, Key=key)
            metadata = response.get('Metadata', {})
            
            # Extract user identifier
            user_id = metadata.get('user-sub', 'anonymous')
            user_groups = metadata.get('user-groups', '')
            
            # Get existing tags
            try:
                existing_tags = s3_client.get_object_tagging(Bucket=bucket, Key=key)
                tags = existing_tags.get('TagSet', [])
            except Exception:
                tags = []
            
            # Add/update UserId tag
            tag_dict = {tag['Key']: tag['Value'] for tag in tags}
            tag_dict['UserId'] = user_id
            
            if user_groups:
                tag_dict['UserGroups'] = user_groups
            
            # Apply tags
            new_tags = [{'Key': k, 'Value': v} for k, v in tag_dict.items()]
            s3_client.put_object_tagging(
                Bucket=bucket,
                Key=key,
                Tagging={'TagSet': new_tags}
            )
            
            print(f"Tagged with UserId: {user_id}")
            
        except Exception as e:
            print(f"Error tagging object: {e}")
            # Don't fail - let processing continue
    
    return {'statusCode': 200}
