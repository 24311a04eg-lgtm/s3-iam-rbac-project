# 🔐 AWS S3 IAM Role-Based Access Control (RBAC) Project

[![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20IAM%20%7C%20EC2%20%7C%20ALB-orange?logo=amazon-aws)](https://aws.amazon.com)
[![Region](https://img.shields.io/badge/Region-US--East--1-blue)](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
[![IAM](https://img.shields.io/badge/IAM-Least%20Privilege-red?logo=amazon-aws)](docs/02-SECURITY-IMPROVEMENTS.md)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](docs/03-TESTING-VALIDATION.md)

> A production-ready, enterprise-grade S3 access control system built with AWS IAM roles, policies, and the principle of least privilege. Features two IAM users (Alice – read/write, Bob – read-only) and an EC2 instance accessing S3 through an Application Load Balancer, all deployed in **US-EAST-1**.

---

## 📌 Real-World Use Case

> **The Problem:** A company stores sensitive client reports, data exports, and operational files in Amazon S3. Different teams need different levels of access — developers need to upload files, managers need to read them, and applications need to automate both. But **nobody should be able to delete production data by accident**.

This project solves that exact problem using **AWS IAM Role-Based Access Control**:

| Who | What They Need | What They Get |
|---|---|---|
| 👩‍💻 **Alice** (Developer) | Upload & download reports | Read + Write access (no delete) |
| 👨‍💼 **Bob** (Manager/Viewer) | View and download reports only | Read-only access |
| 🖥️ **EC2 Application** | Automate file operations | Read + Write via instance role (no delete) |
| 🚫 **Everyone** | Should never delete prod data | DeleteObject is denied for all |

The files stored in the bucket include operational reports like `clients-reports.txt`, `Data-report.csv`, and `report1.txt` through `report5.txt`:

![S3 Bucket Contents](<images/Screenshot 2026-04-08 224601.png>)
*S3 bucket showing stored report files — Data-report.csv, report1.txt, report2.txt, report3.txt with sizes and timestamps*

![S3 file](<images/Screenshot 2026-04-08 224855.png>)
*clients-reports.txt — a client report file stored securely in the S3 bucket*

---

## 🗂️ Project Overview

This project implements **six key components** working together to form a secure, scalable access control system:

| Component | Service | Purpose |
|---|---|---|
| 🪣 **Secure S3 Access** | Amazon S3 | Central, encrypted file storage with versioning and lifecycle management |
| 👥 **Users & Permissions** | AWS IAM | Role-based policies for Alice (read-write) and Bob (read-only) |
| 🖥️ **EC2** | Amazon EC2 | Application server that interacts with S3 using a secure instance profile |
| ⚖️ **ALB** | AWS ALB | Application Load Balancer routing external HTTPS traffic to EC2 |
| 🔒 **Services** | AWS VPC | Network isolation keeping all resources inside `SECURE-S3-VPC` |
| 🛡️ **Security** | IAM Policies | MFA enforcement, no long-term keys on EC2, no delete for anyone |

---

## 🏗️ AWS Architecture Diagram

![Architecture Diagram](images/architecture.png)

The architecture shows:

1. **External clients** (Alice, Bob) connect over **HTTPS/443** to IAM, and assume their respective roles
2. **Alice** assumes `S3READWRITEROLE` → can list, get, and put objects in S3
3. **Bob** assumes `S3READONLYROLE` → can only list and get objects in S3
4. **Internet traffic** enters through the **Application Load Balancer** (public subnet `10.0.1.0/24`)
5. ALB forwards requests to the **EC2 instance** (AWS CLI host) inside `SECURE-S3-VPC` (`10.0.0.0/16`)
6. EC2 uses `EC2S3ACCESSROLE` via its **instance profile** — no static credentials stored
7. All roles use `sts:AssumeRole` to obtain **temporary credentials** — no long-term access keys

> **Key security insight:** Solid lines show allowed access paths. Each identity (Alice, Bob, EC2) can only reach what their specific IAM policy permits. No path exists for deleting objects.

---

## 📋 Permission Matrix

| Identity | Role | List Bucket | Download (GET) | Upload (PUT) | Delete |
|---|:---:|:---:|:---:|:---:|:---:|
| **Alice** (Developer) | `s3-read-write-get` | ✅ | ✅ | ✅ | ❌ |
| **Bob** (Viewer) | `s3-read-only` | ✅ | ✅ | ❌ | ❌ |
| **EC2 Instance** | `ec2-s3-access-role` | ✅ | ✅ | ✅ | ❌ |

### IAM Users

![IAM Users](<images/Screenshot 2026-04-08 224620.png>)
*IAM Users — Alice-developer and Bob-viewer created in AWS account 855409827378*

| Username | Access Type | Assigned Role |
|---|---|---|
| `Alice-developer` | Console + Programmatic | `s3-read-write-get` |
| `Bob-viewer` | Console + Programmatic | `s3-read-only` |

### IAM Roles

![IAM Roles](<images/Screenshot 2026-04-08 224627.png>)
*IAM Roles — ec2-s3-access-role, s3-read-only, s3-read-write-get, and supporting roles*

### S3 Bucket

| Property | Value |
|---|---|
| Bucket Name | `secure-corp-storage` |
| Region | US East (N. Virginia) `us-east-1` |
| Public Access | **Blocked** |
| Versioning | Enabled |
| Encryption | SSE-S3 (AES-256) |
| Lifecycle Policy | Standard → IA (30d) → Intelligent-Tiering (60d) → One Zone-IA (90d) → Glacier (120d) |

---

## 🚀 Quick Start Guide

### Prerequisites
- AWS CLI v2 configured (`aws configure`) with `us-east-1` as default region
- IAM permissions to create users, roles, policies, S3 buckets, EC2, and ALB resources

### Step 1 — Set Up IAM (Users, Roles, Policies)
```bash
chmod +x scripts/*.sh
./scripts/setup-iam.sh
```

### Step 2 — Set Up S3 Bucket
```bash
./scripts/setup-s3.sh
```

### Step 3 — Launch EC2 Instance with Instance Profile
```bash
./scripts/setup-ec2.sh
```

### Step 4 — Validate All Permissions
```bash
./scripts/test-permissions.sh
```

### Step 5 — Clean Up Resources When Done
```bash
./scripts/cleanup.sh
```

---

## 📁 Repository Structure

```
s3-iam-rbac-project/
│
├── README.md                          # This file — overview, use case & architecture
│
├── docs/
│   ├── 01-PROJECT-SETUP.md            # Complete setup walkthrough with screenshots
│   ├── 02-SECURITY-IMPROVEMENTS.md    # 8 production security hardening recommendations
│   ├── 03-TESTING-VALIDATION.md       # Full permission test suite with evidence
│   └── 04-PDF-REFERENCE.md            # Image-to-section reference guide
│
├── iam-policies/
│   ├── ec2-s3-access-policy.json      # EC2: list + get + put (no delete)
│   ├── s3-read-write-policy.json      # Alice: list + get + put (no delete)
│   ├── s3-read-only-policy.json       # Bob: list + get only
│   ├── trust-policy-ec2.json          # EC2 service trust relationship
│   ├── trust-policy-alice.json        # Alice trust relationship (MFA required)
│   └── trust-policy-bob.json          # Bob trust relationship (MFA required)
│
├── scripts/
│   ├── setup-iam.sh                   # Create users, roles, policies
│   ├── setup-s3.sh                    # Create and configure S3 bucket
│   ├── setup-ec2.sh                   # Launch EC2 + ALB
│   ├── test-permissions.sh            # Validate all allow/deny scenarios
│   └── cleanup.sh                     # Tear down all resources
│
└── images/                            # AWS console screenshots (real evidence)
    ├── architecture.png               # Full AWS architecture diagram
    ├── s3bucketname.png               # S3 bucket list — secure-corp-storage created
    ├── Screenshot 2026-04-08 224601.png  # S3 bucket contents (4 report files)
    ├── Screenshot 2026-04-08 224612.png  # S3 lifecycle policy transitions
    ├── Screenshot 2026-04-08 224620.png  # IAM Users — Alice-developer, Bob-viewer
    ├── Screenshot 2026-04-08 224627.png  # IAM Roles — all 5 roles listed
    ├── Screenshot 2026-04-08 224635.png  # EC2/Alice policy JSON (list+get+put)
    ├── Screenshot 2026-04-08 224646.png  # Bob policy JSON (list+get only)
    ├── Screenshot 2026-04-08 224706.png  # EC2 trust policy (ec2.amazonaws.com)
    ├── Screenshot 2026-04-08 224749.png  # Alice user policy to assume role
    ├── Screenshot 2026-04-08 224759.png  # ALB details (active, multi-AZ)
    ├── Screenshot 2026-04-08 224808.png  # EC2 CLI: s3 ls — 4 files listed ✅
    ├── Screenshot 2026-04-08 224817.png  # EC2 CLI: s3 cp download — success ✅
    ├── Screenshot 2026-04-08 224826.png  # EC2 CLI: s3 cp upload — success ✅
    ├── Screenshot 2026-04-08 224834.png  # EC2 CLI: s3 rm — AccessDenied ❌
    ├── Screenshot 2026-04-08 224855.png  # S3 file: clients-reports.txt
    ├── Screenshot 2026-04-08 224920.png  # Bob: report3.txt Access denied ❌
    └── downloading.png                   # Local downloads folder — Data-report.csv
```

---

## 📸 Real AWS Console Evidence

### S3 Bucket
| Bucket Created | Files Stored |
|---|---|
| ![S3 Bucket](images/s3bucketname.png) | ![S3 Contents](<images/Screenshot 2026-04-08 224601.png>) |

### IAM Configuration
| Users | Roles |
|---|---|
| ![IAM Users](<images/Screenshot 2026-04-08 224620.png>) | ![IAM Roles](<images/Screenshot 2026-04-08 224627.png>) |

### EC2 Operations Proof
| List ✅ | Download ✅ |
|---|---|
| ![EC2 List](<images/Screenshot 2026-04-08 224808.png>) | ![EC2 Download](<images/Screenshot 2026-04-08 224817.png>) |

| Upload ✅ | Delete ❌ |
|---|---|
| ![EC2 Upload](<images/Screenshot 2026-04-08 224826.png>) | ![EC2 Delete Denied](<images/Screenshot 2026-04-08 224834.png>) |

---

## 📚 Documentation

| Document | Description |
|---|---|
| [01-PROJECT-SETUP.md](docs/01-PROJECT-SETUP.md) | Complete step-by-step setup: S3, IAM, EC2, ALB with screenshots at each stage |
| [02-SECURITY-IMPROVEMENTS.md](docs/02-SECURITY-IMPROVEMENTS.md) | 8 production security hardening recommendations |
| [03-TESTING-VALIDATION.md](docs/03-TESTING-VALIDATION.md) | Full permission validation: EC2, Alice, and Bob test scenarios |
| [04-PDF-REFERENCE.md](docs/04-PDF-REFERENCE.md) | Image-to-section mapping and visual learning path |

---

## 🔒 Security Highlights & Compliance

### Principle of Least Privilege
Every identity has **only the permissions they absolutely need** — nothing more.

- ✅ **No delete permissions** for any user, role, or EC2 instance
- ✅ **S3 public access fully blocked** — bucket is private by default
- ✅ **Bucket-level encryption** with SSE-S3 (AES-256)
- ✅ **IAM roles over long-term keys** — EC2 uses instance profile with temporary credentials
- ✅ **MFA required** for Alice and Bob to assume their roles
- ✅ **S3 Versioning enabled** — protects against accidental overwrites
- ✅ **Lifecycle policy** — automatically transitions data to cheaper storage tiers
- ✅ **VPC isolation** — all resources inside `SECURE-S3-VPC`, no unnecessary public exposure

### Compliance-Aligned Design
| Control | Implementation |
|---|---|
| Access Control | IAM roles with scoped resource ARNs |
| Audit Trail | CloudTrail captures all S3 and IAM API calls |
| Data Protection | SSE-S3 encryption at rest, HTTPS in transit |
| Change Prevention | No `s3:DeleteObject` in any policy |
| Identity Verification | MFA condition on all human role assumptions |

---

## 📜 License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

*Built with ❤️ using AWS best practices for production-grade S3 access control*
