# User Info Agent - Self-Managed Memory Strategy

A sample implementation demonstrating AWS Bedrock AgentCore self-managed memory that automatically extracts and stores user information from conversations.

## Architecture Overview

```
AgentCore Conversation → Memory Trigger → SNS → Lambda → Bedrock LLM → Memory Storage
                                        ↓
                                    S3 Bucket (payload storage)
```

## Quick Start

```bash
# 1. Install dependencies
make install

# 2. Deploy infrastructure
make deploy-infra

# 3. Create memory resource
make create-memory

# 4. Deploy Lambda function
make update-lambda-code

# 5. Start development server
make dev

# 6. Test (in another terminal)
make test
```

---

# Deployment Guide

## Prerequisites

- **AWS Account** with appropriate permissions
- **AWS CLI** configured (`aws configure`)
- **Python 3.10+** environment (conda/venv recommended)
- **Bedrock Model Access** - Request access in AWS Console:
  - Navigate to AWS Bedrock Console → Model access
  - Request access to Claude 3 Haiku: `anthropic.claude-3-haiku-20240307-v1:0`
- **IAM Role** - Create memory execution role manually (see below)

### Create Memory Execution Role

Create an IAM role with the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "bedrock-agentcore:*",
      "bedrock-runtime:InvokeModel",
      "s3:GetObject",
      "s3:PutObject",
      "sns:Publish"
    ],
    "Resource": "*"
  }]
}
```

Save the ARN - you'll need it for deployment.

---

## Step-by-Step Deployment

### Step 1: Install Dependencies

```bash
make install
```

**What it does:**
- Installs all Python dependencies from `pyproject.toml`
- Installs `agentcore` CLI tool
- Installs `bedrock-agentcore`, `strands-agents`, and other required packages

**Verify:** Run `agentcore --version` to confirm installation

---

### Step 2: Deploy Infrastructure

```bash
# Set your memory execution role ARN
export MEMORY_EXEC_ROLE_ARN=arn:aws:iam::YOUR_ACCOUNT:role/agentcore-memory-role

make deploy-infra
```

**What it does:**
- Deploys CloudFormation stack with:
  - S3 bucket for memory event payloads
  - SNS topic for memory notifications
  - Lambda function for processing memories
  - IAM roles and permissions

**Output:** Note the S3 bucket name and SNS topic ARN from the output

---

### Step 3: Create AgentCore Memory

```bash
make create-memory
```

**What it does:**
- Checks if a memory already exists (reuses existing if found)
- Creates a self-managed memory resource in AgentCore if needed
- Configures memory settings:
  - **Trigger**: After 2 messages (`messageBasedTrigger`)
  - **Context Window**: Last 20 messages (`historicalContextWindowSize`)
  - **Event Expiry**: 30 days
  - **SNS Topic**: Links to the topic created in Step 2
  - **S3 Bucket**: Links to the bucket for payload storage
- Saves Memory ID to `.memory_id` file for reuse

**Output:** Memory ID is saved automatically (e.g., `UserInfoSelfManagedMemory-ABC123`)

**Note:** The script (`scripts/setup_memory.py`) is idempotent - it will reuse an existing memory if one is found with the pattern `UserInfoSelfManagedMemory-*`

---

### Step 4: Deploy Lambda Function

```bash
make update-lambda-code
```

**What it does:**
- Packages Lambda function code from `functions/memory_processor/app.py`
- Installs dependencies for Lambda runtime
- Deploys to AWS Lambda
- Sets environment variables (Memory ID, Model ID)

**Verify:** Check Lambda function in AWS Console

---

### Step 5: Start Development Server

```bash
make dev
```

**What it does:**
- Automatically sets up environment variables (if not already done)
- Reads Memory ID from `.memory_id` file
- Starts AgentCore development server on port 8081
- Enables hot reloading for code changes

**Output:** Server runs at `http://localhost:8081/invocations`

**Keep this terminal open** - the server runs in the foreground

**Note:** The agent reads `BEDROCK_AGENTCORE_MEMORY_ID` from the environment to know which memory to use.

---

### Step 6: Test the Agent

In a **new terminal**, run:

```bash
make test
```

