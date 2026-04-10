#!/usr/bin/env bash
# =============================================================================
# cleanup.sh — Tear down all S3 IAM RBAC project resources
# =============================================================================
# Usage: ./scripts/cleanup.sh
# WARNING: This will DELETE all resources including the S3 bucket and its files!
# =============================================================================
set -euo pipefail

BUCKET_NAME="secure-corp-storage"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=========================================================="
echo " S3 IAM RBAC Cleanup — Remove All Resources"
echo " Account: ${ACCOUNT_ID} | Region: ${REGION}"
echo "=========================================================="
echo ""
echo -e "\033[0;31m⚠️  WARNING: This will PERMANENTLY DELETE:\033[0m"
echo "   - S3 bucket and ALL its contents (including versions)"
echo "   - IAM roles: ec2-s3-access-role, s3-read-write-get, s3-read-only"
echo "   - IAM users: Alice-developer, Bob-viewer"
echo "   - EC2 instances tagged 'Project=s3-iam-rbac'"
echo "   - ALB: secure-s3-alb"
echo ""
read -r -p "Type 'yes' to confirm cleanup: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Best-effort cleanup — errors are reported but do not stop execution
ERRORS=0

run_or_warn() {
  if ! "$@" 2>/dev/null; then
    echo "  ⚠️  Command failed (may not exist): $*"
    ERRORS=$((ERRORS + 1))
  fi
}

# ------------------------------------------------------------------
# 1. Empty and delete S3 bucket (including all versions)
# ------------------------------------------------------------------
echo ""
echo "[1/6] Emptying and deleting S3 bucket..."

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "  Removing all object versions and delete markers..."
  # Delete all versions
  aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
    --query "Versions[].{Key:Key,VersionId:VersionId}" \
    --output json 2>/dev/null | \
    python3 -c "
import sys, json, subprocess
versions = json.load(sys.stdin) or []
for v in versions:
    subprocess.run(['aws','s3api','delete-object',
        '--bucket','${BUCKET_NAME}',
        '--key',v['Key'],
        '--version-id',v['VersionId']], check=False)
    print(f'  Deleted version: {v[\"Key\"]} ({v[\"VersionId\"]})')
" || true

  # Delete all delete markers
  aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
    --query "DeleteMarkers[].{Key:Key,VersionId:VersionId}" \
    --output json 2>/dev/null | \
    python3 -c "
import sys, json, subprocess
markers = json.load(sys.stdin) or []
for m in markers:
    subprocess.run(['aws','s3api','delete-object',
        '--bucket','${BUCKET_NAME}',
        '--key',m['Key'],
        '--version-id',m['VersionId']], check=False)
    print(f'  Deleted marker: {m[\"Key\"]} ({m[\"VersionId\"]})')
" || true

  # Final delete of remaining objects
  aws s3 rm "s3://${BUCKET_NAME}/" --recursive 2>/dev/null || true

  run_or_warn aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
  echo "  ✅ Bucket deleted: ${BUCKET_NAME}"
else
  echo "  ✅ Bucket does not exist — skipping"
fi

# ------------------------------------------------------------------
# 2. Remove IAM roles and policies
# ------------------------------------------------------------------
echo ""
echo "[2/6] Removing IAM roles and policies..."

