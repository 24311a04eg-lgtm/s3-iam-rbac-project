# 🔐 AWS S3 IAM Role-Based Access Control (RBAC) Project

[![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20IAM%20%7C%20EC2%20%7C%20ALB-orange?logo=amazon-aws)](https://aws.amazon.com)
[![Region](https://img.shields.io/badge/Region-US--East--1-blue)](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
[![Security](https://img.shields.io/badge/Security-Least%20Privilege-red)](docs/02-SECURITY-IMPROVEMENTS.md)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)]()

---

## 🎯 Use Case: Real-World Scenario

> **Why does this project exist?**

Organizations store critical files — client reports, financial data, operational documents — in Amazon S3. The challenge is: **not everyone should have the same level of access.**

Imagine a company called **SecureCorp** that needs to manage access to sensitive files stored in an S3 bucket called `secure-corp-storage`:

- 👩‍💻 **Alice** is a developer who needs to **read and write** files (upload reports, download data) — but should **never delete** anything accidentally
- 👨‍💼 **Bob** is a business analyst who only needs to **read and download** files — he should not be able to modify or delete anything
- 🖥️ **EC2 Application** needs to **read and write** files programmatically — no hardcoded credentials, no delete access

Without proper access controls, anyone could accidentally delete critical client data, or a compromised credential could expose the entire bucket. This project solves that problem using **AWS IAM Role-Based Access Control (RBAC)**.

> **The solution:** Each identity gets *exactly* the permissions they need — nothing more, nothing less. This is the **Principle of Least Privilege**.

---

## 📦 Project Overview

This project implements a **production-grade S3 access control system** across 6 core pillars:

| 🔒 Secure S3 Access | 👥 Users & Permissions | 🖥️ EC2 Instance |
|:---:|:---:|:---:|
| S3 bucket with public access blocked, versioning enabled, and SSE-S3 encryption | Two IAM users (Alice — read/write, Bob — read-only) with role-based policies | EC2 host using IAM instance profile — no hardcoded credentials |

| ⚖️ ALB Integration | 🛠️ Core Services | 🛡️ Security Focus |
|:---:|:---:|:---:|
| Application Load Balancer in SECURE-S3-VPC routing traffic to EC2 | S3, IAM, EC2, ALB, VPC all integrated in us-east-1 | Least privilege, no delete for any user, MFA on role assumption |

---

## 🏗️ AWS Architecture

![AWS Architecture Diagram](images/architecture.png)

*The diagram above shows the complete architecture: Users (Alice, Bob) access S3 through IAM roles (solid HTTPS arrows = network traffic, dashed arrows = IAM permission grants). The EC2 instance sits inside VPC `SECURE-S3-VPC` behind an Application Load Balancer.*

**Architecture flow:**
1. **Alice** and **Bob** authenticate via HTTPS and assume their respective IAM roles using `sts:AssumeRole`
2. The **Application Load Balancer (ALB)** receives external traffic and routes it to the **EC2 instance** inside the VPC
3. The **EC2 instance** uses an **IAM Instance Profile** (`ec2-s3-access-role`) to access S3 — no static keys stored on the server
4. All traffic to **S3** (`secure-corp-storage`) is authenticated and authorized through IAM policies

---

## 👥 Access Permissions Matrix

| Identity | Role | List Bucket | Download (GET) | Upload (PUT) | Delete |
|:---|:---|:---:|:---:|:---:|:---:|
| 👩‍💻 **Alice** (Developer) | `s3-read-write-get` | ✅ | ✅ | ✅ | ❌ |
| 👨‍💼 **Bob** (Viewer) | `s3-read-only` | ✅ | ✅ | ❌ | ❌ |
| 🖥️ **EC2 Instance** | `ec2-s3-access-role` | ✅ | ✅ | ✅ | ❌ |

> ⚠️ **No identity can delete S3 objects.** This is a deliberate security design — it prevents accidental or malicious data loss.

---

## 📸 Real AWS Console Evidence

### S3 Bucket — `secure-corp-storage`

| S3 Bucket List | Bucket Contents |
|:---:|:---:|
| ![S3 Bucket List](images/s3bucketname.png) | ![S3 Bucket Contents](images/Screenshot%202026-04-08%20224601.png) |
| *S3 general purpose bucket `secure-corp-storage` in us-east-1* | *Files stored: Data-report.csv, report1.txt, report2.txt, report3.txt* |

### IAM Configuration

| IAM Users | IAM Roles |
|:---:|:---:|
| ![IAM Users](images/Screenshot%202026-04-08%20224620.png) | ![IAM Roles](images/Screenshot%202026-04-08%20224627.png) |
| *Alice-developer and Bob-viewer created in IAM* | *ec2-s3-access-role, s3-read-only, s3-read-write-get roles* |

### EC2 Operations — All Scenarios Tested

| List ✅ | Download ✅ | Upload ✅ | Delete ❌ |
|:---:|:---:|:---:|:---:|
| ![EC2 List](images/Screenshot%202026-04-08%20224808.png) | ![EC2 Download](images/Screenshot%202026-04-08%20224817.png) | ![EC2 Upload](images/Screenshot%202026-04-08%20224826.png) | ![EC2 Delete Denied](images/Screenshot%202026-04-08%20224834.png) |
| *`aws s3 ls` succeeds* | *`aws s3 cp` download succeeds* | *`aws s3 cp` upload succeeds* | *`aws s3 rm` → AccessDenied* |

---

## 🚀 Quick Start

### Prerequisites
- AWS CLI v2 installed and configured (`aws configure`)
- IAM permissions to create users, roles, policies, S3 buckets, and EC2 instances
- An existing VPC with public and private subnets

### Setup (4 steps)

```bash
# Step 1: Make all scripts executable
chmod +x scripts/*.sh

# Step 2: Create IAM users, roles, and policies
./scripts/setup-iam.sh

# Step 3: Create and configure the S3 bucket
./scripts/setup-s3.sh

# Step 4: Launch EC2 instance and Application Load Balancer
./scripts/setup-ec2.sh
```

### Validate Permissions

```bash
# Run all permission tests (EC2, Alice, Bob scenarios)
./scripts/test-permissions.sh
```

### Clean Up Resources

```bash
# Tear down all AWS resources created by this project
./scripts/cleanup.sh
```

---

## 📁 Repository Structure

```
s3-iam-rbac-project/
│
├── README.md                          # This file — overview & architecture
│
├── docs/
│   ├── 01-PROJECT-SETUP.md            # Complete setup walkthrough with screenshots
│   ├── 02-SECURITY-IMPROVEMENTS.md    # 8 production security hardening steps
│   └── 03-TESTING-VALIDATION.md       # Full validation suite with test evidence
│
├── iam-policies/
│   ├── ec2-s3-access-policy.json      # EC2 role: s3:ListBucket + GetObject + PutObject
│   ├── s3-read-write-policy.json      # Alice: s3:ListBucket + GetObject + PutObject
│   ├── s3-read-only-policy.json       # Bob: s3:ListBucket + GetObject only
│   ├── trust-policy-ec2.json          # Trust relationship: EC2 service
│   ├── trust-policy-alice.json        # Trust relationship: Alice-developer (MFA)
│   └── trust-policy-bob.json          # Trust relationship: Bob-viewer (MFA)
│
├── scripts/
│   ├── setup-iam.sh                   # Create IAM users, roles, and policies
│   ├── setup-s3.sh                    # Create and configure S3 bucket
│   ├── setup-ec2.sh                   # Launch EC2 instance + ALB
│   ├── test-permissions.sh            # Validate all allow/deny scenarios
│   └── cleanup.sh                     # Tear down all AWS resources
│
└── images/                            # Real AWS console screenshots
    ├── architecture.png               # Full AWS architecture diagram
    ├── s3bucketname.png               # S3 bucket list — secure-corp-storage
    ├── downloading.png                # Alice downloading Data-report.csv
    ├── Screenshot 2026-04-08 224601.png  # S3 bucket contents (all files)
    ├── Screenshot 2026-04-08 224612.png  # S3 lifecycle policy timeline
    ├── Screenshot 2026-04-08 224620.png  # IAM users (Alice-developer, Bob-viewer)
    ├── Screenshot 2026-04-08 224627.png  # IAM roles list
    ├── Screenshot 2026-04-08 224635.png  # EC2/Alice IAM policy JSON
    ├── Screenshot 2026-04-08 224646.png  # Bob's read-only policy JSON
    ├── Screenshot 2026-04-08 224706.png  # Alice's read-write policy JSON
    ├── Screenshot 2026-04-08 224749.png  # Trust policy with role ARN
    ├── Screenshot 2026-04-08 224759.png  # ALB details (Active, VPC, AZs)
    ├── Screenshot 2026-04-08 224808.png  # EC2: aws s3 ls (file listing)
    ├── Screenshot 2026-04-08 224817.png  # EC2: aws s3 cp (download)
    ├── Screenshot 2026-04-08 224826.png  # EC2: aws s3 cp (upload)
    ├── Screenshot 2026-04-08 224834.png  # EC2: aws s3 rm → AccessDenied
    ├── Screenshot 2026-04-08 224855.png  # Alice's view of bucket files
    └── Screenshot 2026-04-08 224920.png  # Report3.txt — Access Denied (Bob test)
```

---

## 🔒 Security Highlights

| Principle | Implementation |
|:---|:---|
| **Least Privilege** | Each identity has only the permissions it needs |
| **No Delete Access** | `s3:DeleteObject` is absent from all three policies |
| **No Public Access** | S3 bucket has all public access blocked |
| **Encryption at Rest** | SSE-S3 (AES-256) on all objects |
| **No Static Keys on EC2** | IAM instance profile provides temporary credentials |
| **MFA on Role Assumption** | Alice and Bob must use MFA to assume their roles |
| **Versioning Enabled** | Protects against accidental overwrites |
| **Lifecycle Policy** | Auto-tiers objects to cheaper storage, then deletes at day 120 |

---

## 📚 Full Documentation

| Document | Description |
|:---|:---|
| [📖 01-PROJECT-SETUP.md](docs/01-PROJECT-SETUP.md) | Complete walkthrough: S3, IAM, EC2, ALB setup with real screenshots at each step |
| [🛡️ 02-SECURITY-IMPROVEMENTS.md](docs/02-SECURITY-IMPROVEMENTS.md) | 8 production security hardening recommendations |
| [✅ 03-TESTING-VALIDATION.md](docs/03-TESTING-VALIDATION.md) | Full test suite: EC2, Alice, Bob permission validation with evidence |

---

## 🛠️ AWS Services Used

| Service | Purpose | Configuration |
|:---|:---|:---|
| **Amazon S3** | Secure object storage | Bucket `secure-corp-storage`, versioning + SSE-S3 |
| **AWS IAM** | Identity & access management | 3 roles, 2 users, 6 policy documents |
| **Amazon EC2** | Application/CLI host | Instance profile, no hardcoded credentials |
| **AWS ALB** | Load balancer & entry point | Multi-AZ: us-east-1a + us-east-1d |
| **Amazon VPC** | Network isolation | `SECURE-S3-VPC` (10.0.0.0/16) |

---

## 📜 License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

*Built with ❤️ using AWS best practices for production-grade S3 access control*