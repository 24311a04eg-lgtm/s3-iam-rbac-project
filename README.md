# 🔐 AWS S3 IAM Role-Based Access Control (RBAC) Project

[![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20IAM%20%7C%20EC2%20%7C%20ALB-orange?logo=amazon-aws)](https://aws.amazon.com)
[![Region](https://img.shields.io/badge/Region-US--East--1-blue)](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Security](https://img.shields.io/badge/Security-Least%20Privilege-red)](docs/02-SECURITY-IMPROVEMENTS.md)

> A production-ready, secure S3 access control system built with AWS IAM roles, policies, and least-privilege principles. Features two IAM users (Alice - read/write, Bob - read-only) and an EC2 instance accessing S3 through an Application Load Balancer in **US-EAST-1**.

---

## 🏗️ Architecture Diagram

![Architecture Diagram](images/20-architecture-diagram.jpg)

> **AWS Account (US-EAST-1)** → **VPC: SECURE-S3-VPC** → **Public Subnet** → **ALB** → **EC2 (AWS CLI Host)** → **IAM Roles** → **S3: secure-corp-storage**

---

## 📋 Project Overview

This project demonstrates enterprise-grade S3 access control using AWS Identity and Access Management (IAM) with role-based policies. The system enforces the **principle of least privilege** — each identity only gets the permissions they absolutely need.

### Access Control Matrix

| Identity | List Bucket | Download (GET) | Upload (PUT) | Delete | Role |
|---|:---:|:---:|:---:|:---:|---|
| **Alice** (Developer) | ✅ | ✅ | ✅ | ❌ | `s3-read-write-get` |
| **Bob** (Viewer) | ✅ | ✅ | ❌ | ❌ | `s3-read-only` |
| **EC2 Instance** | ✅ | ✅ | ✅ | ❌ | `ec2-s3-access-role` |

### IAM Users

| User | Username | Access Level | Role Assigned |
|---|---|---|---|
| Alice | `Alice-developer` | Read + Write (no delete) | `s3-read-write-get` |
| Bob | `Bob-viewer` | Read-Only | `s3-read-only` |

### S3 Bucket

| Property | Value |
|---|---|
| Bucket Name | `secure-corp-storage` |
| Region | US East (N. Virginia) `us-east-1` |
| Public Access | **Blocked** |
| Versioning | Enabled |
| Encryption | SSE-S3 (AES-256) |
| Lifecycle Policy | Standard → IA (30d) → Glacier (60d) → Deep Archive (90d) → Delete (120d) |

---

## 🛠️ Tech Stack

| Service | Purpose |
|---|---|
| **Amazon S3** | Secure object storage for reports and data |
| **AWS IAM** | Identity & Access Management with role-based policies |
| **Amazon EC2** | Application server / AWS CLI host |
| **AWS ALB** | Application Load Balancer routing traffic to EC2 |
| **AWS VPC** | Network isolation (SECURE-S3-VPC) |
| **AWS CLI** | Command-line S3 operations from EC2 |

---

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured (`aws configure`)
- Sufficient IAM permissions to create users, roles, and policies
- An existing VPC with public and private subnets

### 1. Set up IAM (Users, Roles, Policies)
```bash
chmod +x scripts/*.sh
./scripts/setup-iam.sh
```

### 2. Set up S3 Bucket
```bash
./scripts/setup-s3.sh
```

### 3. Launch EC2 Instance & ALB
```bash
./scripts/setup-ec2.sh
```

### 4. Validate All Permissions
```bash
./scripts/test-permissions.sh
```

### 5. Clean Up Resources
```bash
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
│   ├── 01-PROJECT-SETUP.md            # Complete setup guide with all screenshots
│   ├── 02-SECURITY-IMPROVEMENTS.md    # 8 production security improvements
│   └── 03-TESTING-VALIDATION.md       # Full test suite with evidence
│
├── iam-policies/
│   ├── ec2-s3-access-policy.json      # EC2 instance: list + get + put (no delete)
│   ├── s3-read-write-policy.json      # Alice: list + get + put (no delete)
│   ├── s3-read-only-policy.json       # Bob: list + get only
│   ├── trust-policy-ec2.json          # EC2 service trust relationship
│   ├── trust-policy-alice.json        # Alice role trust relationship (MFA)
│   └── trust-policy-bob.json          # Bob role trust relationship (MFA)
│
├── scripts/
│   ├── setup-iam.sh                   # Create users, roles, policies
│   ├── setup-s3.sh                    # Create and configure S3 bucket
│   ├── setup-ec2.sh                   # Launch EC2 + ALB
│   ├── test-permissions.sh            # Validate all allow/deny scenarios
│   └── cleanup.sh                     # Tear down all resources
│
└── images/                            # AWS console screenshots (real)
    ├── 01-clients-reports.txt.jpg     # clients-reports.txt file
    ├── 02-downloads-folder.jpg        # Downloads folder with Data-report.csv
    ├── 03-s3-general-buckets.jpg      # S3 buckets list — secure-corp-storage
    ├── 04-s3-bucket-contents.jpg      # S3 contents — Access denied on report3.txt
    ├── 05-ec2-download.jpg            # EC2 downloading report1.txt from S3
    ├── 06-ec2-upload.jpg              # EC2 uploading report5.txt to S3
    ├── 07-ec2-delete-denied.jpg       # EC2 AccessDenied on delete
    ├── 08-s3-console.jpg              # S3 console — secure-corp-storage
    ├── 09-iam-trust-read-only.jpg     # IAM trust policy for s3-read-only
    ├── 10-iam-trust-write-get.jpg     # IAM trust policy for s3-read-write-get
    ├── 11-alb-details.jpg             # ALB — Active, VPC, AZs
    ├── 12-ec2-uploads-list.jpg        # EC2 S3 file listing with timestamps
    ├── 13-iam-users.jpg               # IAM Users — Alice-developer, Bob-viewer
    ├── 14-iam-roles.jpg               # IAM Roles list
    ├── 15-s3-read-write-policy.jpg    # Alice's policy JSON
    ├── 16-s3-read-only-policy.jpg     # Bob's policy JSON
    ├── 17-s3-bucket-details.jpg       # S3 bucket details — secure-corp-storage
    ├── 18-s3-bucket-contents-files.jpg # S3 contents — all report files
    ├── 19-s3-lifecycle-policy.jpg     # S3 lifecycle transitions
    └── 20-architecture-diagram.jpg    # Architecture diagram (COMPULSORY)
```

---

## 📸 Real AWS Console Screenshots

### S3 Bucket
| S3 Buckets List | Bucket Contents |
|---|---|
| ![S3 Buckets](images/03-s3-general-buckets.jpg) | ![Bucket Contents](images/18-s3-bucket-contents-files.jpg) |

### IAM Configuration
| IAM Users | IAM Roles |
|---|---|
| ![IAM Users](images/13-iam-users.jpg) | ![IAM Roles](images/14-iam-roles.jpg) |

### EC2 Operations
| Download ✅ | Upload ✅ | Delete ❌ |
|---|---|---|
| ![EC2 Download](images/05-ec2-download.jpg) | ![EC2 Upload](images/06-ec2-upload.jpg) | ![EC2 Delete Denied](images/07-ec2-delete-denied.jpg) |

---

## 📚 Documentation

| Document | Description |
|---|---|
| [01-PROJECT-SETUP.md](docs/01-PROJECT-SETUP.md) | Complete walkthrough: S3, IAM, EC2, ALB setup with screenshots |
| [02-SECURITY-IMPROVEMENTS.md](docs/02-SECURITY-IMPROVEMENTS.md) | 8 production security hardening recommendations |
| [03-TESTING-VALIDATION.md](docs/03-TESTING-VALIDATION.md) | Full validation suite: EC2, Alice, Bob permission tests |

---

## 🔒 Security Highlights

- ✅ **Principle of Least Privilege** — no identity has more access than needed
- ✅ **No Delete permissions** for any user or EC2 role
- ✅ **S3 Public Access fully blocked**
- ✅ **Bucket-level encryption** (SSE-S3)
- ✅ **IAM roles over long-term access keys** for EC2
- ✅ **MFA enforcement** on Alice and Bob trust policies
- ✅ **S3 Versioning** enabled for accidental-overwrite protection
- ✅ **Lifecycle policy** to manage storage costs automatically

---

## 📜 License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

*Built with ❤️ using AWS best practices for production-grade S3 access control*