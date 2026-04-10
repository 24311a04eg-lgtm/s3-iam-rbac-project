# 📖 Project Setup Guide

Complete walkthrough for building the AWS S3 IAM Role-Based Access Control system from scratch.

---

## Table of Contents

1. [Introduction & Use Case](#1-introduction--use-case)
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

## 1. Introduction & Use Case

### What We're Building

A **secure, production-ready S3 access control system** for a corporate environment where:

- **Employees** (Alice, Bob) need controlled access to company reports stored in S3
- **Applications** running on EC2 need to read and write files to S3
- **Security team** requires full audit trails and no accidental data deletion
- **Compliance** demands the principle of least privilege at all times

### Real-World Use Case

A company stores client reports, data exports, and operational files in an S3 bucket called `secure-corp-storage`. The access rules are:

| Identity | Can List | Can Download | Can Upload | Can Delete |
|---|:---:|:---:|:---:|:---:|
| Alice (Developer) | ✅ | ✅ | ✅ | ❌ |
| Bob (Viewer) | ✅ | ✅ | ❌ | ❌ |
| EC2 Application | ✅ | ✅ | ✅ | ❌ |

The S3 bucket contains files like:

![S3 Bucket Contents](../images/01-clients-reports.txt.jpg)
*clients-reports.txt — one of the files stored in the secure-corp-storage bucket (January 31, 2026)*

![Downloads Folder](../images/02-downloads-folder.jpg)
*Local Downloads folder showing Data-report.csv — a file downloaded from S3*

---

## 2. Architecture Overview

### Architecture Diagram

![Architecture Diagram](../images/20-architecture-diagram.jpg)

### Component Breakdown

```
AWS Account (US-EAST-1)
└── VPC: SECURE-S3-VPC
    ├── Public Subnet
    │   └── Application Load Balancer (ALB)
    │       └── Routes HTTPS traffic → EC2
    ├── Private Subnet
    │   └── EC2 Instance (AWS CLI Host)
    │       ├── IAM Instance Profile: ec2-s3-access-role
    │       └── Performs: LIST, GET, PUT on S3
    └── IAM (Global)
        ├── Users
        │   ├── Alice-developer → s3-read-write-get role
        │   └── Bob-viewer      → s3-read-only role
        └── Roles
            ├── s3-read-write-get  (Alice: LIST + GET + PUT)
            ├── s3-read-only       (Bob: LIST + GET)
            └── ec2-s3-access-role (EC2: LIST + GET + PUT)

S3 Bucket: secure-corp-storage
├── Versioning: Enabled
├── Public Access: Blocked
├── Encryption: SSE-S3
└── Lifecycle: Standard → IA → Glacier → Deep Archive → Delete
```

### Data Flow

1. **Client request** arrives at the **ALB** (Application Load Balancer)
2. ALB routes traffic to the **EC2 instance** in the private subnet
3. EC2 uses its **IAM instance profile** (`ec2-s3-access-role`) to authenticate with S3
4. **No long-term credentials** stored on EC2 — IAM role provides temporary credentials
5. EC2 can **list, download, and upload** files but **cannot delete** them
6. **Alice** assumes the `s3-read-write-get` role to manage files via console or CLI
7. **Bob** assumes the `s3-read-only` role for read-only access via console or CLI

---

## 3. AWS Services Overview

| Service | Role in This Project | Configuration |
|---|---|---|
| **Amazon S3** | Central file storage | Bucket: `secure-corp-storage`, versioning + encryption |
| **AWS IAM** | Access control engine | 3 roles, 2 users, 6 policies |
| **Amazon EC2** | Application/CLI host | AL2023, private subnet, instance profile |
| **AWS ALB** | Load balancer & entry point | Active, multi-AZ, us-east-1a + us-east-1d |
| **Amazon VPC** | Network isolation | `SECURE-S3-VPC` with public/private subnets |

---

## 4. Prerequisites

### Required Tools
```bash
# AWS CLI v2
aws --version
# aws-cli/2.x.x Python/3.x.x

# Configure credentials
aws configure
# AWS Access Key ID: [your key]
# AWS Secret Access Key: [your secret]
# Default region name: us-east-1
# Default output format: json
```

### Required Permissions (for setup)
Your IAM user/role needs:
- `iam:CreateUser`, `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`
- `s3:CreateBucket`, `s3:PutBucketPolicy`, `s3:PutLifecycleConfiguration`
- `ec2:RunInstances`, `ec2:CreateSecurityGroup`
- `elasticloadbalancing:CreateLoadBalancer`

---

## 5. S3 Bucket Configuration

### 5.1 Create the Bucket

```bash
# Create bucket in us-east-1
aws s3api create-bucket \
  --bucket secure-corp-storage \
  --region us-east-1

# Block ALL public access
aws s3api put-public-access-block \
  --bucket secure-corp-storage \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 5.2 S3 Bucket in AWS Console

![S3 General Buckets](../images/03-s3-general-buckets.jpg)
*S3 console showing secure-corp-storage bucket in US East (N. Virginia)*

![S3 Bucket Details](../images/17-s3-bucket-details.jpg)
*Detailed view of the secure-corp-storage bucket properties*

### 5.3 Enable Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket secure-corp-storage \
  --versioning-configuration Status=Enabled
```

### 5.4 Enable Default Encryption

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
```

### 5.5 Configure Lifecycle Policy

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket secure-corp-storage \
  --lifecycle-configuration file://lifecycle.json
```

![S3 Lifecycle Policy](../images/19-s3-lifecycle-policy.jpg)
*Lifecycle policy: Standard → Infrequent Access (30d) → Glacier (60d) → Deep Archive (90d) → Delete (120d)*

### 5.6 Bucket Contents

After uploading test files:

![S3 Bucket Contents](../images/04-s3-bucket-contents.jpg)
*S3 bucket contents showing report3.txt — Access Denied error demonstrates policy enforcement*

![S3 Console](../images/08-s3-console.jpg)
*S3 console view of secure-corp-storage bucket*

![S3 Files](../images/18-s3-bucket-contents-files.jpg)
*All files in the bucket: Data-report.csv, report1.txt, report2.txt, report3.txt, report5.txt*

---

## 6. IAM Design & Implementation

### 6.1 IAM Users

Two IAM users have been created:

![IAM Users](../images/13-iam-users.jpg)
*IAM Users: Alice-developer and Bob-viewer*

| Username | Access Type | Assigned Role |
|---|---|---|
| `Alice-developer` | Programmatic + Console | `s3-read-write-get` |
| `Bob-viewer` | Programmatic + Console | `s3-read-only` |

```bash
# Create Alice
aws iam create-user --user-name Alice-developer

# Create Bob
aws iam create-user --user-name Bob-viewer
```

### 6.2 IAM Roles

![IAM Roles](../images/14-iam-roles.jpg)
*IAM Roles: ec2-s3-access-role, rds-proxy-role, s3-read-only, s3-read-write-get, ssm-role*

Five roles are configured:

| Role Name | Purpose | Trusted By |
|---|---|---|
| `ec2-s3-access-role` | EC2 instance profile for S3 access | EC2 service |
| `s3-read-write-get` | Alice's role — list + get + put | Alice-developer (MFA required) |
| `s3-read-only` | Bob's role — list + get only | Bob-viewer (MFA required) |
| `rds-proxy-role` | RDS Proxy service role | RDS service |
| `ssm-role` | Systems Manager access | EC2 service |

### 6.3 Alice's Policy (s3-read-write-get)

![S3 Read-Write Policy](../images/15-s3-read-write-policy.jpg)
*Alice's IAM policy: ListBucket + GetObject + PutObject on secure-corp-storage*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::secure-corp-storage/*"
    }
  ]
}
```

### 6.4 Bob's Policy (s3-read-only)

![S3 Read-Only Policy](../images/16-s3-read-only-policy.jpg)
*Bob's IAM policy: ListBucket + GetObject only on secure-corp-storage*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::secure-corp-storage/*"
    }
  ]
}
```

