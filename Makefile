.PHONY: help install build deploy test clean layer local-test clean-all stack-status stack-events delete-stack-only

# Default environment
ENV ?= dev
AWS_REGION ?= ap-northeast-1
AWS_PROFILE ?=
STACK_NAME = lambda-deploy-$(ENV)

# AWS CLI profile option
ifdef AWS_PROFILE
	AWS_PROFILE_FLAG = --profile $(AWS_PROFILE)
else
	AWS_PROFILE_FLAG =
endif

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install Python dependencies
	pip install -r src/lambda/requirements.txt

layer: ## Create Lambda layer (optimized)
	@if command -v docker > /dev/null 2>&1; then \
		echo "Using Docker to build layer with Python 3.11..."; \
		./scripts/create_layer_docker.sh; \
	else \
		echo "Docker not found. Using local Python..."; \
		./scripts/create_layer.sh; \
	fi

layer-local: ## Create Lambda layer using local Python
	./scripts/create_layer.sh

layer-docker: ## Create Lambda layer using Docker (Python 3.11)
	./scripts/create_layer_docker.sh

force-layer: ## Force recreate Lambda layer (ignore cache)
	rm -f .layer_hash requests-layer.zip
	@if command -v docker > /dev/null 2>&1; then \
		./scripts/create_layer_docker.sh; \
	else \
		./scripts/create_layer.sh; \
	fi

layer-info: ## Show layer information
	@if [ -f "requests-layer.zip" ]; then \
		echo "Layer file: requests-layer.zip"; \
		echo "Layer size: $$(du -h requests-layer.zip | cut -f1)"; \
		if [ -f ".layer_hash" ]; then \
			echo "Layer hash: $$(cat .layer_hash)"; \
		fi; \
	else \
		echo "Layer not found. Run 'make layer' to create it."; \
	fi

build: layer ## Build SAM application
	@if command -v docker > /dev/null 2>&1; then \
		echo "Building SAM application with Docker (Python 3.11)..."; \
		sam build --template-file infrastructure/template.yaml --use-container; \
	else \
		echo "Building SAM application with local Python..."; \
		sam build --template-file infrastructure/template.yaml; \
	fi

deploy: build ## Deploy to AWS
	@if [ -z "$(CLOUDFORMATION_ROLE_ARN)" ]; then \
		echo "Warning: CLOUDFORMATION_ROLE_ARN not set. Deploying without service role."; \
		sam deploy \
			--stack-name $(STACK_NAME) \
			--parameter-overrides Environment=$(ENV) \
			--capabilities CAPABILITY_IAM \
			--region $(AWS_REGION) \
			--resolve-s3 \
			--no-confirm-changeset \
			--no-fail-on-empty-changeset; \
	else \
		echo "Deploying with CloudFormation service role: $(CLOUDFORMATION_ROLE_ARN)"; \
		sam deploy \
			--stack-name $(STACK_NAME) \
			--parameter-overrides Environment=$(ENV) \
			--capabilities CAPABILITY_IAM \
			--role-arn $(CLOUDFORMATION_ROLE_ARN) \
			--region $(AWS_REGION) \
			--resolve-s3 \
			--no-confirm-changeset \
			--no-fail-on-empty-changeset; \
	fi

test: ## Test Lambda function
	@echo "Testing Lambda function..."
	@FUNCTION_NAME=$$(aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query 'Stacks[0].Outputs[?OutputKey==`LambdaFunction`].OutputValue' \
		--output text \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG)); \
	aws lambda invoke \
		--function-name $$FUNCTION_NAME \
		--payload '{"url": "https://httpbin.org/json"}' \
		--cli-binary-format raw-in-base64-out \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) \
		response.json > /dev/null
	@echo ""
	@echo "Lambda Response:"
	@python3 -m json.tool < response.json

local-test: build ## Test Lambda function locally
	sam local invoke SimpleLambdaFunction -e tests/test-event.json -t .aws-sam/build/template.yaml

clean: ## Clean build artifacts
	rm -rf .aws-sam/
	rm -rf layer/
	rm -f requests-layer.zip
	rm -f .layer_hash
	rm -f response.json

