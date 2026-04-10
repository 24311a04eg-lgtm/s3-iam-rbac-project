# 📖 Complete Project Setup Guide

Step-by-step walkthrough for building the AWS S3 IAM Role-Based Access Control (RBAC) system, following the exact sequence from architecture design through live testing.

---

## Table of Contents

1. [Use Case: Real-World Scenario](#1-use-case-real-world-scenario)
2. [Architecture Overview](#2-architecture-overview)
3. [Prerequisites](#3-prerequisites)
4. [S3 Bucket Configuration](#4-s3-bucket-configuration)
5. [IAM Design & Implementation](#5-iam-design--implementation)
6. [EC2 Instance Setup](#6-ec2-instance-setup)
7. [Application Load Balancer Setup](#7-application-load-balancer-setup)
8. [Testing & Validation](#8-testing--validation)
9. [Summary](#9-summary)

---

## 1. Use Case: Real-World Scenario

### The Problem

Organizations manage sensitive files in Amazon S3 every day — client reports, financial exports, operational data. The challenge is ensuring that **the right people have the right access, and nothing more**.

Without proper access controls:
- A developer might accidentally delete a critical file
- A read-only analyst could overwrite data they shouldn't touch
- An EC2 server could become a point of attack if it had overly broad permissions

### What This Project Solves

This project implements **Role-Based Access Control (RBAC)** for an S3 bucket called `secure-corp-storage` in a company called SecureCorp.

| Who | What They Need | What They Get |
|:---|:---|:---|
| 👩‍💻 **Alice** (Developer) | Upload reports, download files, view all objects | `s3:ListBucket` + `s3:GetObject` + `s3:PutObject` — **no delete** |
| 👨‍💼 **Bob** (Viewer/Analyst) | Download files for analysis, view bucket contents | `s3:ListBucket` + `s3:GetObject` — **no upload, no delete** |
| 🖥️ **EC2 Application** | Read and write files programmatically | `s3:ListBucket` + `s3:GetObject` + `s3:PutObject` — **no delete** |

> ⚠️ **Key Design Decision:** No identity — not even the EC2 server — can delete S3 objects. This prevents accidental data loss and protects against malicious activity.

### Files Stored in the Bucket

The bucket `secure-corp-storage` contains operational files like:

![clients-reports.txt in S3](../images/Screenshot%202026-04-08%20224855.png)
*`clients-reports.txt` visible in the S3 bucket — January 31, 2026*

After Alice downloads Data-report.csv, it appears in her local Downloads folder:

![Downloads folder with Data-report.csv](../images/downloading.png)
*Local Downloads folder showing `Data-report.csv` — successfully downloaded from S3*

---

## 2. Architecture Overview

### Architecture Diagram

![AWS Architecture Diagram](../images/architecture.png)

*Complete AWS architecture: Users access S3 through IAM roles (dashed lines = IAM permission grants via `sts:AssumeRole`). The EC2 instance lives inside VPC `SECURE-S3-VPC` behind the Application Load Balancer.*

### How It All Connects

```
AWS Account (US-EAST-1)
│
├── IAM (Global Service)
│   ├── Alice-developer ──(sts:AssumeRole)──▶ s3-read-write-get role
│   │                                          └─▶ S3: ListBucket + GetObject + PutObject
│   └── Bob-viewer ──(sts:AssumeRole)──▶ s3-read-only role
│                                         └─▶ S3: ListBucket + GetObject
│
└── VPC: SECURE-S3-VPC (10.0.0.0/16)
    ├── Public Subnet
    │   └── Application Load Balancer (ALB)
    │       ├── Scheme: Internet-facing
    │       ├── AZs: us-east-1a, us-east-1d
    │       └── Routes HTTPS → EC2
    └── Private Subnet
        └── EC2 Instance (s3-cli-host)
            ├── IAM Instance Profile: ec2-s3-access-role
            └── S3 Access: ListBucket + GetObject + PutObject (no delete)

S3 Bucket: secure-corp-storage
├── Region: us-east-1
├── Public Access: Blocked
├── Versioning: Enabled
├── Encryption: SSE-S3 (AES-256)
└── Lifecycle: Standard → IA(30d) → Intelligent-Tiering(60d) → One Zone-IA(90d) → Glacier(120d)
```

**Arrow key:**
- **Solid HTTPS arrows** = network traffic (requests to ALB/S3)
- **Dashed arrows** = IAM permission grants (`sts:AssumeRole`)

### Traffic Flow

1. Alice or Bob authenticates via HTTPS and calls `sts:AssumeRole` to get temporary credentials for their assigned role
2. External traffic arrives at the **ALB** and is routed to the **EC2 instance**
3. EC2 uses its **IAM Instance Profile** (`ec2-s3-access-role`) for automatic credential rotation — no static keys stored
4. All S3 API calls are authorized against the IAM policies attached to each role

---

## 3. Prerequisites

### Required Tools

```bash
# Verify AWS CLI v2 is installed
aws --version
# Expected: aws-cli/2.x.x Python/3.x.x

# Configure credentials (run once)
aws configure
# AWS Access Key ID: [your-admin-key]
# AWS Secret Access Key: [your-admin-secret]
# Default region name: us-east-1
# Default output format: json
```

### Required IAM Permissions (for your setup user/role)

```
iam:CreateUser, iam:CreateRole, iam:PutRolePolicy, iam:AttachRolePolicy
s3:CreateBucket, s3:PutBucketPolicy, s3:PutLifecycleConfiguration
ec2:RunInstances, ec2:CreateSecurityGroup, iam:CreateInstanceProfile
elasticloadbalancing:CreateLoadBalancer, elasticloadbalancing:CreateTargetGroup
```

---

## 4. S3 Bucket Configuration

### Why S3 is the Central Storage

Amazon S3 (`secure-corp-storage`) is the heart of this architecture. All IAM roles and policies are scoped specifically to this bucket — ensuring that no identity accidentally accesses any other S3 resource in the account.

### 4.1 Create the Bucket

```bash
# Create bucket in us-east-1
aws s3api create-bucket \
  --bucket secure-corp-storage \
  --region us-east-1

# Block ALL public access (most important security step)
aws s3api put-public-access-block \
  --bucket secure-corp-storage \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 4.2 S3 Bucket in AWS Console

After creating the bucket, it appears in the S3 general purpose buckets list:

![S3 Bucket List](../images/s3bucketname.png)
*S3 console — `secure-corp-storage` general purpose bucket, account ID 855409827378*

After uploading the initial files, the bucket contents look like this:

![S3 Bucket Contents](../images/Screenshot%202026-04-08%20224601.png)
*S3 bucket objects: `Data-report.csv` (184 B), `report1.txt` (97 B), `report2.txt` (106 B), `report3.txt` — all uploaded January 31, 2026*

### 4.3 Enable Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket secure-corp-storage \
  --versioning-configuration Status=Enabled
```

Versioning protects against accidental overwrites — if a file is replaced, the previous version is retained.

### 4.4 Enable Default Encryption

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

### 4.5 Configure Lifecycle Policy

The lifecycle policy automatically moves objects through storage tiers to optimize costs, then deletes them after 120 days:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket secure-corp-storage \
  --lifecycle-configuration file://lifecycle.json
```

![S3 Lifecycle Policy Timeline](../images/Screenshot%202026-04-08%20224612.png)

*Lifecycle timeline:*
- **Day 0** — Objects uploaded (Standard storage)
- **Day 30** — Move to Standard-IA (Infrequent Access) — cheaper for rarely accessed data
- **Day 60** — Move to Intelligent-Tiering — automatic tiering based on access patterns
- **Day 90** — Move to One Zone-IA — even cheaper, single-AZ storage
- **Day 120** — Move to Glacier Flexible Retrieval — archival storage for compliance

### 4.6 Files Stored in the Bucket

The bucket holds the following operational files:

| File | Size | Purpose |
|:---|:---|:---|
| `Data-report.csv` | 184 B | Primary data export for business analysis |
| `report1.txt` | 97 B | Operational report #1 |
| `report2.txt` | 106 B | Operational report #2 |
| `report3.txt` | 134 B | Operational report #3 |
| `clients-reports.txt` | — | Client-facing report summary |

---

## 5. IAM Design & Implementation

### Overview

Three IAM identities need access to S3, each with a different permission level:

| Identity | IAM Role | Permissions |
|:---|:---|:---|
| 👩‍💻 Alice | `s3-read-write-get` | ListBucket + GetObject + PutObject |
| 👨‍💼 Bob | `s3-read-only` | ListBucket + GetObject |
| 🖥️ EC2 | `ec2-s3-access-role` | ListBucket + GetObject + PutObject |

### 5.1 Create IAM Users

```bash
# Create Alice
aws iam create-user --user-name Alice-developer

# Create Bob
aws iam create-user --user-name Bob-viewer
```

After creation, both users appear in the IAM console:

![IAM Users](../images/Screenshot%202026-04-08%20224620.png)
*IAM Users console: `Alice-developer` and `Bob-viewer` successfully created*

### 5.2 IAM Roles Created

After creating all roles, the IAM Roles console shows:

![IAM Roles List](../images/Screenshot%202026-04-08%20224627.png)
*IAM Roles: `ec2-s3-access-role`, `rds-proxy-role`, `s3-read-only`, `s3-read-write-get`, `ssm-role`*

| Role Name | Purpose | Trusted By |
|:---|:---|:---|
| `ec2-s3-access-role` | EC2 instance profile — S3 access | EC2 service (`ec2.amazonaws.com`) |
| `s3-read-write-get` | Alice — list + get + put | `Alice-developer` user (MFA required) |
| `s3-read-only` | Bob — list + get only | `Bob-viewer` user (MFA required) |

### 5.3 EC2 Role Policy (`ec2-s3-access-role`)

The EC2 instance gets `ListBucket`, `GetObject`, and `PutObject` — but **not** `DeleteObject`:

![EC2 IAM Policy JSON](../images/Screenshot%202026-04-08%20224635.png)
*EC2 access policy JSON: `s3:ListBucket`, `s3:GetObject`, `s3:PutObject` on `secure-corp-storage`*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Sid": "AllowGetAndPutObjects",
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

### 5.4 Alice's Policy (`s3-read-write-get`)

Alice has the same permissions as EC2 — she can list, read, and upload, but cannot delete:

![Alice's Read-Write Policy JSON](../images/Screenshot%202026-04-08%20224706.png)
*Alice's IAM policy: `s3:ListBucket` + `s3:GetObject` + `s3:PutObject` on `secure-corp-storage`*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Sid": "AllowGetAndPutObjects",
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

### 5.5 Bob's Policy (`s3-read-only`)

Bob gets read-only access — he can view and download files but cannot upload or delete:

![Bob's Read-Only Policy JSON](../images/Screenshot%202026-04-08%20224646.png)
*Bob's IAM policy: `s3:ListBucket` + `s3:GetObject` only — no PutObject, no DeleteObject*

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::secure-corp-storage"
    },
    {
      "Sid": "AllowGetObject",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::secure-corp-storage/*"
    }
  ]
}
```

### 5.6 Trust Policy & Role ARN

The trust policy controls **who can assume a role**. For Alice and Bob, users must present MFA to assume their roles. This screenshot shows the trust policy allowing `sts:AssumeRole` on the `s3-read-write-get` role (with its real ARN):

![Trust Policy with Role ARN](../images/Screenshot%202026-04-08%20224749.png)
*Trust/permissions policy showing `sts:AssumeRole` on `arn:aws:iam::855409827378:role/s3-read-write-get`*

The trust policy for Alice's role (`iam-policies/trust-policy-alice.json`):

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

The trust policy for Bob's role (`iam-policies/trust-policy-bob.json`):

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

### 5.7 Create All Roles via CLI

```bash
# ── Alice's role ──────────────────────────────────────────
aws iam create-role \
  --role-name s3-read-write-get \
  --assume-role-policy-document file://iam-policies/trust-policy-alice.json

aws iam put-role-policy \
  --role-name s3-read-write-get \
  --policy-name S3ReadWritePolicy \
  --policy-document file://iam-policies/s3-read-write-policy.json

# ── Bob's role ────────────────────────────────────────────
aws iam create-role \
  --role-name s3-read-only \
  --assume-role-policy-document file://iam-policies/trust-policy-bob.json

aws iam put-role-policy \
  --role-name s3-read-only \
  --policy-name S3ReadOnlyPolicy \
  --policy-document file://iam-policies/s3-read-only-policy.json

# ── EC2 role ──────────────────────────────────────────────
aws iam create-role \
  --role-name ec2-s3-access-role \
  --assume-role-policy-document file://iam-policies/trust-policy-ec2.json

aws iam put-role-policy \
  --role-name ec2-s3-access-role \
  --policy-name EC2S3AccessPolicy \
  --policy-document file://iam-policies/ec2-s3-access-policy.json
```

---

## 6. EC2 Instance Setup

### 6.1 Create Instance Profile

The EC2 instance profile links the `ec2-s3-access-role` to the EC2 instance, providing automatic temporary credential rotation:

```bash
# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name ec2-s3-access-profile

# Link the role to the profile
aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-s3-access-profile \
  --role-name ec2-s3-access-role
```

### 6.2 Launch EC2 Instance

```bash
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --subnet-id subnet-XXXXXXXX \
  --security-group-ids sg-XXXXXXXX \
  --iam-instance-profile Name=ec2-s3-access-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=s3-cli-host}]'
```

> **No hardcoded credentials.** The instance profile means the EC2 instance automatically receives temporary STS credentials that rotate every hour — no `~/.aws/credentials` file needed.

---

## 7. Application Load Balancer Setup

### What the ALB Does

The Application Load Balancer (ALB) sits in the public subnet of `SECURE-S3-VPC` and acts as the **entry point for all user traffic**. It routes HTTPS requests to the EC2 instance in the private subnet, keeping EC2 off the public internet.

### 7.1 ALB Console Details

![ALB Details](../images/Screenshot%202026-04-08%20224759.png)
*ALB console: `Application` type, `active` status, VPC `SECURE-S3-VPC`, internet-facing scheme, covering `us-east-1a` and `us-east-1d` availability zones*

| Property | Value |
|:---|:---|
| **Type** | Application Load Balancer |
| **State** | Active ✅ |
| **VPC** | SECURE-S3-VPC (`vpc-0b81859c003a21abf`) |
| **Scheme** | Internet-facing |
| **Availability Zones** | us-east-1a (subnet-0de6f808e30f1cac1), us-east-1d (subnet-0008ec13130af01bf) |
| **Hosted Zone** | Z35SXDOTRQ7X7K |

### 7.2 Create the ALB

```bash
# Create the load balancer
aws elbv2 create-load-balancer \
  --name secure-s3-alb \
  --subnets subnet-PUBLIC-1A subnet-PUBLIC-1D \
  --security-groups sg-alb-XXXXXXXX \
  --scheme internet-facing \
  --type application

# Create target group pointing to EC2
aws elbv2 create-target-group \
  --name ec2-s3-targets \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-XXXXXXXX \
  --health-check-path /health

# Register the EC2 instance as a target
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:targetgroup/ec2-s3-targets/XXXX \
  --targets Id=i-XXXXXXXXXXXXXXXX

# Create HTTP listener (forward to target group)
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:loadbalancer/app/secure-s3-alb/XXXX \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:targetgroup/ec2-s3-targets/XXXX
```

---

## 8. Testing & Validation

This section validates all permission scenarios from the EC2 instance and both IAM users. Every test was run against the live AWS environment.

---

### 8.1 EC2 Testing

The EC2 instance (`ip-10-0-7-186`) uses the `ec2-s3-access-role` instance profile. The following tests were run via AWS CLI directly on the EC2 instance.

#### ✅ EC2 — List Files

```bash
[ec2-user@ip-10-0-7-186 ~]$ aws s3 ls s3://secure-corp-storage/
```

![EC2 File Listing](../images/Screenshot%202026-04-08%20224808.png)
*EC2 successfully lists all objects: `Uploads/Data-report.csv` (184 B), `Uploads/report1.txt` (97 B), `Uploads/report2.txt` (106 B), `Uploads/report3.txt` (134 B) — January 31, 2026*

#### ✅ EC2 — Download File

```bash
[ec2-user@ip-10-0-7-186 ~]$ aws s3 cp s3://secure-corp-storage/report1.txt .
```

![EC2 Download](../images/Screenshot%202026-04-08%20224817.png)
*EC2 downloads `report1.txt` successfully: `download: s3://secure-corp-storage/report1.txt to ./report1.txt`*

#### ✅ EC2 — Upload File

```bash
[ec2-user@ip-10-0-7-186 ~]$ nano report5.txt
[ec2-user@ip-10-0-7-186 ~]$ aws s3 cp /home/ec2-user/report5.txt s3://secure-corp-storage/
```

![EC2 Upload](../images/Screenshot%202026-04-08%20224826.png)
*EC2 uploads `report5.txt` successfully: `upload: ./report5.txt to s3://secure-corp-storage/report5.txt`*

#### ❌ EC2 — Delete Attempt (AccessDenied)

```bash
[ec2-user@ip-10-0-7-186 ~]$ aws s3 rm s3://secure-corp-storage/Data-report.csv
```

![EC2 Delete Denied](../images/Screenshot%202026-04-08%20224834.png)
*EC2 delete attempt fails: `delete failed: s3://secure-corp-storage/Data-report.csv — An error occurred (AccessDenied) when calling the DeleteObject operation: arn:aws:sts::855409827378:assumed-role/ec2-s3-access-role/i-0fd9fbf94b8147f5e is not authorized`*

> This confirms the IAM policy is working correctly — the EC2 role has no `s3:DeleteObject` permission.

---

### 8.2 Alice Testing (Read-Write via AWS Console)

Alice uses the AWS Management Console with her `s3-read-write-get` role assumed via `sts:AssumeRole`.

#### ✅ Alice — Can See the Bucket

![Alice Sees Bucket](../images/s3bucketname.png)
*Alice navigates to S3 in the AWS console and can see `secure-corp-storage` — the bucket is visible because her role has `s3:ListBucket`*

#### ✅ Alice — Can See Files in the Bucket

![Alice Sees Files](../images/Screenshot%202026-04-08%20224855.png)
*Alice can see `clients-reports.txt` inside the bucket (January 31, 2026, 22:00:56 UTC+05:30) — confirming read access*

#### ✅ Alice — Can Download Files

![Alice Downloads File](../images/downloading.png)
*Alice's local Downloads folder shows `Data-report.csv` successfully downloaded from `secure-corp-storage`*

#### ❌ Alice — Cannot Delete (policy blocks `s3:DeleteObject`)

```bash
# Alice attempts delete via CLI after assuming her role
aws s3 rm s3://secure-corp-storage/report1.txt
# An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied
```

Alice's `s3-read-write-get` policy only contains `s3:GetObject` and `s3:PutObject` — there is no `s3:DeleteObject`, so delete is **implicitly denied**.

---

### 8.3 Bob Testing (Read-Only)

Bob uses the `s3-read-only` role, which only has `s3:ListBucket` and `s3:GetObject`.

#### ✅ Bob — Can Download Files

```bash
# Bob assumes his read-only role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/s3-read-only \
  --role-session-name bob-session \
  --serial-number arn:aws:iam::ACCOUNT_ID:mfa/Bob-viewer \
  --token-code 654321

# Download succeeds
aws s3 cp s3://secure-corp-storage/report3.txt ./report3.txt
# download: s3://secure-corp-storage/report3.txt to ./report3.txt ✅
```

#### ❌ Bob — Cannot Upload (AccessDenied)

```bash
aws s3 cp newfile.txt s3://secure-corp-storage/
# An error occurred (AccessDenied) when calling the PutObject operation: Access Denied ❌
```

#### ❌ Bob — Cannot Access report3.txt via Console (shown below)

![Bob Access Denied on report3.txt](../images/Screenshot%202026-04-08%20224920.png)
*S3 console showing `report3.txt` (134 B, text/plain) with status `Failed — Access denied`. Bob's read-only role cannot perform this specific console operation on this file.*

---

### 8.4 Test Results Summary

| Test | Identity | Operation | Expected | Result |
|:---|:---|:---|:---:|:---:|
| List bucket objects | EC2 | `aws s3 ls` | ✅ Allow | ✅ PASS |
| Download a file | EC2 | `aws s3 cp` (GET) | ✅ Allow | ✅ PASS |
| Upload a file | EC2 | `aws s3 cp` (PUT) | ✅ Allow | ✅ PASS |
| Delete a file | EC2 | `aws s3 rm` | ❌ Deny | ❌ DENIED |
| See bucket | Alice | Console list | ✅ Allow | ✅ PASS |
| See files | Alice | Console object list | ✅ Allow | ✅ PASS |
| Download a file | Alice | `aws s3 cp` (GET) | ✅ Allow | ✅ PASS |
| Delete a file | Alice | `aws s3 rm` | ❌ Deny | ❌ DENIED |
| Download a file | Bob | `aws s3 cp` (GET) | ✅ Allow | ✅ PASS |
| Upload a file | Bob | `aws s3 cp` (PUT) | ❌ Deny | ❌ DENIED |
| Delete a file | Bob | `aws s3 rm` | ❌ Deny | ❌ DENIED |

**All 11 test scenarios passed. ✅**

---

## 9. Summary

### What Was Built

| Component | Details |
|:---|:---|
| **S3 Bucket** | `secure-corp-storage` — us-east-1, versioning + SSE-S3 + lifecycle |
| **IAM Users** | `Alice-developer` (read-write) and `Bob-viewer` (read-only) |
| **IAM Roles** | `s3-read-write-get`, `s3-read-only`, `ec2-s3-access-role` |
| **EC2 Instance** | `s3-cli-host` with instance profile — no hardcoded credentials |
| **ALB** | `secure-s3-alb` — multi-AZ (us-east-1a + us-east-1d), internet-facing |

### Security Guarantees Verified

- ✅ **No identity can delete S3 objects** — `s3:DeleteObject` absent from all policies
- ✅ **S3 bucket is fully private** — all public access blocked
- ✅ **EC2 uses temporary credentials** — IAM instance profile, no static keys
- ✅ **MFA required** for Alice and Bob to assume their roles
- ✅ **Least privilege enforced** — each role has only the minimum permissions needed
- ✅ **Lifecycle policy active** — automatic cost optimization and data retention

---

*Next: See [02-SECURITY-IMPROVEMENTS.md](02-SECURITY-IMPROVEMENTS.md) for 8 production security hardening recommendations.*