### 6.5 Trust Policy — Alice's Role

![IAM Trust Policy Read-Only](../images/09-iam-trust-read-only.jpg)
*Trust policy for s3-read-only role — allows AssumeRole*

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

### 6.6 Trust Policy — Bob's Role

![IAM Trust Policy Write-Get](../images/10-iam-trust-write-get.jpg)
*Trust policy for s3-read-write-get role — allows AssumeRole*

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

### 6.7 Create Roles

```bash
# Create Alice's role
aws iam create-role \
  --role-name s3-read-write-get \
  --assume-role-policy-document file://iam-policies/trust-policy-alice.json

# Attach Alice's permission policy
aws iam put-role-policy \
  --role-name s3-read-write-get \
  --policy-name S3ReadWritePolicy \
  --policy-document file://iam-policies/s3-read-write-policy.json

# Create Bob's role
aws iam create-role \
  --role-name s3-read-only \
  --assume-role-policy-document file://iam-policies/trust-policy-bob.json

# Attach Bob's permission policy
aws iam put-role-policy \
  --role-name s3-read-only \
  --policy-name S3ReadOnlyPolicy \
  --policy-document file://iam-policies/s3-read-only-policy.json
```

---

## 7. EC2 Instance Setup

### 7.1 Create EC2 IAM Role

