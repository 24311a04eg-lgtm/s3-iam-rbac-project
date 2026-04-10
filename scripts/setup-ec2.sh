#!/usr/bin/env bash
# =============================================================================
# setup-ec2.sh — Launch EC2 instance with IAM profile and ALB
# =============================================================================
# Usage: ./scripts/setup-ec2.sh [VPC_ID] [PUBLIC_SUBNET_1] [PUBLIC_SUBNET_2]
# Prerequisites: AWS CLI configured, VPC with public/private subnets
# =============================================================================
set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
INSTANCE_PROFILE="ec2-s3-access-profile"
INSTANCE_NAME="s3-cli-host"
ALB_NAME="secure-s3-alb"
TG_NAME="ec2-s3-targets"

# Accept optional arguments
VPC_ID="${1:-}"
PUBLIC_SUBNET_1="${2:-}"
PUBLIC_SUBNET_2="${3:-}"

echo "=========================================================="
echo " S3 IAM RBAC Setup — EC2 Instance & ALB"
echo " Region: ${REGION} | Account: ${ACCOUNT_ID}"
echo "=========================================================="

# ------------------------------------------------------------------
# Auto-discover VPC and subnets if not provided
# ------------------------------------------------------------------
if [[ -z "${VPC_ID}" ]]; then
  echo ""
  echo "[Auto] Discovering default VPC..."
  VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)
  echo "  VPC: ${VPC_ID}"
fi

if [[ -z "${PUBLIC_SUBNET_1}" ]] || [[ -z "${PUBLIC_SUBNET_2}" ]]; then
  echo ""
  echo "[Auto] Discovering public subnets in ${VPC_ID}..."
  SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=true" \
    --query "Subnets[*].SubnetId" \
    --output text)
  PUBLIC_SUBNET_1=$(echo "${SUBNETS}" | awk '{print $1}')
  PUBLIC_SUBNET_2=$(echo "${SUBNETS}" | awk '{print $2}')
  echo "  Subnet 1: ${PUBLIC_SUBNET_1}"
  echo "  Subnet 2: ${PUBLIC_SUBNET_2}"
fi

# ------------------------------------------------------------------
# 1. Get latest Amazon Linux 2023 AMI
# ------------------------------------------------------------------
echo ""
echo "[1/5] Finding latest Amazon Linux 2023 AMI..."

AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters \
    "Name=name,Values=al2023-ami-2023*-x86_64" \
    "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text)
echo "  ✅ AMI: ${AMI_ID}"

# ------------------------------------------------------------------
# 2. Create security group for EC2
# ------------------------------------------------------------------
echo ""
echo "[2/5] Creating EC2 security group..."

SG_NAME="ec2-s3-host-sg"
EXISTING_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_SG}" != "None" ]] && [[ -n "${EXISTING_SG}" ]]; then
  EC2_SG_ID="${EXISTING_SG}"
  echo "  ✅ Security group already exists: ${EC2_SG_ID}"
else
  EC2_SG_ID=$(aws ec2 create-security-group \
    --group-name "${SG_NAME}" \
    --description "Security group for S3 CLI host EC2 instance" \
    --vpc-id "${VPC_ID}" \
    --query GroupId \
    --output text)
  # Allow outbound HTTPS for AWS API calls
  aws ec2 authorize-security-group-egress \
    --group-id "${EC2_SG_ID}" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0
  echo "  ✅ Created security group: ${EC2_SG_ID}"
fi

# ------------------------------------------------------------------
# 3. Launch EC2 instance with instance profile
# ------------------------------------------------------------------
echo ""
echo "[3/5] Launching EC2 instance..."

EXISTING_INSTANCE=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=${INSTANCE_NAME}" \
    "Name=instance-state-name,Values=running,pending" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_INSTANCE}" != "None" ]] && [[ -n "${EXISTING_INSTANCE}" ]]; then
  INSTANCE_ID="${EXISTING_INSTANCE}"
  echo "  ✅ Instance already running: ${INSTANCE_ID}"
