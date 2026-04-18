# 🔐 S3 Vault: IAM Driven Access Management

Secure role-based access to AWS S3 using IAM. Alice reads/writes, Bob reads only, EC2 does it all—no hardcoded credentials.

---

## Overview

Organizations store critical files in S3 but without proper access control, anyone can delete or modify them. This project demonstrates least-privilege RBAC: three IAM roles with different permission levels, enforced at the policy level.

**The problem:** Accidental file deletion.  
**The solution:** Role-based access control.

---

## Architecture

![Architecture Diagram](images/01-architecture.png)

- **VPC:** Isolated network (`10.0.0.0/16`) with public subnet
- **ALB:** Routes traffic to EC2
- **EC2:** Hosts AWS CLI, no hardcoded credentials (uses IAM instance profile)
- **IAM Roles:** `s3-read-write-get` (Alice), `s3-read-only` (Bob), `ec2-s3-access-role` (EC2)
- **S3 Bucket:** `secure-corp-storage` with lifecycle policy + public access blocked

---

## What You Get

- ✓ Role-based access control in action
- ✓ Least-privilege principle enforced
- ✓ Real testing showing Alice can upload, Bob gets "Access Denied"
- ✓ S3 lifecycle cost optimization
- ✓ No hardcoded AWS credentials

---

## Quick Test

```bash
# Alice (read/write/upload) - succeeds
aws s3 cp file.txt s3://secure-corp-storage/

# Bob (read-only) - fails with Access Denied
aws s3 cp file.txt s3://secure-corp-storage/
# Error: Access Denied
```

---

## Testing Results

- **Alice:** List ✓ | Download ✓ | Upload ✓
- **Bob:** List ✓ | Download ✓ | Upload ✗ (Access Denied)
- **EC2:** List ✓ | Download ✓ | Upload ✓ | Delete ✗ (Access Denied)

---

## Key Learnings

- → Implemented role-based access control (RBAC)
- → Learned principle of least privilege
- → Hands-on with IAM, EC2, ALB, S3
- → Secure AWS operations without hardcoded credentials
- → Professional AWS architecture design

---

## Tech Stack

- **AWS:** EC2 | IAM | ALB | S3 | VPC
- **Region:** `us-east-1`

---

## Setup

See `SETUP.md` for step-by-step commands.

---

## References

- AWS IAM Best Practices
- S3 Access Control

---

## License

MIT  
Based on: AWS security best practices
