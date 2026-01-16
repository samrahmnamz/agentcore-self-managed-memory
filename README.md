# How to Implement a Self-Managed Memory Strategy for AWS Bedrock AgentCore

This guide provides step-by-step instructions for implementing a self-managed memory strategy that automatically extracts and stores user information from conversations usin# User Info Agent - Self-Managed Memory Strategy


## Architecture Overview

```
AgentCore Conversation → Memory Trigger → SNS → Lambda → Bedrock LLM → Memory Storage
                                        ↓
                                    S3 Bucket (payload storage)
```

---

# Part 1: Infrastructure Setup

## Prerequisites
- AWS CLI configured with appropriate permissions
- Access to AWS Bedrock and AgentCore services
- Python 3.10+ environment

## 1. Deploy AWS Infrastructure

Create `infrastructure.yaml`:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  MemoryEventsBucket:
    Type: AWS::S3::Bucket
  MemoryEventsTopic:
    Type: AWS::SNS::Topic
  MemoryProcessorFunction:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: python3.11
      Handler: lambda_function.handler
      Role: !GetAtt LambdaExecutionRole.Arn
```

Deploy:
```bash
aws cloudformation deploy --template-file infrastructure.yaml --stack-name memory-infrastructure
```

## 2. Create IAM Role

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "bedrock-agentcore:*",
      "bedrock-runtime:InvokeModel",
      "s3:GetObject",
      "sns:Publish"
    ],
    "Resource": "*"
  }]
}
```

---

# Part 2: Memory Setup Script

**Run this locally or in a setup script to create the AgentCore memory:**

Create `setup_memory.py`:

```python
import boto3

# Configuration
REGION = "us-east-1"
MEMORY_EXEC_ROLE_ARN = "arn:aws:iam::ACCOUNT:role/memory-role"
SNS_TOPIC_ARN = "arn:aws:sns:REGION:ACCOUNT:memory-events"
S3_BUCKET = "your-memory-events-bucket"
 
def get_or_create_memory():
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    
    # Create new memory
    resp = control.create_memory(
        name="UserInfoSelfManagedMemory",
        description="Self-managed memory for user info extraction",
        memoryExecutionRoleArn=MEMORY_EXEC_ROLE_ARN,
        eventExpiryDuration=30,
        memoryStrategies=[{
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
        }],
    )
    
    memory_id = resp["memory"]["id"]
    print(f"Created memory: {memory_id}")
    return memory_id

if __name__ == "__main__":
    memory_id = get_or_create_memory()
    print(f"\n⚠️  SAVE THIS MEMORY ID: {memory_id}")
    print("You'll need it for:")
    print(f"  - Lambda environment variable: AGENTCORE_MEMORY_ID={memory_id}")
    print(f"  - Testing: python test_memory.py {memory_id}")
```

## 3. Update Lambda Environment Variables

**After running the setup script, update your Lambda function:**

```bash
# Use the memory ID from setup_memory.py output
aws lambda update-function-configuration \
  --function-name memory-processor \
  --environment Variables='{"AGENTCORE_MEMORY_ID":"UserInfoSelfManagedMemory-ABC123","MY_BEDROCK_MODEL_ID":"anthropic.claude-3-haiku-20240307-v1:0"}'
```

Or set via AWS Console:
- Go to Lambda → memory-processor → Configuration → Environment variables
- Add: `AGENTCORE_MEMORY_ID` = `UserInfoSelfManagedMemory-ABC123`
- Add: `MY_BEDROCK_MODEL_ID` = `anthropic.claude-3-haiku-20240307-v1:0`

---

# Part 3: Lambda Function Code

**Deploy this code to your Lambda function:**

Create `lambda_function.py`:

