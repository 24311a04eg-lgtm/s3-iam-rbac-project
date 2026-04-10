#!/usr/bin/env bash
# =============================================================================
# setup-s3.sh — Create and configure the secure-corp-storage S3 bucket
# =============================================================================
# Usage: ./scripts/setup-s3.sh
# Prerequisites: AWS CLI configured, run setup-iam.sh first
# =============================================================================
set -euo pipefail

BUCKET_NAME="secure-corp-storage"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=========================================================="
echo " S3 IAM RBAC Setup — S3 Bucket Configuration"
echo " Bucket: ${BUCKET_NAME} | Region: ${REGION}"
echo "=========================================================="

# ------------------------------------------------------------------
# 1. Create the bucket
# ------------------------------------------------------------------
echo ""
echo "[1/6] Creating S3 bucket..."

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "  ✅ Bucket ${BUCKET_NAME} already exists — skipping creation"
else
  # us-east-1 does NOT use --create-bucket-configuration
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}"
  echo "  ✅ Created bucket: ${BUCKET_NAME}"
fi

# ------------------------------------------------------------------
# 2. Block all public access
# ------------------------------------------------------------------
echo ""
echo "[2/6] Blocking all public access..."

aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "  ✅ All public access blocked"

# ------------------------------------------------------------------
# 3. Enable versioning
# ------------------------------------------------------------------
echo ""
echo "[3/6] Enabling versioning..."

aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
echo "  ✅ Versioning enabled"

# ------------------------------------------------------------------
# 4. Enable default encryption (SSE-S3 / AES-256)
# ------------------------------------------------------------------
echo ""
echo "[4/6] Enabling default encryption (SSE-S3)..."

aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'
echo "  ✅ SSE-S3 encryption enabled"

# ------------------------------------------------------------------
# 5. Configure lifecycle policy
# ------------------------------------------------------------------
echo ""
echo "[5/6] Applying lifecycle policy..."

aws s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET_NAME}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "DataLifecycle",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 60,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 90,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ],
      "Expiration": {
        "Days": 120
      },
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }]
  }'
echo "  ✅ Lifecycle policy applied"
echo "     Day 0:  Standard storage"
echo "     Day 30: Infrequent Access"
echo "     Day 60: Glacier"
echo "     Day 90: Deep Archive"
echo "     Day 120: Delete"

# ------------------------------------------------------------------
# 6. Upload sample test files
# ------------------------------------------------------------------
echo ""
echo "[6/6] Uploading sample test files..."

for i in 1 2 3; do
  echo "Sample report ${i} - created $(date)" > "/tmp/report${i}.txt"
  aws s3 cp "/tmp/report${i}.txt" "s3://${BUCKET_NAME}/report${i}.txt"
  echo "  ✅ Uploaded report${i}.txt"
  rm -f "/tmp/report${i}.txt"
done

echo "  ✅ Sample files uploaded"

# Show bucket contents
echo ""
echo "Bucket contents:"
aws s3 ls "s3://${BUCKET_NAME}/"

echo ""
echo "=========================================================="
echo " ✅ S3 setup complete!"
echo "    Bucket:     ${BUCKET_NAME}"
echo "    Region:     ${REGION}"
echo "    Versioning: Enabled"
echo "    Encryption: SSE-S3 (AES-256)"
echo "    Public Access: Blocked"
echo "    Lifecycle:  Standard→IA(30d)→Glacier(60d)→Deep Archive(90d)→Delete(120d)"
echo "=========================================================="
