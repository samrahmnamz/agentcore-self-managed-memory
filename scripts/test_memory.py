#!/usr/bin/env python3
"""
Test script to write and read memory records from AgentCore
"""
import boto3
import sys
from datetime import datetime, timezone

REGION = "us-east-1"

def test_memory(memory_id):
    client = boto3.client("bedrock-agentcore", region_name=REGION)
    
    # Write test records
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
    
    print(f"Writing {len(records)} test records to memory {memory_id}...")
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
