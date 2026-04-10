#!/usr/bin/env bash
# =============================================================================
# setup-iam.sh — Create IAM users, roles, and policies for S3 RBAC project
# =============================================================================
# Usage: ./scripts/setup-iam.sh
# Prerequisites: AWS CLI configured with sufficient IAM permissions
# =============================================================================
set -euo pipefail

BUCKET_NAME="secure-corp-storage"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

echo "=========================================================="
echo " S3 IAM RBAC Setup — IAM Users, Roles & Policies"
echo " Account: ${ACCOUNT_ID} | Region: ${REGION}"
echo "=========================================================="

# ------------------------------------------------------------------
# Helper: check if a resource already exists before creating
# ------------------------------------------------------------------
user_exists()  { aws iam get-user --user-name "$1" &>/dev/null; }
role_exists()  { aws iam get-role --role-name "$1" &>/dev/null; }
policy_exists(){ aws iam get-role-policy --role-name "$1" --policy-name "$2" &>/dev/null; }

# ------------------------------------------------------------------
# 1. Create IAM Users
# ------------------------------------------------------------------
echo ""
echo "[1/6] Creating IAM users..."

if user_exists "Alice-developer"; then
  echo "  ✅ Alice-developer already exists — skipping"
else
  aws iam create-user --user-name Alice-developer
  echo "  ✅ Created user: Alice-developer"
fi

if user_exists "Bob-viewer"; then
  echo "  ✅ Bob-viewer already exists — skipping"
else
  aws iam create-user --user-name Bob-viewer
  echo "  ✅ Created user: Bob-viewer"
fi

# ------------------------------------------------------------------
# 2. Build trust policy files with real account ID
# ------------------------------------------------------------------
echo ""
echo "[2/6] Generating trust policies with Account ID ${ACCOUNT_ID}..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_DIR="${SCRIPT_DIR}/../iam-policies"

# EC2 trust policy (no substitution needed — uses service principal)
EC2_TRUST_POLICY="${POLICY_DIR}/trust-policy-ec2.json"

# Alice trust policy
ALICE_TRUST_POLICY=$(mktemp)
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" "${POLICY_DIR}/trust-policy-alice.json" > "${ALICE_TRUST_POLICY}"

# Bob trust policy
BOB_TRUST_POLICY=$(mktemp)
sed "s/ACCOUNT_ID/${ACCOUNT_ID}/g" "${POLICY_DIR}/trust-policy-bob.json" > "${BOB_TRUST_POLICY}"

echo "  ✅ Trust policies ready"

# ------------------------------------------------------------------
# 3. Create IAM Roles
# ------------------------------------------------------------------
echo ""
echo "[3/6] Creating IAM roles..."

# EC2 role
if role_exists "ec2-s3-access-role"; then
  echo "  ✅ ec2-s3-access-role already exists — skipping"
else
  aws iam create-role \
    --role-name ec2-s3-access-role \
    --assume-role-policy-document "file://${EC2_TRUST_POLICY}" \
    --description "Allows EC2 instances to access S3 (list, get, put — no delete)"
  echo "  ✅ Created role: ec2-s3-access-role"
fi

# Alice's role (s3-read-write-get)
if role_exists "s3-read-write-get"; then
  echo "  ✅ s3-read-write-get already exists — skipping"
else
  aws iam create-role \
    --role-name s3-read-write-get \
    --assume-role-policy-document "file://${ALICE_TRUST_POLICY}" \
    --description "Alice-developer: read + write access to secure-corp-storage (no delete)"
  echo "  ✅ Created role: s3-read-write-get"
fi

# Bob's role (s3-read-only)
if role_exists "s3-read-only"; then
  echo "  ✅ s3-read-only already exists — skipping"
else
  aws iam create-role \
    --role-name s3-read-only \
    --assume-role-policy-document "file://${BOB_TRUST_POLICY}" \
    --description "Bob-viewer: read-only access to secure-corp-storage"
  echo "  ✅ Created role: s3-read-only"
fi

# ------------------------------------------------------------------
# 4. Attach permission policies to roles
# ------------------------------------------------------------------
echo ""
echo "[4/6] Attaching permission policies to roles..."

# EC2 policy
if policy_exists "ec2-s3-access-role" "EC2S3AccessPolicy"; then
  echo "  ✅ EC2S3AccessPolicy already attached — skipping"
else
  aws iam put-role-policy \
    --role-name ec2-s3-access-role \
    --policy-name EC2S3AccessPolicy \
    --policy-document "file://${POLICY_DIR}/ec2-s3-access-policy.json"
  echo "  ✅ Attached EC2S3AccessPolicy to ec2-s3-access-role"
fi

# Alice's policy
if policy_exists "s3-read-write-get" "S3ReadWritePolicy"; then
  echo "  ✅ S3ReadWritePolicy already attached — skipping"
else
  aws iam put-role-policy \
    --role-name s3-read-write-get \
    --policy-name S3ReadWritePolicy \
    --policy-document "file://${POLICY_DIR}/s3-read-write-policy.json"
  echo "  ✅ Attached S3ReadWritePolicy to s3-read-write-get"
fi

# Bob's policy
if policy_exists "s3-read-only" "S3ReadOnlyPolicy"; then
  echo "  ✅ S3ReadOnlyPolicy already attached — skipping"
else
  aws iam put-role-policy \
    --role-name s3-read-only \
    --policy-name S3ReadOnlyPolicy \
    --policy-document "file://${POLICY_DIR}/s3-read-only-policy.json"
  echo "  ✅ Attached S3ReadOnlyPolicy to s3-read-only"
fi

# ------------------------------------------------------------------
# 5. Grant users permission to assume their roles
# ------------------------------------------------------------------
echo ""
echo "[5/6] Granting users permission to assume their roles..."

ALICE_ASSUME_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/s3-read-write-get"
  }]
}
EOF
)

BOB_ASSUME_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/s3-read-only"
  }]
}
EOF
)

aws iam put-user-policy \
  --user-name Alice-developer \
  --policy-name AssumeS3ReadWriteRole \
  --policy-document "${ALICE_ASSUME_POLICY}"
echo "  ✅ Alice can now assume s3-read-write-get"

aws iam put-user-policy \
  --user-name Bob-viewer \
  --policy-name AssumeS3ReadOnlyRole \
  --policy-document "${BOB_ASSUME_POLICY}"
echo "  ✅ Bob can now assume s3-read-only"

# ------------------------------------------------------------------
# 6. Create EC2 instance profile
# ------------------------------------------------------------------
echo ""
echo "[6/6] Creating EC2 instance profile..."

if aws iam get-instance-profile --instance-profile-name ec2-s3-access-profile &>/dev/null; then
  echo "  ✅ ec2-s3-access-profile already exists — skipping"
else
  aws iam create-instance-profile --instance-profile-name ec2-s3-access-profile
  aws iam add-role-to-instance-profile \
    --instance-profile-name ec2-s3-access-profile \
    --role-name ec2-s3-access-role
  echo "  ✅ Created instance profile: ec2-s3-access-profile"
fi

# Cleanup temp files
rm -f "${ALICE_TRUST_POLICY}" "${BOB_TRUST_POLICY}"

echo ""
echo "=========================================================="
echo " ✅ IAM setup complete!"
echo "    Users:   Alice-developer, Bob-viewer"
echo "    Roles:   ec2-s3-access-role, s3-read-write-get, s3-read-only"
echo "    Profile: ec2-s3-access-profile"
echo "=========================================================="
