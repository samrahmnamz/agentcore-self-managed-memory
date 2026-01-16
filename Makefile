.PHONY: help install deploy-infra create-memory update-lambda clean dev test update-lambda-code get-stack-outputs list-memories setup-env

# Configuration
MEMORY_EXEC_ROLE_ARN := arn:aws:iam::084375560447:role/agentcore-memory-role

# Default target
help:
	@echo "User Info Agent Deployment"
	@echo "=========================="
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Python 3.10+ environment (conda/venv)"
	@echo "  2. Run 'make install' to install dependencies"
	@echo "  3. Create memory execution role manually with proper permissions"
	@echo "  4. Set MEMORY_EXEC_ROLE_ARN environment variable"
	@echo ""
	@echo "Targets:"
	@echo "  install       - Install project dependencies"
	@echo "  deploy-infra  - Deploy CloudFormation infrastructure"
	@echo "  get-stack-outputs - Get CloudFormation outputs and set env vars"
	@echo "  list-memories - List existing memories"
	@echo "  setup-env     - Setup environment variables file"
	@echo "  create-memory - Create self-managed memory"
	@echo "  update-lambda - Update Lambda with memory ID (requires MEMORY_ID)"
	@echo "  update-lambda-code - Update Lambda function code from lambda_function.py"
	@echo "  dev           - Start agent in development mode"
	@echo "  test          - Test agent with sample user info extraction"
	@echo "  clean         - Delete CloudFormation stack"
	@echo "  all           - Run complete deployment (infra + memory)"

# Install dependencies
install:
	@echo "Installing project dependencies..."
	pip install -e .
	@echo "✓ Dependencies installed"
	@echo "Verifying agentcore CLI..."
	@which agentcore && agentcore --version || echo "⚠️  agentcore not found. Try: hash -r"
	@echo "Verifying agentcore CLI..."
	@which agentcore || echo "⚠️  agentcore not in PATH. You may need to restart your shell."

# Deploy CloudFormation infrastructure
deploy-infra:
	@echo "Deploying CloudFormation infrastructure..."
	cd infra/cloudformation && ./deploy.sh
	@echo ""
	@echo "Next steps:"
	@echo "1. Set environment variables from output above"
	@echo "2. Run: make create-memory"

# List existing memories
list-memories:
	@python -c "import boto3; client = boto3.client('bedrock-agentcore-control', region_name='us-east-1'); memories = client.list_memories().get('memories', []); print(f'Found {len(memories)} memories:'); [print(f'ID: {m.get(\"id\", \"N/A\")}, Keys: {list(m.keys())}') for m in memories]"

# Test memory operations
test-memory:
	@echo "Testing memory operations..."
	export MEMORY_EXEC_ROLE_ARN=$(MEMORY_EXEC_ROLE_ARN) && \
	export MEMORY_EVENTS_BUCKET=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsBucket`].OutputValue' --output text) && \
	export MEMORY_EVENTS_TOPIC_ARN=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsTopicArn`].OutputValue' --output text) && \
	MEMORY_ID=$$(python scripts/setup_memory.py) && \
	python scripts/test_memory.py $$MEMORY_ID

# Create self-managed memory
create-memory:
	export MEMORY_EXEC_ROLE_ARN=$(MEMORY_EXEC_ROLE_ARN) && \
	export MEMORY_EVENTS_BUCKET=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsBucket`].OutputValue' --output text) && \
	export MEMORY_EVENTS_TOPIC_ARN=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsTopicArn`].OutputValue' --output text) && \
	echo "Creating self-managed memory..." && \
	MEMORY_ID=$$(python scripts/setup_memory.py) && \
	echo "Memory ID: $$MEMORY_ID" && \
	echo "✓ Memory ready" && \
	echo "Run: make update-lambda MEMORY_ID=$$MEMORY_ID"