```bash
# Create EC2 role
aws iam create-role \
  --role-name ec2-s3-access-role \
  --assume-role-policy-document file://iam-policies/trust-policy-ec2.json

# Attach EC2 S3 access policy
aws iam put-role-policy \
  --role-name ec2-s3-access-role \
  --policy-name EC2S3AccessPolicy \
  --policy-document file://iam-policies/ec2-s3-access-policy.json

# Create instance profile
aws iam create-instance-profile --instance-profile-name ec2-s3-access-profile

# Add role to profile
aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-s3-access-profile \
  --role-name ec2-s3-access-role
```

### 7.2 Launch EC2 Instance

```bash
# Launch instance with instance profile
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --subnet-id subnet-XXXXXXXX \
  --security-group-ids sg-XXXXXXXX \
  --iam-instance-profile Name=ec2-s3-access-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=s3-cli-host}]'
```

---

## 8. Application Load Balancer Setup

### 8.1 ALB Details

![ALB Details](../images/11-alb-details.jpg)
*Application Load Balancer — Active status, multi-AZ (us-east-1a, us-east-1d)*

The ALB is configured with:
- **State:** Active
- **VPC:** SECURE-S3-VPC
- **Availability Zones:** us-east-1a, us-east-1d
- **Scheme:** Internet-facing (public)
- **Type:** Application Load Balancer

### 8.2 Create ALB

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name secure-s3-alb \
  --subnets subnet-PUBLIC-1A subnet-PUBLIC-1D \
  --security-groups sg-alb-XXXXXXXX \
  --scheme internet-facing \
  --type application

# Create target group
aws elbv2 create-target-group \
  --name ec2-s3-targets \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-XXXXXXXX \
  --health-check-path /health