for ROLE in ec2-s3-access-role s3-read-write-get s3-read-only; do
  if aws iam get-role --role-name "${ROLE}" 2>/dev/null; then
    # Remove inline policies
    POLICIES=$(aws iam list-role-policies --role-name "${ROLE}" \
      --query "PolicyNames" --output text 2>/dev/null || echo "")
    for POLICY in ${POLICIES}; do
      run_or_warn aws iam delete-role-policy \
        --role-name "${ROLE}" \
        --policy-name "${POLICY}"
      echo "  Removed inline policy: ${POLICY} from ${ROLE}"
    done
    # Detach managed policies
    MANAGED=$(aws iam list-attached-role-policies --role-name "${ROLE}" \
      --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
    for POLICY_ARN in ${MANAGED}; do
      run_or_warn aws iam detach-role-policy \
        --role-name "${ROLE}" \
        --policy-arn "${POLICY_ARN}"
      echo "  Detached managed policy: ${POLICY_ARN} from ${ROLE}"
    done
    run_or_warn aws iam delete-role --role-name "${ROLE}"
    echo "  ✅ Deleted role: ${ROLE}"
  else
    echo "  ✅ Role ${ROLE} does not exist — skipping"
  fi
done

# ------------------------------------------------------------------
# 3. Remove EC2 instance profile
# ------------------------------------------------------------------
echo ""
echo "[3/6] Removing EC2 instance profile..."

if aws iam get-instance-profile --instance-profile-name ec2-s3-access-profile 2>/dev/null; then
  run_or_warn aws iam remove-role-from-instance-profile \
    --instance-profile-name ec2-s3-access-profile \
    --role-name ec2-s3-access-role
  run_or_warn aws iam delete-instance-profile \
    --instance-profile-name ec2-s3-access-profile
  echo "  ✅ Deleted instance profile: ec2-s3-access-profile"
else
  echo "  ✅ Instance profile does not exist — skipping"
fi

# ------------------------------------------------------------------
# 4. Remove IAM users
# ------------------------------------------------------------------
echo ""
echo "[4/6] Removing IAM users..."

for USER in Alice-developer Bob-viewer; do
  if aws iam get-user --user-name "${USER}" 2>/dev/null; then
    # Remove inline policies
    USER_POLICIES=$(aws iam list-user-policies --user-name "${USER}" \
      --query "PolicyNames" --output text 2>/dev/null || echo "")
    for POLICY in ${USER_POLICIES}; do
      run_or_warn aws iam delete-user-policy \
        --user-name "${USER}" \
        --policy-name "${POLICY}"
    done
    # Deactivate and delete MFA devices
    MFA_DEVICES=$(aws iam list-mfa-devices --user-name "${USER}" \
      --query "MFADevices[].SerialNumber" --output text 2>/dev/null || echo "")
    for MFA in ${MFA_DEVICES}; do
      run_or_warn aws iam deactivate-mfa-device \
        --user-name "${USER}" \
        --serial-number "${MFA}"
      run_or_warn aws iam delete-virtual-mfa-device --serial-number "${MFA}"
    done
    # Delete access keys
    KEYS=$(aws iam list-access-keys --user-name "${USER}" \
      --query "AccessKeyMetadata[].AccessKeyId" --output text 2>/dev/null || echo "")
    for KEY in ${KEYS}; do
      run_or_warn aws iam delete-access-key \
        --user-name "${USER}" \
        --access-key-id "${KEY}"
    done
    run_or_warn aws iam delete-user --user-name "${USER}"
    echo "  ✅ Deleted user: ${USER}"
  else
    echo "  ✅ User ${USER} does not exist — skipping"
  fi
done

# ------------------------------------------------------------------
# 5. Terminate EC2 instances
# ------------------------------------------------------------------
echo ""
echo "[5/6] Terminating EC2 instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Project,Values=s3-iam-rbac" \
    "Name=instance-state-name,Values=running,pending,stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text 2>/dev/null || echo "")

if [[ -n "${INSTANCE_IDS}" ]]; then
  for ID in ${INSTANCE_IDS}; do
    run_or_warn aws ec2 terminate-instances --instance-ids "${ID}"
    echo "  ✅ Terminating instance: ${ID}"
  done
else
  echo "  ✅ No tagged EC2 instances found — skipping"
fi

# ------------------------------------------------------------------
# 6. Delete ALB and target group
# ------------------------------------------------------------------
echo ""
echo "[6/6] Removing ALB and target group..."

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "secure-s3-alb" \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text 2>/dev/null || echo "None")

if [[ "${ALB_ARN}" != "None" ]] && [[ -n "${ALB_ARN}" ]]; then
  # Delete listeners first
  LISTENER_ARNS=$(aws elbv2 describe-listeners \
    --load-balancer-arn "${ALB_ARN}" \
    --query "Listeners[].ListenerArn" \
    --output text 2>/dev/null || echo "")
  for LISTENER_ARN in ${LISTENER_ARNS}; do
    run_or_warn aws elbv2 delete-listener --listener-arn "${LISTENER_ARN}"
  done
  run_or_warn aws elbv2 delete-load-balancer --load-balancer-arn "${ALB_ARN}"
  echo "  ✅ Deleted ALB: secure-s3-alb"
else
  echo "  ✅ ALB does not exist — skipping"
fi

TG_ARN=$(aws elbv2 describe-target-groups \
  --names "ec2-s3-targets" \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text 2>/dev/null || echo "None")

if [[ "${TG_ARN}" != "None" ]] && [[ -n "${TG_ARN}" ]]; then
  run_or_warn aws elbv2 delete-target-group --target-group-arn "${TG_ARN}"
  echo "  ✅ Deleted target group: ec2-s3-targets"
else
  echo "  ✅ Target group does not exist — skipping"
fi

echo ""
echo "=========================================================="
if [[ ${ERRORS} -gt 0 ]]; then
  echo " ⚠️  Cleanup completed with ${ERRORS} warning(s) (resources may not have existed)"
else
  echo " ✅ Cleanup complete — all resources removed"
fi
echo "=========================================================="