**What it does:**
- Sends test messages to the agent
- Tests user info extraction (name, SSN filtering)
- Verifies memory storage
- Checks memory retrieval

**Expected behavior:**
- Agent responds to queries
- After 2 messages, Lambda is triggered
- User info is extracted and stored
- Agent can recall stored information

---

## Additional Commands

### List Existing Memories

```bash
make list-memories
```

Shows all AgentCore memories in your account.

### Check Memory Contents

```bash
# Automatically uses Memory ID from .memory_id file
make check-memory

# Or specify a different Memory ID
make check-memory MEMORY_ID=UserInfoSelfManagedMemory-ABC123
```

Inspects what's stored in a specific memory. Useful for debugging.

**Note:** If you don't provide `MEMORY_ID`, it automatically reads from `.memory_id` file.

### Test Memory Operations

```bash
make test-memory
```

Writes test records and verifies memory storage/retrieval.

### Clean Up

```bash
make clean
```

**Warning:** Deletes the CloudFormation stack and all resources.

---

# Project Structure

```
userinfoagent/
├── functions/memory_processor/    # Lambda function
│   ├── app.py                     # Handler code
│   └── requirements.txt           # Lambda dependencies
├── infra/cloudformation/          # Infrastructure as Code
│   ├── template.yaml              # CloudFormation template
│   └── deploy.sh                  # Deployment script
├── scripts/                       # Operational scripts
│   ├── setup_memory.py            # Create AgentCore memory
│   ├── deploy_lambda.py           # Deploy Lambda function
│   ├── test_memory.py             # Test memory operations
│   └── check_memory.py            # Debug memory contents
├── src/                           # AgentCore agent code
│   ├── main.py                    # Agent entry point (reads BEDROCK_AGENTCORE_MEMORY_ID)
│   ├── mcp_client/                # MCP integration
│   └── model/                     # Model configuration
├── test/                          # Unit tests
├── .memory_id                     # Saved Memory ID (auto-generated)
├── .agentcore_env                 # Environment variables (auto-generated)
├── Makefile                       # Build automation
├── pyproject.toml                 # Python packaging
├── requirements.txt               # Dependencies
└── README.md                      # This file
```

---

# How It Works

## Memory Trigger Flow

1. **User interacts** with AgentCore agent
2. **After 2 messages**, memory trigger fires
3. **AgentCore** publishes event to SNS topic
4. **SNS** stores conversation payload in S3
5. **SNS** invokes Lambda function
6. **Lambda** downloads payload from S3
7. **Lambda** extracts facts using Bedrock LLM
8. **Lambda** stores facts in AgentCore memory
9. **Agent** can now recall stored information

## Lambda Function Logic

The Lambda function (`functions/memory_processor/app.py`):

1. Parses SNS notification
2. Downloads conversation from S3
3. Builds transcript from historical + current context
4. Invokes Bedrock LLM to extract facts
5. Filters sensitive data (SSN, passwords)
6. Stores facts as memory records

## Memory Configuration

- **Trigger**: After 2 messages (`messageBasedTrigger`)
- **Context Window**: Last 20 messages
- **Storage**: Key-value pairs in AgentCore memory
- **Namespace**: `/` (root namespace)
- **Expiry**: 30 days

---

# Troubleshooting

## Common Issues

**Lambda not triggered:**
- Check SNS subscription in AWS Console
- Verify Lambda has permission to be invoked by SNS

**S3 access denied:**
- Verify Lambda execution role has `s3:GetObject` permission
- Check S3 bucket policy

**Bedrock errors:**
- Confirm model access is granted in Bedrock Console
- Verify model ID: `anthropic.claude-3-haiku-20240307-v1:0`
- Check region availability (us-east-1 recommended)

**Memory storage fails:**
- Verify Memory ID is correct
- Check Lambda environment variables
- Review CloudWatch logs: `aws logs tail /aws/lambda/memory-processor --follow`

**agentcore command not found:**
- Run `hash -r` to refresh shell PATH
- Restart terminal/shell
- Verify installation: `pip show bedrock-agentcore-starter-toolkit`

---

# License

Apache 2.0 - See LICENSE file

# Contributing

See CONTRIBUTING.md for guidelines

# Code of Conduct

See CODE_OF_CONDUCT.md