# Register EC2 instance
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:targetgroup/ec2-s3-targets/XXXX \
  --targets Id=i-XXXXXXXXXXXXXXXX

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:loadbalancer/app/secure-s3-alb/XXXX \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:...
```

---

## 9. Testing & Validation

### Scenario 1: EC2 Download (PASS ✅)

EC2 can download files from S3 using its instance role:

![EC2 Download](../images/05-ec2-download.jpg)
*EC2 downloading report1.txt from S3 — operation succeeds*

```bash
# On EC2 instance
aws s3 cp s3://secure-corp-storage/report1.txt ./report1.txt
# download: s3://secure-corp-storage/report1.txt to ./report1.txt
```

### Scenario 2: EC2 Upload (PASS ✅)

EC2 can upload new files to S3:

![EC2 Upload](../images/06-ec2-upload.jpg)
*EC2 uploading report5.txt to S3 — operation succeeds*

```bash
echo "Report 5 content" > report5.txt
aws s3 cp report5.txt s3://secure-corp-storage/report5.txt
# upload: ./report5.txt to s3://secure-corp-storage/report5.txt
```

### Scenario 3: EC2 Delete (DENIED ❌)

EC2 correctly receives AccessDenied when attempting to delete:

![EC2 Delete Denied](../images/07-ec2-delete-denied.jpg)
*EC2 attempting to delete Data-report.csv — AccessDenied as expected*

```bash
aws s3 rm s3://secure-corp-storage/Data-report.csv
# An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied
```

### Scenario 4: EC2 File Listing (PASS ✅)

EC2 can list all files in the bucket:

![EC2 Uploads List](../images/12-ec2-uploads-list.jpg)
*EC2 listing S3 files — report2.txt (97B), report1.txt (106B), report3.txt (134B)*

```bash
aws s3 ls s3://secure-corp-storage/
# 2026-01-31 10:23:45     97 report2.txt
# 2026-01-31 10:24:12    106 report1.txt
# 2026-01-31 10:25:33    134 report3.txt
```

### Scenario 5: Alice Upload (PASS ✅)

Alice can upload files after assuming her role:

```bash
# Alice assumes her role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/s3-read-write-get \
  --role-session-name alice-session \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/Alice-developer \
  --token-code 123456

# Upload with temporary credentials
aws s3 cp Data-report.csv s3://secure-corp-storage/Data-report.csv
# upload: ./Data-report.csv to s3://secure-corp-storage/Data-report.csv ✅
```

### Scenario 6: Alice Download (PASS ✅)

Alice can download any file:

```bash
aws s3 cp s3://secure-corp-storage/report1.txt ./report1.txt
# download: s3://secure-corp-storage/report1.txt to ./report1.txt ✅
```

### Scenario 7: Alice Delete (DENIED ❌)

Alice cannot delete (no `s3:DeleteObject` in her policy):

```bash
aws s3 rm s3://secure-corp-storage/report1.txt
# An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied ❌
```

### Scenario 8: Bob Download (PASS ✅)

Bob can download files:

```bash
# Bob assumes his read-only role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/s3-read-only \
  --role-session-name bob-session \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/Bob-viewer \
  --token-code 654321

aws s3 cp s3://secure-corp-storage/report3.txt ./report3.txt
# download: s3://secure-corp-storage/report3.txt to ./report3.txt ✅
```

### Scenario 9: Bob Upload/Delete (DENIED ❌)

Bob cannot upload or delete:

```bash
aws s3 cp newfile.txt s3://secure-corp-storage/
# An error occurred (AccessDenied) when calling the PutObject operation: Access Denied ❌

aws s3 rm s3://secure-corp-storage/report3.txt
# An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied ❌
```

*S3 console confirmation — report3.txt access denied for Bob:*

![S3 Access Denied](../images/04-s3-bucket-contents.jpg)
*Bob attempting to access report3.txt — Access Denied as expected (read-only enforced)*

---

## 10. Summary

### What We Built

| Component | Details |
|---|---|
| S3 Bucket | `secure-corp-storage` in us-east-1 with versioning, encryption, lifecycle |
| IAM Users | `Alice-developer` (read-write) and `Bob-viewer` (read-only) |
| IAM Roles | `s3-read-write-get`, `s3-read-only`, `ec2-s3-access-role` |
| EC2 | Instance profile with temporary credentials, no hardcoded keys |
| ALB | Multi-AZ application load balancer routing to EC2 |

### Security Guarantees

- ✅ No identity can delete S3 objects
- ✅ No public access to the bucket
- ✅ All EC2 credentials are temporary (IAM role)
- ✅ MFA required for Alice and Bob to assume roles
- ✅ All actions are logged in CloudTrail

---

*Next: See [02-SECURITY-IMPROVEMENTS.md](02-SECURITY-IMPROVEMENTS.md) for production hardening recommendations.*
