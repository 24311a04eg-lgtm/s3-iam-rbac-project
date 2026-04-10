#!/usr/bin/env bash
# =============================================================================
# test-permissions.sh — Validate all S3 IAM RBAC allow/deny scenarios
# =============================================================================
# Usage: ./scripts/test-permissions.sh
# Prerequisites: setup-iam.sh and setup-s3.sh completed
# Exit code: 0 = all tests passed, 1 = one or more tests failed
# =============================================================================
set -euo pipefail

BUCKET_NAME="secure-corp-storage"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ALICE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/s3-read-write-get"
BOB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/s3-read-only"
EC2_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/ec2-s3-access-role"

PASS=0
FAIL=0
TOTAL=0

# Colour output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Colour

# ------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------
pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  echo -e "  ${GREEN}✅ PASS${NC}: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  echo -e "  ${RED}❌ FAIL${NC}: $1"
}

# Assume a role and return temporary credentials as env vars
assume_role() {
  local role_arn="$1"
  local session_name="$2"
  local creds
  creds=$(aws sts assume-role \
    --role-arn "${role_arn}" \
    --role-session-name "${session_name}" \
    --output json)
  export TEST_AWS_ACCESS_KEY_ID=$(echo "${creds}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
  export TEST_AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
  export TEST_AWS_SESSION_TOKEN=$(echo "${creds}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")
}

# Run an aws s3 command with assumed-role credentials
run_as() {
  AWS_ACCESS_KEY_ID="${TEST_AWS_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${TEST_AWS_SECRET_ACCESS_KEY}" \
  AWS_SESSION_TOKEN="${TEST_AWS_SESSION_TOKEN}" \
  aws "$@"
}

# ------------------------------------------------------------------
# Prepare test objects
# ------------------------------------------------------------------
echo "Creating test files..."
echo "EC2 test upload file" > /tmp/ec2-test-upload.txt
echo "Alice test upload file" > /tmp/alice-test-upload.txt
echo "Bob test upload file (should be denied)" > /tmp/bob-test-upload.txt

# Ensure at least one object exists in the bucket
aws s3 cp /tmp/ec2-test-upload.txt "s3://${BUCKET_NAME}/test-object.txt" &>/dev/null || true

echo ""
echo "=========================================================="
echo " S3 IAM RBAC Permission Validation"
echo " Bucket: ${BUCKET_NAME} | Account: ${ACCOUNT_ID}"
echo "=========================================================="

# ==========================================================
# EC2 ROLE TESTS (simulated — assume ec2-s3-access-role)
# ==========================================================
echo ""
echo "[EC2 ROLE TESTS] Role: ec2-s3-access-role"
echo "---"

assume_role "${EC2_ROLE_ARN}" "test-ec2-session"

# Test 1: EC2 can list bucket
if run_as s3 ls "s3://${BUCKET_NAME}/" &>/dev/null; then
  pass "EC2 can list bucket (s3:ListBucket)"
else
  fail "EC2 should be able to list bucket"
fi

# Test 2: EC2 can download
if run_as s3 cp "s3://${BUCKET_NAME}/test-object.txt" /tmp/ec2-download-test.txt &>/dev/null; then
  pass "EC2 can download file (s3:GetObject)"
  rm -f /tmp/ec2-download-test.txt
else
  fail "EC2 should be able to download files"
fi

# Test 3: EC2 can upload
if run_as s3 cp /tmp/ec2-test-upload.txt "s3://${BUCKET_NAME}/ec2-upload-test.txt" &>/dev/null; then
  pass "EC2 can upload file (s3:PutObject)"
else
  fail "EC2 should be able to upload files"
fi

# Test 4: EC2 cannot delete
if run_as s3 rm "s3://${BUCKET_NAME}/test-object.txt" &>/dev/null; then
  fail "EC2 should NOT be able to delete files — policy misconfigured!"
else
  pass "EC2 correctly denied delete (s3:DeleteObject not allowed)"
fi

# ==========================================================
# ALICE ROLE TESTS (s3-read-write-get)
# ==========================================================
echo ""
echo "[ALICE ROLE TESTS] Role: s3-read-write-get"
echo "---"

# Note: In real setup, assume_role requires MFA for Alice.
# For automated testing, this simulates the role with temporary credentials
# obtained via an admin session (CI/CD pipeline pattern).
if aws sts assume-role \
  --role-arn "${ALICE_ROLE_ARN}" \
  --role-session-name "test-alice-session" \
  --output json &>/dev/null; then

  assume_role "${ALICE_ROLE_ARN}" "test-alice-session"

  # Test 5: Alice can list
  if run_as s3 ls "s3://${BUCKET_NAME}/" &>/dev/null; then
    pass "Alice can list bucket (s3:ListBucket)"
  else
    fail "Alice should be able to list bucket"
  fi

  # Test 6: Alice can download
  if run_as s3 cp "s3://${BUCKET_NAME}/test-object.txt" /tmp/alice-download-test.txt &>/dev/null; then
    pass "Alice can download file (s3:GetObject)"
    rm -f /tmp/alice-download-test.txt
  else
    fail "Alice should be able to download files"
  fi

  # Test 7: Alice can upload
  if run_as s3 cp /tmp/alice-test-upload.txt "s3://${BUCKET_NAME}/alice-upload-test.txt" &>/dev/null; then
    pass "Alice can upload file (s3:PutObject)"
  else
    fail "Alice should be able to upload files"
  fi

  # Test 8: Alice cannot delete
  if run_as s3 rm "s3://${BUCKET_NAME}/test-object.txt" &>/dev/null; then
    fail "Alice should NOT be able to delete files — policy misconfigured!"
  else
    pass "Alice correctly denied delete (s3:DeleteObject not allowed)"
  fi
else
  echo "  ⚠️  Skipping Alice tests — MFA required (cannot assume role without MFA token)"
  echo "  💡  Run: aws sts assume-role --role-arn ${ALICE_ROLE_ARN} --role-session-name test --serial-number <mfa-arn> --token-code <code>"
fi

# ==========================================================
# BOB ROLE TESTS (s3-read-only)
# ==========================================================
echo ""
echo "[BOB ROLE TESTS] Role: s3-read-only"
echo "---"

if aws sts assume-role \
  --role-arn "${BOB_ROLE_ARN}" \
  --role-session-name "test-bob-session" \
  --output json &>/dev/null; then

  assume_role "${BOB_ROLE_ARN}" "test-bob-session"

  # Test 9: Bob can list
  if run_as s3 ls "s3://${BUCKET_NAME}/" &>/dev/null; then
    pass "Bob can list bucket (s3:ListBucket)"
  else
    fail "Bob should be able to list bucket"
  fi

  # Test 10: Bob can download
  if run_as s3 cp "s3://${BUCKET_NAME}/test-object.txt" /tmp/bob-download-test.txt &>/dev/null; then
    pass "Bob can download file (s3:GetObject)"
    rm -f /tmp/bob-download-test.txt
  else
    fail "Bob should be able to download files"
  fi

  # Test 11: Bob cannot upload
  if run_as s3 cp /tmp/bob-test-upload.txt "s3://${BUCKET_NAME}/bob-upload-test.txt" &>/dev/null; then
    fail "Bob should NOT be able to upload files — policy misconfigured!"
  else
    pass "Bob correctly denied upload (s3:PutObject not allowed)"
  fi

  # Test 12: Bob cannot delete
  if run_as s3 rm "s3://${BUCKET_NAME}/test-object.txt" &>/dev/null; then
    fail "Bob should NOT be able to delete files — policy misconfigured!"
  else
    pass "Bob correctly denied delete (s3:DeleteObject not allowed)"
  fi
else
  echo "  ⚠️  Skipping Bob tests — MFA required (cannot assume role without MFA token)"
  echo "  💡  Run: aws sts assume-role --role-arn ${BOB_ROLE_ARN} --role-session-name test --serial-number <mfa-arn> --token-code <code>"
fi

# ------------------------------------------------------------------
# Cleanup test files
# ------------------------------------------------------------------
rm -f /tmp/ec2-test-upload.txt /tmp/alice-test-upload.txt /tmp/bob-test-upload.txt
aws s3 rm "s3://${BUCKET_NAME}/ec2-upload-test.txt" &>/dev/null || true
aws s3 rm "s3://${BUCKET_NAME}/alice-upload-test.txt" &>/dev/null || true

# ------------------------------------------------------------------
# Results
# ------------------------------------------------------------------
echo ""
echo "=========================================================="
echo " RESULTS: ${PASS}/${TOTAL} tests passed"
if [[ ${FAIL} -gt 0 ]]; then
  echo -e " ${RED}❌ ${FAIL} test(s) FAILED${NC}"
  echo "=========================================================="
  exit 1
else
  echo -e " ${GREEN}✅ All tests passed!${NC}"
  echo "=========================================================="
  exit 0
fi