```python
import json
import boto3
import os
from datetime import datetime, timezone

# Environment variables
MEMORY_ID = os.environ['AGENTCORE_MEMORY_ID']
MODEL_ID = os.environ['MY_BEDROCK_MODEL_ID']
REGION = "us-east-1"

s3 = boto3.client('s3')

def handler(event, context):
    # 1. Parse SNS notification
    sns_msg_raw = event["Records"][0]["Sns"]["Message"]
    msg = json.loads(sns_msg_raw)
    
    # 2. Download conversation from S3
    s3_payload_location = msg["s3PayloadLocation"]
    bucket, key = _parse_s3_location(s3_payload_location)
    obj = s3.get_object(Bucket=bucket, Key=key)
    payload = json.loads(obj["Body"].read())
    
    # 3. Extract conversation context
    session_id = payload.get("sessionId")
    transcript = _build_transcript(payload)
    
    # 4. Extract facts using Bedrock
    extracted = _invoke_bedrock(transcript)
    
    # 5. Store facts in AgentCore memory
    records = []
    now = datetime.now(timezone.utc).isoformat()
    
    for fact in extracted.get("facts", []):
        records.append({
            "requestIdentifier": f"{session_id}-{fact.get('key', 'unknown')}",
            "namespaces": ["/"],
            "content": {"text": f'{fact["key"]}: {fact["value"]}'},
            "timestamp": now,
        })
    
    if records:
        agentcore = boto3.client("bedrock-agentcore", region_name=REGION)
        agentcore.batch_create_memory_records(
            memoryId=MEMORY_ID,
            records=records,
        )
    
    return {"statusCode": 200, "body": f"Stored {len(records)} records"}

def _invoke_bedrock(text: str) -> dict:
    prompt = """Extract user facts from this conversation. Return JSON:
    {"facts":[{"key":"name", "value":"John Doe", "confidence":0.9}]}
    Rules: No sensitive data (SSN, passwords). Only stable facts."""
    
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 300,
        "messages": [{"role": "user", "content": f"{prompt}\n\n{text}"}],
    }

    bedrock = boto3.client("bedrock-runtime", region_name=REGION)
    resp = bedrock.invoke_model(modelId=MODEL_ID, body=json.dumps(body))
    result = json.loads(resp["body"].read())
    return json.loads(result["content"][0]["text"])

def _parse_s3_location(location):
    # Parse s3://bucket/key format
    parts = location.replace("s3://", "").split("/", 1)
    return parts[0], parts[1]

def _build_transcript(payload):
    # Build conversation transcript from payload
    messages = payload.get("currentContext", [])
    return "\n".join([f"{msg['role']}: {msg['content']}" for msg in messages])
```

Deploy:
```bash
zip lambda_function.zip lambda_function.py
aws lambda update-function-code --function-name memory-processor --zip-file fileb://lambda_function.zip
```

---

# Part 4: Testing Memory Records

**Test script to verify memory storage and retrieval:**

Create `test_memory.py`:

```python
#!/usr/bin/env python3
import boto3
import sys
from datetime import datetime, timezone

def test_memory(memory_id):
    client = boto3.client("bedrock-agentcore", region_name="us-east-1")
    
    # Write test records (optional - you will have records written in by the lambda)
    records = [
        {
            "requestIdentifier": "test-name",
            "namespaces": ["/"],
            "content": {"text": "name: John Doe"},
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
        {
            "requestIdentifier": "test-email", 
            "namespaces": ["/"],
            "content": {"text": "email: john@example.com"},
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    ]
    
    print(f"Writing {len(records)} test records...")
    client.batch_create_memory_records(memoryId=memory_id, records=records)
    
    # Read back records
    print("\nReading memory records...")
    response = client.list_memory_records(memoryId=memory_id, namespace="/")
    
    records = response.get("memoryRecordSummaries", [])
    print(f"Found {len(records)} total records:")
    
    for record in records:
        content = record.get("content", {})
        timestamp = record.get("timestamp", "")
        print(f"  - {content.get('text', 'N/A')} (created: {timestamp[:19]})")
    
    return len(records)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python test_memory.py <memory-id>")
        sys.exit(1)
    
    memory_id = sys.argv[1]
    count = test_memory(memory_id)
    print(f"\nTotal records: {count}")
```

Run the test:
```bash
python test_memory.py UserInfoSelfManagedMemory-ABC123
```

Expected output:
```
Writing 2 test records...

Reading memory records...
Found 2 total records:
  - name: John Doe (created: 2024-01-01T12:00:00)
  - email: john@example.com (created: 2024-01-01T12:00:00)

Total records: 2
```

---

# Testing & Troubleshooting

## Test the Flow

1. **Create a conversation** in AgentCore (2+ messages)
2. **Check Lambda logs**: `aws logs tail /aws/lambda/memory-processor --follow`
3. **Verify memory records**: Use AgentCore API to list stored memories

## Common Issues

- **Lambda not triggered**: Check SNS subscription to your topic
- **S3 access denied**: Verify Lambda execution role permissions
- **Bedrock errors**: Check model ID and region availability
- **Memory storage fails**: Verify AgentCore permissions and memory ID

## Key Configuration

- **Trigger**: After 2 messages (`messageBasedTrigger`)
- **Context**: Last 20 messages (`historicalContextWindowSize`)
- **Storage**: Facts stored as key-value pairs in AgentCore memory