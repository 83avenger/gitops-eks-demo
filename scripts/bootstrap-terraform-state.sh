#!/usr/bin/env bash
# =============================================================================
# Bootstrap Terraform Remote State (S3 + DynamoDB)
# Run ONCE before any terraform commands
# Usage: ./scripts/bootstrap-terraform-state.sh
# =============================================================================

set -euo pipefail

PROJECT_NAME="gitops-demo"
REGION="ap-southeast-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}"
DYNAMO_TABLE="${PROJECT_NAME}-terraform-locks"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bootstrapping Terraform Remote State"
echo "  Account  : ${ACCOUNT_ID}"
echo "  Region   : ${REGION}"
echo "  S3 Bucket: ${BUCKET_NAME}"
echo "  DynamoDB : ${DYNAMO_TABLE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# S3 bucket for state storage
echo "▶ Creating S3 bucket..."
aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  $([ "${REGION}" != "ap-southeast-1" ] && echo "--create-bucket-configuration LocationConstraint=${REGION}" || echo "")

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable access logging
LOGGING_BUCKET="${BUCKET_NAME}-logs"
aws s3api create-bucket \
  --bucket "${LOGGING_BUCKET}" \
  --region "${REGION}" \
  $([ "${REGION}" != "ap-southeast-1" ] && echo "--create-bucket-configuration LocationConstraint=${REGION}" || echo "") || true

aws s3api put-bucket-logging \
  --bucket "${BUCKET_NAME}" \
  --bucket-logging-status "{
    \"LoggingEnabled\": {
      \"TargetBucket\": \"${LOGGING_BUCKET}\",
      \"TargetPrefix\": \"terraform-state-logs/\"
    }
  }"

# DynamoDB for state locking
echo "▶ Creating DynamoDB lock table..."
aws dynamodb create-table \
  --table-name "${DYNAMO_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}" \
  --tags Key=Project,Value="${PROJECT_NAME}" Key=ManagedBy,Value=bootstrap \
  2>/dev/null || echo "  DynamoDB table already exists"

# Enable point-in-time recovery
aws dynamodb update-continuous-backups \
  --table-name "${DYNAMO_TABLE}" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region "${REGION}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Terraform state backend ready!"
echo ""
echo "Update your backend config in terraform/environments/*/:"
echo ""
echo '  backend "s3" {'
echo "    bucket         = \"${BUCKET_NAME}\""
echo '    key            = "dev/terraform.tfstate"'
echo "    region         = \"${REGION}\""
echo '    encrypt        = true'
echo "    dynamodb_table = \"${DYNAMO_TABLE}\""
echo '  }'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
