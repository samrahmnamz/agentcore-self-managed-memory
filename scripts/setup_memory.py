#!/usr/bin/env python3
"""
Create or get existing self-managed memory for user info extraction
"""
import os
import boto3

REGION = os.getenv("AWS_REGION", "us-east-1")

# Required environment variables
S3_BUCKET = os.environ["MEMORY_EVENTS_BUCKET"]
SNS_TOPIC_ARN = os.environ["MEMORY_EVENTS_TOPIC_ARN"]
MEMORY_EXEC_ROLE_ARN = os.environ["MEMORY_EXEC_ROLE_ARN"]

def get_or_create_memory():
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    
    # First, try to find existing memory by ID pattern
    try:
        response = control.list_memories()
        for memory in response.get('memories', []):
            if memory['id'].startswith('UserInfoSelfManagedMemory-'):
                # print(memory)
                memory_id = memory['id']
                return memory_id
    except Exception as e:
        print(f"Error listing memories: {str(e)}")
    
    # Create new memory if not found
    resp = control.create_memory(
        name="UserInfoSelfManagedMemory",
        description="Self-managed memory for user info extraction",
        memoryExecutionRoleArn=MEMORY_EXEC_ROLE_ARN,
        eventExpiryDuration=30,  # days
        memoryStrategies=[
            {
                "customMemoryStrategy": {
                    "name": "user_info_self_managed",
                    "description": "Self-managed user info extraction",
                    "configuration": {
                        "selfManagedConfiguration": {
                            "triggerConditions": [
                                {"messageBasedTrigger": {"messageCount": 2}}
                            ],
                            "invocationConfiguration": {
                                "topicArn": SNS_TOPIC_ARN,
                                "payloadDeliveryBucketName": S3_BUCKET,
                            },
                            "historicalContextWindowSize": 20,
                        }
                    },
                }
            }
        ],
    )
    
    memory_id = resp["memory"]["id"]
    return memory_id

if __name__ == "__main__":
    memory_id = get_or_create_memory()
    print(memory_id)  # Output just the ID for Makefile to capture