delete-stack-only: ## Delete application stack only (keep SAM managed resources for reuse)
	@if [ -z "$(CLOUDFORMATION_ROLE_ARN)" ]; then \
		echo "Warning: CLOUDFORMATION_ROLE_ARN not set. Deleting without service role."; \
		aws cloudformation delete-stack --stack-name $(STACK_NAME) --region $(AWS_REGION) $(AWS_PROFILE_FLAG); \
	else \
		echo "Deleting stack with CloudFormation service role: $(CLOUDFORMATION_ROLE_ARN)"; \
		aws cloudformation delete-stack \
			--stack-name $(STACK_NAME) \
			--role-arn $(CLOUDFORMATION_ROLE_ARN) \
			--region $(AWS_REGION) $(AWS_PROFILE_FLAG); \
	fi
	@echo "Stack deletion initiated. Waiting for completion..."
	@aws cloudformation wait stack-delete-complete \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) || true
	@echo ""
	@echo "Application stack deleted successfully!"
	@echo "Note: SAM managed resources (S3 bucket and stack) are kept for reuse."
	@echo "      To delete everything including SAM managed resources, use 'make delete-stack'"

delete-stack: ## Delete ALL stacks and S3 buckets (complete cleanup)
	@if [ -z "$(CLOUDFORMATION_ROLE_ARN)" ]; then \
		echo "Warning: CLOUDFORMATION_ROLE_ARN not set. Deleting without service role."; \
		aws cloudformation delete-stack --stack-name $(STACK_NAME) --region $(AWS_REGION) $(AWS_PROFILE_FLAG); \
	else \
		echo "Deleting stack with CloudFormation service role: $(CLOUDFORMATION_ROLE_ARN)"; \
		aws cloudformation delete-stack \
			--stack-name $(STACK_NAME) \
			--role-arn $(CLOUDFORMATION_ROLE_ARN) \
			--region $(AWS_REGION) $(AWS_PROFILE_FLAG); \
	fi
	@echo "Stack deletion initiated. Waiting for completion..."
	@aws cloudformation wait stack-delete-complete \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) || true
	@echo ""
	@echo "Deleting SAM managed S3 buckets..."
	@aws s3 ls $(AWS_PROFILE_FLAG) | grep aws-sam-cli-managed-default | awk '{print $$3}' | while read bucket; do \
		if [ -n "$$bucket" ]; then \
			if [ -n "$(AWS_PROFILE)" ]; then \
				bash scripts/empty_bucket.sh "$$bucket" $(AWS_PROFILE) || true; \
			else \
				bash scripts/empty_bucket.sh "$$bucket" || true; \
			fi; \
			echo "  Deleting bucket: $$bucket"; \
			aws s3 rb s3://"$$bucket" $(AWS_PROFILE_FLAG) 2>/dev/null || true; \
		fi; \
	done || echo "No SAM managed buckets found."
	@echo ""
	@echo "Deleting SAM managed CloudFormation stack..."
	@aws cloudformation delete-stack \
		--stack-name aws-sam-cli-managed-default \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) 2>/dev/null || true
	@echo "Waiting for SAM managed stack deletion..."
	@aws cloudformation wait stack-delete-complete \
		--stack-name aws-sam-cli-managed-default \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) 2>/dev/null || true
	@echo ""
	@echo "All stacks and S3 buckets deleted successfully!"

clean-all: delete-stack ## Alias for delete-stack (delete stack and all AWS managed resources)
	@echo ""
	@echo "Note: The following resources are NOT deleted (manual deletion required if needed):"
	@echo "  - CloudFormationServiceRole (IAM Role - no cost)"
	@echo "  - Local developer IAM user (no cost)"
	@echo "  - GitHub Actions IAM role (no cost)"

stack-status: ## Show CloudFormation stack status
	@aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) \
		--query 'Stacks[0].[StackName,StackStatus,StackStatusReason]' \
		--output table || echo "Stack $(STACK_NAME) does not exist"

stack-events: ## Show recent CloudFormation stack events (useful for debugging failures)
	@aws cloudformation describe-stack-events \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) $(AWS_PROFILE_FLAG) \
		--max-items 20 \
		--query 'StackEvents[].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
		--output table || echo "Stack $(STACK_NAME) does not exist"