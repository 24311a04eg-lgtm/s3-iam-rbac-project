# 🔐 S3 Vault: IAM-Driven Access Management

![Architecture Diagram](images/01-architecture.png)

Secure role-based access to Amazon S3 using AWS Identity and Access Management (IAM).
Implements least-privilege access where:

- **Alice** → Read, Write, Upload
- **Bob** → Read-only
- **EC2** → Controlled access via IAM Role (no hardcoded credentials)

---

## 📌 Overview

Organizations store critical data in S3, but without proper access control, files can be accidentally modified or deleted.

This project demonstrates a Role-Based Access Control (RBAC) model using IAM roles and policies to enforce:

- Least privilege access
- Secure credential management (no access keys)
- Controlled S3 operations per user role

**Problem:** Unrestricted access to S3 leads to accidental or unauthorized changes

**Solution:** Fine-grained IAM roles with enforced permissions

---

## 🏗️ Architecture

### Components

- **VPC**: Isolated network (`10.0.0.0/16`) with a public subnet
- **Application Load Balancer (ALB)**: Acts as an entry point for incoming traffic and simulates a production-ready architecture  
  *(Note: Included for extensibility; core access control is handled by IAM)*
- **Amazon EC2**: Hosts AWS CLI and interacts with S3 using an IAM instance profile
- **AWS Identity and Access Management (IAM)**: Defines roles and policies:
  - `s3-read-write-get` → Alice
  - `s3-read-only` → Bob
  - `ec2-s3-access-role` → EC2
- **Amazon S3 Bucket**: `secure-corp-storage` with:
  - Public access blocked
  - Lifecycle policy enabled

---

## 🔐 Access Model

| Entity | Permissions |
|---|---|
| **Alice** | List, Download, Upload |
| **Bob** | List, Download |
| **EC2** | List, Download, Upload *(No Delete)* |

All access is enforced via IAM policies — **no hardcoded credentials** used.

---

## ⚡ Quick Test

```bash
# Alice (Read/Write) — succeeds
aws s3 cp file.txt s3://secure-corp-storage/

# Bob (Read-only) — fails
aws s3 cp file.txt s3://secure-corp-storage/
# Output: Access Denied
```

---

## ✅ Testing Results

- **Alice:** List ✓ | Download ✓ | Upload ✓
- **Bob:** List ✓ | Download ✓ | Upload ✗ (Access Denied)
- **EC2:** List ✓ | Download ✓ | Upload ✓ | Delete ✗ (Access Denied)

---

## 🎯 Key Features

- Role-Based Access Control (RBAC) using IAM
- Enforced least privilege principle
- Secure EC2 access via IAM instance profile
- No hardcoded AWS credentials
- S3 lifecycle policy for cost optimization
- Architecture designed for real-world extensibility

---

## ���� Key Learnings

- Implemented IAM-based RBAC in AWS
- Applied least privilege for secure system design
- Understood role assumption and policy enforcement
- Built secure AWS workflows without access keys
- Designed a production-inspired cloud architecture

---

## 🛠️ Tech Stack

- Amazon EC2
- Amazon S3
- AWS Identity and Access Management
- Application Load Balancer
- Amazon VPC

**Region:** `us-east-1`

---

## ⚙️ Setup

Detailed setup instructions available in `SETUP.md`.

Includes:
- IAM role & policy creation
- EC2 configuration
- S3 bucket setup
- CLI-based testing steps

---

## 🔮 Future Improvements

- Move EC2 to private subnet + use VPC endpoints
- Add Infrastructure as Code (Terraform / CloudFormation)
- Integrate web application behind ALB
- Enable logging & monitoring (CloudWatch, CloudTrail)

---

## 📚 References

- AWS IAM Best Practices
- S3 Access Control Documentation

---

## 📄 License

MIT License