import json
import os
# Import bedrock_agentcore directly instead of using MemoryClient
import boto3
from datetime import datetime, timezone
from urllib.parse import urlparse

REGION = os.getenv("AWS_REGION", "us-east-1")
MEMORY_ID = os.environ["AGENTCORE_MEMORY_ID"]
MODEL_ID = os.environ["MY_BEDROCK_MODEL_ID"]

s3 = boto3.client("s3", region_name=REGION)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
agentcore = boto3.client("bedrock-agentcore", region_name=REGION)

EXTRACTION_SYSTEM = """You extract durable user memory for an assistant.
Return ONLY valid JSON:
{
  "facts":[{"key":"...", "value":"...", "confidence":0.0-1.0}]
}
Rules:
- Do NOT store secrets or highly sensitive identifiers (SSNs, passwords, full DOB, etc).
- Prefer stable long-lived facts (name, preferred contact method, etc).
"""

def _parse_s3_payload_location(s3_payload_location: str) -> tuple[str, str]:
    u = urlparse(s3_payload_location)
    if u.scheme != "s3" or not u.netloc or not u.path:
        raise ValueError(f"Unexpected s3PayloadLocation: {s3_payload_location}")
    return u.netloc, u.path.lstrip("/")

def _extract_text_from_context_item(item: dict) -> str:
    role = item.get("role", "UNKNOWN")
    content = item.get("content", {})
    text = content.get("text")
    if text is None:
        text = json.dumps(content) if content else json.dumps(item)
    return f"{role}: {text}"

def _build_transcript(payload: dict) -> str:
    parts = []
    for section in ("historicalContext", "currentContext"):
        for item in payload.get(section, []) or []:
            if "role" in item and "content" in item:
                parts.append(_extract_text_from_context_item(item))
    return "\n".join(parts)

def invoke_model(text: str) -> dict:
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 300,
        "messages": [
            {
                "role": "user",
                "content": f"{EXTRACTION_SYSTEM}\n\nText:\n{text}",
            }
        ],
    }

    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(body),
    )

    result = json.loads(resp["body"].read())
    content_text = result["content"][0]["text"]
    return json.loads(content_text)

def handler(event, context):
    # 1) SNS -> Lambda
    sns_msg_raw = event["Records"][0]["Sns"]["Message"]
    print("SNS message raw:", sns_msg_raw)

    msg = json.loads(sns_msg_raw)

    # 2) Get S3 payload location
    s3_payload_location = msg["s3PayloadLocation"]
    bucket, key = _parse_s3_payload_location(s3_payload_location)

    # 3) Download payload JSON
    obj = s3.get_object(Bucket=bucket, Key=key)
    delivered = json.loads(obj["Body"].read())

    actor_id = delivered.get("actorId")
    session_id = delivered.get("sessionId")

    transcript = _build_transcript(delivered)
    print(f"Transcript: {transcript}")
    
    extracted = invoke_model(transcript)
    print(f"Extracted facts: {extracted}")

    now = datetime.now(timezone.utc).isoformat()

    records = []
    for f in extracted.get("facts", []):
        print(f"Processing fact: {f}")
        records.append({
            "requestIdentifier": f"{session_id}-{f.get('key', 'unknown')}",
            # "namespaces": [f"/users/{actor_id}/info", "/"],
            "namespaces": ["/"],
            "content": {"text": f'{f["key"]}: {f["value"]}'},
            "timestamp": now,
        })
    
    print(f"Created {len(records)} records for actor_id: {actor_id}, session_id: {session_id}")

    # Store memories using boto3 bedrock-agentcore client
    if records:
        try:
            print(f"Attempting to store {len(records)} records to memory {MEMORY_ID}")
            response = agentcore.batch_create_memory_records(
                memoryId=MEMORY_ID,
                records=records,
            )
            print(f"Successfully stored records. Response: {response}")
        except Exception as e:
            print(f"Error storing records: {str(e)}")
            raise e
    else:
        print("No records to store")

    return {"ok": True, "stored": len(records)}