# Update Lambda function code
update-lambda-code:
	@echo "Updating Lambda function code..."
	export MEMORY_EXEC_ROLE_ARN=$(MEMORY_EXEC_ROLE_ARN) && \
	export MEMORY_EVENTS_BUCKET=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsBucket`].OutputValue' --output text) && \
	export MEMORY_EVENTS_TOPIC_ARN=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsTopicArn`].OutputValue' --output text) && \
	MEMORY_ID=$$(python scripts/setup_memory.py) && \
	python scripts/deploy_lambda.py $$MEMORY_ID
	@echo "✓ Lambda code updated successfully"

# Clean up - delete CloudFormation stack
clean:
	@echo "Deleting CloudFormation stack..."
	aws cloudformation delete-stack --stack-name userinfoagent-memory-infrastructure --region us-east-1
	@echo "Stack deletion initiated. Check AWS console for status."

# Setup environment variables file
setup-env: create-memory
	@echo "Setting up environment variables..."
	@echo "export MEMORY_EXEC_ROLE_ARN=$(MEMORY_EXEC_ROLE_ARN)" > .agentcore_env
	@echo "export MEMORY_EVENTS_BUCKET=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsBucket`].OutputValue' --output text)" >> .agentcore_env
	@echo "export MEMORY_EVENTS_TOPIC_ARN=$$(aws cloudformation describe-stacks --stack-name userinfoagent-memory-infrastructure-02 --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`MemoryEventsTopicArn`].OutputValue' --output text)" >> .agentcore_env
	@echo "export BEDROCK_AGENTCORE_MEMORY_ID=UserInfoSelfManagedMemory-Vi7ki5GF4T" >> .agentcore_env
	@echo "✓ Environment variables written to .agentcore_env file"

# Complete deployment (infrastructure + memory creation)
all: deploy-infra
	@echo ""
	@echo "Infrastructure deployed. Please:"
	@echo "1. Set the environment variables shown above"
	@echo "2. Run: make create-memory"
	@echo "3. Run: make update-lambda-code MEMORY_ID=<your-memory-id>"


# Development target - start the agent
dev: setup-env
	@echo "Starting agent in development mode..."
	@bash -c "source .agentcore_env && agentcore dev --port 8081"

# Test agent with sample invocations
test:
	@echo "Testing agent with sample user info extraction..."
	@echo "Make sure the agent is running (make dev) in another terminal"
	@SESSION_ID="session-$(shell date +%Y%m%d)" && echo "Using session: $$SESSION_ID" && \
	echo "" && \
	echo "Test 1: Name extraction" && \
	agentcore invoke --dev '{"prompt": "Hi, my name is john gro", "session_id": "'$$SESSION_ID'"}' --port 8081 && \
	echo "" && \
	echo "Test 2: SSN extraction" && \
	agentcore invoke --dev '{"prompt": "My SSN is 123-45-2231", "session_id": "'$$SESSION_ID'"}' --port 8081 && \
	echo "" && \
	echo "Test 3: set dog" && \
	agentcore invoke --dev '{"prompt": "I have a frog named frogo.", "session_id": "'$$SESSION_ID'"}' --port 8081 && \
	echo "" && \
	echo "Test 4: Check extracted info" && \
	agentcore invoke --dev '{"prompt": "What information do you have about me?", "session_id": "'$$SESSION_ID'"}' --port 8081

# Test with new session using agentcore invoke
test-new-session:
	@echo "Testing agent with new session..."
	@SESSION_ID="session-$(shell date +%Y%m%d)" && echo "Using session: $$SESSION_ID" && \
	../.env3/bin/agentcore invoke --dev '{"prompt": "Hi, I am Jane Doe from the new session", "session_id": "'$$SESSION_ID'"}' --port 8081 && \
	echo "" && \
	../.env3/bin/agentcore invoke --dev '{"prompt": "My phone number is 555-9999", "session_id": "'$$SESSION_ID'"}' --port 8081
