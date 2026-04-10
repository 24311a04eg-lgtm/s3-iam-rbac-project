# 📖 Complete Project Setup Guide

A step-by-step walkthrough for building the AWS S3 IAM Role-Based Access Control system from scratch — with real AWS console screenshots at every stage.

---

## Table of Contents

1. [Introduction & Real-World Use Case](#1-introduction--real-world-use-case)
2. [Architecture Overview](#2-architecture-overview)
3. [AWS Services Overview](#3-aws-services-overview)
4. [Prerequisites](#4-prerequisites)
5. [S3 Bucket Configuration](#5-s3-bucket-configuration)
6. [IAM Design & Implementation](#6-iam-design--implementation)
7. [EC2 Instance Setup](#7-ec2-instance-setup)
8. [Application Load Balancer Setup](#8-application-load-balancer-setup)
9. [Testing & Validation](#9-testing--validation)
10. [Summary](#10-summary)

---

## 1. Introduction & Real-World Use Case

### The Problem

Many organizations store critical files in Amazon S3 — client reports, financial exports, operational data. The challenge is always the same:

> *"How do we give the right people access to the right files, without risking accidental deletion or unauthorized access?"*

![Corporate S3 File](../images/12-ec2-uploads-list.png)
*A real corporate file — clients-reports.txt stored in S3 (January 31, 2026). This is the type of sensitive data companies store in S3 that needs careful access control.*

### Our Solution

We build a **role-based access control (RBAC)** system with three identities:

| Identity | Role | Real-World Person |
|---|---|---|
| **Alice** | Developer | Someone who builds reports and needs to upload/download |
| **Bob** | Viewer / Auditor | Someone who reviews reports but never modifies them |
| **EC2 App** | Application | Automated server that generates and stores reports |

### Permission Requirements

| Identity | Can List | Can Download | Can Upload | Can Delete |
|---|:---:|:---:|:---:|:---:|
| Alice (Developer) | ✅ | ✅ | ✅ | ❌ |
| Bob (Viewer) | ✅ | ✅ | ❌ | ❌ |
| EC2 Application | ✅ | ✅ | ✅ | ❌ |

> 🔑 **Security principle:** Nobody gets delete permissions. Even if credentials are compromised, data cannot be permanently removed.

### What Gets Stored in S3

Employees download files like this from S3 to their local machines:

![Downloads Folder](../images/02-downloads-folder.png)
*Local Downloads folder showing Data-report.csv — a file downloaded from S3. This demonstrates the end-to-end flow: files are stored in S3, employees download them securely.*

---

## 2. Architecture Overview

### Architecture Diagram

![Architecture Diagram](../images/01-architecture.png)

### Component Breakdown

```
AWS Account (US-EAST-1)
└── VPC: SECURE-S3-VPC (10.0.0.0/16)
    ├── Public Subnet (10.0.1.0/24)
    │   └── Application Load Balancer (ALB)
    │       ├── Scheme: Internet-facing
    │       ├── AZ: us-east-1a + us-east-1d
    │       └── Routes HTTPS traffic → EC2
    ├── Private Subnet (10.0.2.0/24)
    │   └── EC2 Instance (s3-cli-host)
    │       ├── IAM Instance Profile: ec2-s3-access-role
    │       ├── Performs: s3:ListBucket + s3:GetObject + s3:PutObject
    │       └── NO s3:DeleteObject (enforced by IAM)
    └── IAM (Global, not VPC-scoped)
        ├── Users
        │   ├── Alice-developer → assumes s3-read-write-get
        │   └── Bob-viewer      → assumes s3-read-only
        └── Roles
            ├── s3-read-write-get  (Alice: LIST + GET + PUT)
            ├── s3-read-only       (Bob: LIST + GET)
            ├── ec2-s3-access-role (EC2: LIST + GET + PUT)
            ├── rds-proxy-role     (RDS Proxy service)
            └── ssm-role           (Systems Manager)

S3 Bucket: secure-corp-storage (us-east-1)
├── Public Access: BLOCKED (all 4 settings)
├── Versioning: Enabled
├── Encryption: SSE-S3 (AES-256)
└── Lifecycle: Standard → IA → Intelligent-Tiering → One Zone-IA → Glacier
```

### Data Flow Explanation

```
1. Internet Request
        │ HTTPS/443
        ▼
2. Application Load Balancer (Public Subnet)
        │ HTTPS/443
        ▼
3. EC2 Instance (Private Subnet)
        │ Uses IAM Instance Profile
        ▼
4. AWS STS (Security Token Service)
   → Issues temporary credentials to EC2
        │ Temporary credentials
        ▼
5. Amazon S3: secure-corp-storage
   ✅ ListBucket → allowed
   ✅ GetObject  → allowed
   ✅ PutObject  → allowed
   ❌ DeleteObject → DENIED

Human Users (Alice / Bob):
   → Use MFA device to authenticate
   → Call sts:AssumeRole with MFA token
   → Get temporary credentials for their role
   → Access S3 within their policy boundaries
```

**Key security principle:** No long-term credentials are stored anywhere. EC2 uses an IAM instance profile (automatic credential rotation). Alice and Bob use role assumption with MFA.

---

## 3. AWS Services Overview

| Service | Role in This Project | Key Configuration |
|---|---|---|
| **Amazon S3** | Central file storage for all reports | Bucket: `secure-corp-storage`, versioning + encryption + lifecycle |
| **AWS IAM** | Access control engine | 5 roles, 2 users, 6 policies, MFA enforcement |
| **Amazon EC2** | Application/CLI host | AL2023, private subnet, instance profile — no hardcoded keys |
| **AWS ALB** | Load balancer & public entry point | Active, multi-AZ (us-east-1a + us-east-1d), internet-facing |
| **Amazon VPC** | Network isolation | `SECURE-S3-VPC`, public + private subnets |
| **AWS STS** | Temporary credential vending | Called automatically by IAM role assumption |

---

## 4. Prerequisites

### Required Tools

```bash
# Verify AWS CLI v2 is installed
aws --version
# Expected: aws-cli/2.x.x Python/3.x.x Linux/x86_64

# Configure your credentials
aws configure
# AWS Access Key ID:     [your admin access key]
# AWS Secret Access Key: [your admin secret key]
# Default region name:  us-east-1
# Default output format: json

# Verify you're authenticated
aws sts get-caller-identity
# Returns your account ID, user ARN, and user ID
```

### Required IAM Permissions (for the setup user)

Your admin IAM user/role needs these permissions to run the setup scripts:

```
iam:CreateUser
iam:CreateRole
iam:PutRolePolicy
iam:AttachRolePolicy
iam:CreateInstanceProfile
iam:AddRoleToInstanceProfile
s3:CreateBucket
s3:PutBucketVersioning
s3:PutBucketEncryption
s3:PutPublicAccessBlock
s3:PutLifecycleConfiguration
ec2:RunInstances
ec2:CreateSecurityGroup
elasticloadbalancing:CreateLoadBalancer
elasticloadbalancing:CreateTargetGroup
```

---

## 5. S3 Bucket Configuration

### 5.1 Create the S3 Bucket

```bash
# Create the bucket in us-east-1
aws s3api create-bucket \
  --bucket secure-corp-storage \
  --region us-east-1

# Block ALL public access (4 settings)
aws s3api put-public-access-block \
  --bucket secure-corp-storage \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 5.2 Verify Bucket Creation

After running the command, the bucket appears in the AWS S3 console:

![S3 Buckets List](../images/03-s3-general-buckets.png)
*S3 console showing the `secure-corp-storage` bucket in US East (N. Virginia) — successfully created under General purpose buckets*

![S3 Bucket Details](../images/17-s3-bucket-details.png)
*Detailed view of secure-corp-storage bucket — the bucket is now ready to store corporate files*

### 5.3 Enable Versioning

Versioning protects against accidental overwrites by keeping previous versions of every object:

```bash
aws s3api put-bucket-versioning \
  --bucket secure-corp-storage \
  --versioning-configuration Status=Enabled

# Verify versioning is enabled
aws s3api get-bucket-versioning \
  --bucket secure-corp-storage
# Output: {"Status": "Enabled"}
```

### 5.4 Enable Default Encryption

All objects stored in the bucket are automatically encrypted at rest using AES-256:

```bash
aws s3api put-bucket-encryption \
  --bucket secure-corp-storage \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Verify encryption
aws s3api get-bucket-encryption --bucket secure-corp-storage
```

### 5.5 Configure Lifecycle Policy

The lifecycle policy automatically moves objects to cheaper storage tiers as they age, reducing costs:

```bash
# Create the lifecycle configuration file
cat > /tmp/lifecycle.json << 'EOF'
{
  "Rules": [{
    "ID": "CostOptimizationRule",
    "Status": "Enabled",
    "Filter": {"Prefix": ""},
    "Transitions": [
      {"Days": 30,  "StorageClass": "STANDARD_IA"},
      {"Days": 60,  "StorageClass": "INTELLIGENT_TIERING"},
      {"Days": 90,  "StorageClass": "ONEZONE_IA"},
      {"Days": 120, "StorageClass": "GLACIER"}
    ]
  }]
}
EOF

# Apply the lifecycle policy
aws s3api put-bucket-lifecycle-configuration \
  --bucket secure-corp-storage \
  --lifecycle-configuration file:///tmp/lifecycle.json
```

![S3 Lifecycle Policy](../images/19-s3-lifecycle-policy.png)
*S3 Lifecycle policy configured: Day 0 (upload) → Day 30 (Standard-IA) → Day 60 (Intelligent-Tiering) → Day 90 (One Zone-IA) → Day 120 (Glacier Flexible Retrieval). Objects automatically move to cheaper storage as they age.*

### 5.6 Upload Test Files and Verify Bucket Contents

```bash
# Create test files
echo "Client report data - Q1 2026" > report1.txt
echo "Client report data - Q2 2026" > report2.txt
echo "Confidential client records" > report3.txt
echo "Data export 2026-01-31" > Data-report.csv

# Upload all files to the bucket
aws s3 cp report1.txt s3://secure-corp-storage/
aws s3 cp report2.txt s3://secure-corp-storage/
aws s3 cp report3.txt s3://secure-corp-storage/
aws s3 cp Data-report.csv s3://secure-corp-storage/
```

**EC2 CLI listing — proves the files are in S3:**

![EC2 S3 Listing](../images/08-s3-console.png)
*EC2 CLI output: `aws s3 ls s3://secure-corp-storage/` — shows Data-report.csv (184B), report1.txt (97B), report2.txt (106B), report3.txt (134B) with upload timestamps*

**S3 Console — full bucket contents:**

![S3 Files Listing](../images/18-s3-bucket-contents-files.png)
*S3 console showing all files in secure-corp-storage: Data-report.csv (184B), report1.txt (97B), report2.txt (106B), and report3.txt — stored securely with Standard storage class*

**Access control in action — what happens without proper permissions:**

![S3 Access Denied](../images/04-s3-bucket-contents.png)
*S3 console showing Access Denied on report3.txt — demonstrates that S3 enforces access control. Without the correct IAM role, even viewing file details is blocked.*

---

## 6. IAM Design & Implementation

### IAM Design Philosophy

> "Grant the minimum permissions necessary — nothing more."

Every identity gets exactly what it needs:
- **Alice** needs to upload reports → gets ListBucket + GetObject + PutObject
- **Bob** only reviews reports → gets ListBucket + GetObject
- **EC2** runs the application → gets ListBucket + GetObject + PutObject
- **Nobody** needs to delete → nobody gets DeleteObject

### 6.1 IAM Users

Two human IAM users are created for developer and viewer access:

![IAM Users](../images/13-iam-users.png)
*IAM Users console showing Alice-developer and Bob-viewer — both are active IAM users with console and programmatic access*

| Username | Access Type | Assigned Role | Purpose |
|---|---|---|---|
| `Alice-developer` | Console + Programmatic | `s3-read-write-get` | Uploads and manages report files |
| `Bob-viewer` | Console + Programmatic | `s3-read-only` | Reviews and audits report files |

```bash
# Create Alice (developer)
aws iam create-user --user-name Alice-developer

# Create login profile for console access
aws iam create-login-profile \
  --user-name Alice-developer \
  --password 'TempPass123!' \
  --password-reset-required

# Create Bob (viewer)
aws iam create-user --user-name Bob-viewer

# Create login profile for console access
aws iam create-login-profile \
  --user-name Bob-viewer \
  --password 'TempPass456!' \
  --password-reset-required
```

### 6.2 IAM Roles

Five IAM roles are configured in this system:

![IAM Roles](../images/14-iam-roles.png)
*IAM Roles console showing all 5 roles: ec2-s3-access-role, rds-proxy-role-xxx, s3-read-only, s3-read-write-get, ssm-role*

| Role Name | Purpose | Trusted By | Permissions |
|---|---|---|---|
| `ec2-s3-access-role` | EC2 application S3 access | EC2 service (`ec2.amazonaws.com`) | List + Get + Put |
| `s3-read-write-get` | Alice's role | Alice-developer (MFA required) | List + Get + Put |
| `s3-read-only` | Bob's role | Bob-viewer (MFA required) | List + Get |
| `rds-proxy-role` | RDS Proxy service role | RDS service | RDS-specific |
| `ssm-role` | Systems Manager access | EC2 service | SSM-specific |

### 6.3 Alice's Policy (s3-read-write-get)

Alice can list, download, and upload files. She **cannot delete**.

![Alice's S3 Read-Write Policy](../images/15-s3-read-write-policy.png)
*Alice's IAM policy JSON — grants s3:ListBucket on the bucket ARN, and s3:GetObject + s3:PutObject on all objects within the bucket. Note: no s3:DeleteObject.*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBucketListing",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Sid": "AllowReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::secure-corp-storage/*"
    }
  ]
}
```

**Policy explanation:**
- `s3:ListBucket` on the bucket ARN → lets Alice see the list of files
- `s3:GetObject` on `/*` → lets Alice download any file
- `s3:PutObject` on `/*` → lets Alice upload new files or update existing ones
- Missing `s3:DeleteObject` → Alice **cannot delete** anything

### 6.4 Bob's Policy (s3-read-only)

Bob can list and download only. He **cannot upload or delete**.

![Bob's S3 Read-Only Policy](../images/16-s3-read-only-policy.png)
*Bob's IAM policy JSON — grants s3:ListBucket on the bucket ARN and s3:GetObject on objects. No s3:PutObject, no s3:DeleteObject.*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBucketListing",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Sid": "AllowReadOnly",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::secure-corp-storage/*"
    }
  ]
}
```

**Policy explanation:**
- `s3:ListBucket` → lets Bob see the list of files (audit visibility)
- `s3:GetObject` → lets Bob download files to review them
- Missing `s3:PutObject` → Bob **cannot upload** anything
- Missing `s3:DeleteObject` → Bob **cannot delete** anything

### 6.5 Trust Policies — Controlling Who Can Assume Each Role

Trust policies control which principals (users/services) can call `sts:AssumeRole` to get temporary credentials for a role.

**Alice's trust policy** (who can assume `s3-read-write-get`):

![IAM Trust Policy](../images/09-iam-trust-read-only.png)
*Trust policy JSON — defines who can assume this role. The Effect=Allow, Action=sts:AssumeRole configuration, scoped to a specific IAM principal.*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:user/Alice-developer"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
```

**Bob's trust policy** (who can assume `s3-read-only`):

![IAM Trust Policy Write-Get](../images/10-iam-trust-write-get.png)
*Trust policy for s3-read-write-get role — shows sts:AssumeRole allowed for role ARN arn:aws:iam::855409827378:role/s3-read-write-get with the action explicitly permitted*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:user/Bob-viewer"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
```

> 🔑 **`aws:MultiFactorAuthPresent: "true"`** — this condition means Alice and Bob MUST use their MFA device when assuming roles. If they don't provide a valid MFA token, `sts:AssumeRole` is denied.

### 6.6 Create All Roles with AWS CLI

```bash
# ── Alice's role ──────────────────────────────────────────────────────────
# Create the role with trust policy
aws iam create-role \
  --role-name s3-read-write-get \
  --assume-role-policy-document file://iam-policies/trust-policy-alice.json \
  --description "Alice developer role - S3 read + write, no delete"

# Attach Alice's permissions policy
aws iam put-role-policy \
  --role-name s3-read-write-get \
  --policy-name S3ReadWriteGetPolicy \
  --policy-document file://iam-policies/s3-read-write-policy.json

# ── Bob's role ────────────────────────────────────────────────────────────
# Create the role with trust policy
aws iam create-role \
  --role-name s3-read-only \
  --assume-role-policy-document file://iam-policies/trust-policy-bob.json \
  --description "Bob viewer role - S3 read only, no write or delete"

# Attach Bob's permissions policy
aws iam put-role-policy \
  --role-name s3-read-only \
  --policy-name S3ReadOnlyPolicy \
  --policy-document file://iam-policies/s3-read-only-policy.json

# ── Attach permissions for users to assume their roles ───────────────────
# Allow Alice to call sts:AssumeRole for her role
aws iam put-user-policy \
  --user-name Alice-developer \
  --policy-name AssumeS3ReadWriteRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::ACCOUNT_ID:role/s3-read-write-get"
    }]
  }'

# Allow Bob to call sts:AssumeRole for his role
aws iam put-user-policy \
  --user-name Bob-viewer \
  --policy-name AssumeS3ReadOnlyRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::ACCOUNT_ID:role/s3-read-only"
    }]
  }'
```

---

## 7. EC2 Instance Setup

### 7.1 Create EC2 IAM Role

The EC2 instance uses an **instance profile** — no hardcoded credentials, no access keys stored on the server:

```bash
# Create EC2 role with trust policy for EC2 service
aws iam create-role \
  --role-name ec2-s3-access-role \
  --assume-role-policy-document file://iam-policies/trust-policy-ec2.json \
  --description "EC2 application role - S3 read + write, no delete"

# Attach EC2 S3 access policy
aws iam put-role-policy \
  --role-name ec2-s3-access-role \
  --policy-name EC2S3AccessPolicy \
  --policy-document file://iam-policies/ec2-s3-access-policy.json

# Create instance profile (container for the role)
aws iam create-instance-profile \
  --instance-profile-name ec2-s3-access-profile

# Associate the role with the instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-s3-access-profile \
  --role-name ec2-s3-access-role
```

The EC2 trust policy (`trust-policy-ec2.json`) allows the EC2 service to assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```

### 7.2 Launch EC2 Instance

```bash
# Create security group for EC2
aws ec2 create-security-group \
  --group-name ec2-s3-host-sg \
  --description "Security group for S3 CLI host" \
  --vpc-id vpc-SECURE-S3-VPC

# Allow inbound from ALB only (port 80)
aws ec2 authorize-security-group-ingress \
  --group-id sg-XXXXXXXX \
  --protocol tcp \
  --port 80 \
  --source-group sg-ALB-SECURITY-GROUP

# Launch instance in private subnet with instance profile
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --subnet-id subnet-PRIVATE-SUBNET-ID \
  --security-group-ids sg-XXXXXXXX \
  --iam-instance-profile Name=ec2-s3-access-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=s3-cli-host}]' \
  --no-associate-public-ip-address

# Verify instance is running with correct profile
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=s3-cli-host" \
  --query 'Reservations[0].Instances[0].[State.Name,IamInstanceProfile.Arn]'
```

---

## 8. Application Load Balancer Setup

### 8.1 Why an ALB?

The EC2 instance is in a **private subnet** — it has no direct internet access. The ALB sits in the **public subnet** and routes traffic to EC2. This means:
- EC2 is never directly exposed to the internet
- The ALB handles TLS termination
- Traffic can be distributed across multiple EC2 instances for scaling

### 8.2 ALB Details

![ALB Details](../images/11-alb-details.png)
*Application Load Balancer — Active status, SECURE-S3-VPC, Internet-facing scheme, spanning us-east-1a and us-east-1d availability zones for high availability*

| Property | Value |
|---|---|
| **Type** | Application Load Balancer |
| **State** | Active |
| **VPC** | SECURE-S3-VPC |
| **Scheme** | Internet-facing |
| **Availability Zones** | us-east-1a (use1-az1), us-east-1d (use1-az6) |
| **Subnets** | One public subnet per AZ |

### 8.3 Create ALB, Target Group, and Listener

```bash
# Step 1: Create security group for ALB (allows HTTPS from internet)
aws ec2 create-security-group \
  --group-name alb-security-group \
  --description "ALB security group - allows HTTPS from internet" \
  --vpc-id vpc-SECURE-S3-VPC

aws ec2 authorize-security-group-ingress \
  --group-id sg-ALB-SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Step 2: Create the Application Load Balancer
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name secure-s3-alb \
  --subnets subnet-PUBLIC-1A subnet-PUBLIC-1D \
  --security-groups sg-ALB-SG \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "ALB ARN: $ALB_ARN"

# Step 3: Create target group pointing to EC2 on port 80
TG_ARN=$(aws elbv2 create-target-group \
  --name ec2-s3-targets \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-SECURE-S3-VPC \
  --health-check-path /health \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Step 4: Register EC2 instance as a target
aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=i-XXXXXXXXXXXXXXXX

# Step 5: Create listener (HTTP for demo; use HTTPS in production)
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
```

---

## 9. Testing & Validation

This section validates that every permission scenario works exactly as designed.

### Testing Overview

| Identity | Operation | Expected Result |
|---|---|---|
| EC2 | List objects | ✅ PASS |
| EC2 | Download file | ✅ PASS |
| EC2 | Upload file | ✅ PASS |
| EC2 | Delete file | ❌ DENIED |
| Alice | List objects | ✅ PASS |
| Alice | Download file | ✅ PASS |
| Alice | Upload file | ✅ PASS |
| Alice | Delete file | ❌ DENIED |
| Bob | List objects | ✅ PASS |
| Bob | Download file | ✅ PASS |
| Bob | Upload file | ❌ DENIED |
| Bob | Delete file | ❌ DENIED |

---

### EC2 Testing (via SSH or SSM)

Connect to the EC2 instance using AWS Systems Manager Session Manager (no SSH key needed):

```bash
aws ssm start-session --target i-XXXXXXXXXXXXXXXX
```

#### Scenario 1: EC2 List Objects (PASS ✅)

EC2 uses its instance role to list all objects in the bucket:

![EC2 List Objects](../images/08-s3-console.png)
*EC2 CLI: `aws s3 ls s3://secure-corp-storage/` — successfully lists Uploads/Data-report.csv (184B), Uploads/report1.txt (97B), Uploads/report2.txt (106B), Uploads/report3.txt (134B) with timestamps*

```bash
# On the EC2 instance:
aws s3 ls s3://secure-corp-storage/
# 2026-01-31 13:25:46    184 Uploads/Data-report.csv
# 2026-01-31 13:25:47     97 Uploads/report1.txt
# 2026-01-31 13:25:47    106 Uploads/report2.txt
# 2026-01-31 13:25:48    134 Uploads/report3.txt
```

#### Scenario 2: EC2 Download (PASS ✅)

EC2 downloads a report file from S3:

![EC2 Download](../images/05-ec2-download.png)
*EC2 CLI: `aws s3 cp s3://secure-corp-storage/report1.txt .` — download succeeds. The file is transferred from S3 to the EC2 instance's local filesystem.*

```bash
# Download report1.txt from S3
aws s3 cp s3://secure-corp-storage/report1.txt ./report1.txt
# download: s3://secure-corp-storage/report1.txt to ./report1.txt ✅

# Verify the file was downloaded
cat report1.txt
# Client report data - Q1 2026
```

#### Scenario 3: EC2 Upload (PASS ✅)

EC2 creates a new file and uploads it to S3:

![EC2 Upload](../images/06-ec2-upload.png)
*EC2 CLI: `aws s3 cp report5.txt s3://secure-corp-storage/` — upload succeeds. The file is transferred from EC2 to the S3 bucket.*

```bash
# Create a new report file on EC2
nano report5.txt
# (type content, save with Ctrl+X)

# Upload to S3
aws s3 cp /home/ec2-user/report5.txt s3://secure-corp-storage/
# upload: ./report5.txt to s3://secure-corp-storage/report5.txt ✅
```

#### Scenario 4: EC2 Delete (DENIED ❌)

EC2 attempts to delete a file — the IAM policy has no `s3:DeleteObject`, so this fails:

![EC2 Delete Denied](../images/07-ec2-delete-denied.png)
*EC2 CLI: `aws s3 rm s3://secure-corp-storage/Data-report.csv` — AccessDenied. The error message explicitly says the ec2-s3-access-role is not authorized to call DeleteObject.*

```bash
# Attempt to delete Data-report.csv
aws s3 rm s3://secure-corp-storage/Data-report.csv
# delete failed: s3://secure-corp-storage/Data-report.csv
# An error occurred (AccessDenied) when calling the DeleteObject operation:
# User: arn:aws:sts::855409827378:assumed-role/ec2-s3-access-role/i-0fd9fbf94b8147f5e
# is not authorized to perform: s3:DeleteObject on resource:
# "arn:aws:s3:::secure-corp-storage/Data-report.csv"
```

✅ **Security confirmed:** Even though EC2 can read and write, it cannot delete. The principle of least privilege is working.

---

### Alice Testing (Developer - Read + Write)

Alice assumes her role using MFA before performing any S3 operations.

#### How Alice Assumes Her Role

```bash
# Step 1: Alice calls sts:AssumeRole with her MFA token
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/s3-read-write-get \
  --role-session-name alice-session \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/Alice-developer \
  --token-code 123456

# Step 2: Export the temporary credentials
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

#### Alice Views the S3 Bucket

Alice can see the bucket and all files (ListBucket permission):

```bash
# Alice lists the bucket contents
aws s3 ls s3://secure-corp-storage/
# 2026-01-31 21:33:00    184 Data-report.csv
# 2026-01-31 21:33:01     97 report1.txt
# 2026-01-31 21:33:01    106 report2.txt
# ✅ Alice can list all files
```

#### Alice Uploads a File (PASS ✅)

```bash
# Alice uploads Data-report.csv
aws s3 cp Data-report.csv s3://secure-corp-storage/Data-report.csv
# upload: ./Data-report.csv to s3://secure-corp-storage/Data-report.csv ✅
```

#### Alice Downloads a File (PASS ✅)

```bash
# Alice downloads report1.txt
aws s3 cp s3://secure-corp-storage/report1.txt ./report1.txt
# download: s3://secure-corp-storage/report1.txt to ./report1.txt ✅
```

#### Alice Attempts to Delete (DENIED ❌)

```bash
# Alice tries to delete a file — should fail
aws s3 rm s3://secure-corp-storage/report1.txt
# An error occurred (AccessDenied) when calling the DeleteObject operation:
# User: arn:aws:sts::ACCOUNT_ID:assumed-role/s3-read-write-get/alice-session
# is not authorized to perform: s3:DeleteObject ❌
```

---

### Bob Testing (Viewer - Read Only)

#### How Bob Assumes His Role

```bash
# Bob calls sts:AssumeRole with his MFA token
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/s3-read-only \
  --role-session-name bob-session \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/Bob-viewer \
  --token-code 654321

# Export temporary credentials
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

#### Bob Downloads a File (PASS ✅)

```bash
# Bob downloads report3.txt for review
aws s3 cp s3://secure-corp-storage/report3.txt ./report3.txt
# download: s3://secure-corp-storage/report3.txt to ./report3.txt ✅
```

#### Bob Attempts to Upload (DENIED ❌)

```bash
# Bob tries to upload a file — no s3:PutObject in his policy
echo "Modified report" > newfile.txt
aws s3 cp newfile.txt s3://secure-corp-storage/newfile.txt
# An error occurred (AccessDenied) when calling the PutObject operation:
# User: arn:aws:sts::ACCOUNT_ID:assumed-role/s3-read-only/bob-session
# is not authorized to perform: s3:PutObject ❌
```

#### Bob Attempts to Delete (DENIED ❌)

```bash
# Bob tries to delete a file — no s3:DeleteObject in his policy
aws s3 rm s3://secure-corp-storage/report3.txt
# An error occurred (AccessDenied) when calling the DeleteObject operation:
# User: arn:aws:sts::ACCOUNT_ID:assumed-role/s3-read-only/bob-session
# is not authorized to perform: s3:DeleteObject ❌
```

**S3 console shows Access Denied when Bob tries to access a restricted file:**

![S3 Access Denied for Bob](../images/04-s3-bucket-contents.png)
*S3 download attempt — report3.txt (134B, text/plain) shows Access denied status. This confirms the IAM read-only policy is being enforced at the object level.*

---

## 10. Summary

### What We Built

| Component | Details | Evidence |
|---|---|---|
| **S3 Bucket** | `secure-corp-storage` — versioned, encrypted, with lifecycle policy | Images 3, 17, 18, 19 |
| **IAM Users** | `Alice-developer` + `Bob-viewer` — named accounts, no shared credentials | Image 13 |
| **IAM Roles** | 5 roles — ec2-s3-access-role, s3-read-write-get, s3-read-only, rds-proxy, ssm | Image 14 |
| **IAM Policies** | Least-privilege JSON policies for each role | Images 15, 16 |
| **Trust Policies** | MFA-enforced role assumption for Alice and Bob | Images 9, 10 |
| **EC2 Instance** | Instance profile (no hardcoded keys), private subnet | Images 5, 6, 7, 8 |
| **ALB** | Internet-facing, multi-AZ, SECURE-S3-VPC | Image 11 |

### Security Guarantees Achieved

- ✅ **No identity can delete S3 objects** — DeleteObject missing from all policies
- ✅ **No public access to the bucket** — all 4 Block Public Access settings enabled
- ✅ **EC2 uses temporary credentials** — IAM instance profile, no hardcoded keys
- ✅ **MFA required for human access** — trust policy condition on Alice and Bob roles
- ✅ **Encryption at rest** — SSE-S3 (AES-256) on all objects
- ✅ **Network isolation** — EC2 in private subnet, only accessible via ALB
- ✅ **Versioning enabled** — accidental overwrites are recoverable
- ✅ **Automated cost optimization** — lifecycle policy moves cold data to Glacier

### Access Control Summary

```
Alice (Developer)
  ├── ✅ s3:ListBucket     → can see what's in the bucket
  ├── ✅ s3:GetObject      → can download files
  ├── ✅ s3:PutObject      → can upload/update files
  └── ❌ s3:DeleteObject   → CANNOT delete (not in policy)

Bob (Viewer)
  ├── ✅ s3:ListBucket     → can see what's in the bucket
  ├── ✅ s3:GetObject      → can download files
  ├── ❌ s3:PutObject      → CANNOT upload (not in policy)
  └── ❌ s3:DeleteObject   → CANNOT delete (not in policy)

EC2 (Application)
  ├── ✅ s3:ListBucket     → can list files (for app logic)
  ├── ✅ s3:GetObject      → can download files (for processing)
  ├── ✅ s3:PutObject      → can upload files (reports generated by app)
  └── ❌ s3:DeleteObject   → CANNOT delete (not in policy)
```

---

*Next: See [02-SECURITY-IMPROVEMENTS.md](02-SECURITY-IMPROVEMENTS.md) for production hardening — bucket policies, CloudTrail, HTTPS, VPC endpoints, and more.*