else
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type t3.micro \
    --subnet-id "${PUBLIC_SUBNET_1}" \
    --security-group-ids "${EC2_SG_ID}" \
    --iam-instance-profile Name="${INSTANCE_PROFILE}" \
    --associate-public-ip-address \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Project,Value=s3-iam-rbac}]" \
    --user-data '#!/bin/bash
yum update -y
yum install -y aws-cli jq' \
    --query "Instances[0].InstanceId" \
    --output text)
  echo "  ✅ Launched instance: ${INSTANCE_ID}"
  echo "  ⏳ Waiting for instance to be running..."
  aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
  echo "  ✅ Instance is running"
fi

# ------------------------------------------------------------------
# 4. Create ALB with target group
# ------------------------------------------------------------------
echo ""
echo "[4/5] Creating Application Load Balancer..."

ALB_SG_NAME="alb-public-sg"
EXISTING_ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${ALB_SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_ALB_SG}" != "None" ]] && [[ -n "${EXISTING_ALB_SG}" ]]; then
  ALB_SG_ID="${EXISTING_ALB_SG}"
  echo "  ✅ ALB security group exists: ${ALB_SG_ID}"
else
  ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name "${ALB_SG_NAME}" \
    --description "Public-facing ALB security group" \
    --vpc-id "${VPC_ID}" \
    --query GroupId \
    --output text)
  aws ec2 authorize-security-group-ingress \
    --group-id "${ALB_SG_ID}" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress \
    --group-id "${ALB_SG_ID}" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0
  echo "  ✅ Created ALB security group: ${ALB_SG_ID}"
fi

EXISTING_ALB=$(aws elbv2 describe-load-balancers \
  --names "${ALB_NAME}" \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_ALB}" != "None" ]] && [[ -n "${EXISTING_ALB}" ]]; then
  ALB_ARN="${EXISTING_ALB}"
  echo "  ✅ ALB already exists: ${ALB_ARN}"
else
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "${ALB_NAME}" \
    --subnets "${PUBLIC_SUBNET_1}" "${PUBLIC_SUBNET_2}" \
    --security-groups "${ALB_SG_ID}" \
    --scheme internet-facing \
    --type application \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text)
  echo "  ✅ Created ALB: ${ALB_ARN}"
fi

# Create target group
EXISTING_TG=$(aws elbv2 describe-target-groups \
  --names "${TG_NAME}" \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_TG}" != "None" ]] && [[ -n "${EXISTING_TG}" ]]; then
  TG_ARN="${EXISTING_TG}"
  echo "  ✅ Target group already exists: ${TG_ARN}"
else
  TG_ARN=$(aws elbv2 create-target-group \
    --name "${TG_NAME}" \
    --protocol HTTP \
    --port 80 \
    --vpc-id "${VPC_ID}" \
    --health-check-path "/" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)
  echo "  ✅ Created target group: ${TG_ARN}"
fi

# Register EC2 with target group
aws elbv2 register-targets \
  --target-group-arn "${TG_ARN}" \
  --targets "Id=${INSTANCE_ID}"
echo "  ✅ Registered instance with target group"

# ------------------------------------------------------------------
# 5. Get EC2 public DNS / ALB DNS
# ------------------------------------------------------------------
echo ""
echo "[5/5] Retrieving endpoint information..."

EC2_PUBLIC_DNS=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].PublicDnsName" \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "${ALB_ARN}" \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo ""
echo "=========================================================="
echo " ✅ EC2 + ALB setup complete!"
echo "    Instance ID:  ${INSTANCE_ID}"
echo "    EC2 DNS:      ${EC2_PUBLIC_DNS}"
echo "    ALB DNS:      ${ALB_DNS}"
echo "    Profile:      ${INSTANCE_PROFILE}"
echo ""
echo " To connect via SSM (no SSH key needed):"
echo "    aws ssm start-session --target ${INSTANCE_ID}"
echo "=========================================================="
