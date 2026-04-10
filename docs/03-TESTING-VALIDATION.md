# ✅ Testing & Validation Guide

Complete evidence of permission enforcement for all three identities: EC2, Alice, and Bob.

---

## Table of Contents

1. [Test Environment](#1-test-environment)
2. [EC2 CLI Testing](#2-ec2-cli-testing)
3. [Alice Testing (Read-Write)](#3-alice-testing-read-write)
4. [Bob Testing (Read-Only)](#4-bob-testing-read-only)
5. [Permission Summary Matrix](#5-permission-summary-matrix)
6. [Automated Test Script](#6-automated-test-script)

---

## 1. Test Environment

| Component | Value |
|---|---|
| Region | `us-east-1` |
| S3 Bucket | `secure-corp-storage` |
| EC2 Role | `ec2-s3-access-role` |
| Alice's Role | `s3-read-write-get` |
| Bob's Role | `s3-read-only` |
| Test Files | `report1.txt`, `report2.txt`, `report3.txt`, `report5.txt`, `Data-report.csv` |

### Test Files in Bucket

![S3 Files Listing](../images/18-s3-bucket-contents-files.jpg)
*All files present in secure-corp-storage: Data-report.csv, report1.txt, report2.txt, report3.txt, report5.txt*

---

## 2. EC2 CLI Testing

The EC2 instance uses an IAM instance profile (`ec2-s3-access-role`) which provides temporary credentials automatically. No access keys are stored on the instance.

### 2.1 Verify EC2 Identity

```bash
# On EC2 — confirm which role is being used
aws sts get-caller-identity
```

Expected output:
```json
{
  "UserId": "AROAXXXXXXXXXXXXXXXXX:i-0XXXXXXXXXXXXXXXXX",
  "Account": "123456789012",
  "Arn": "arn:aws:sts::123456789012:assumed-role/ec2-s3-access-role/i-0XXXXXXXXXXXXXXXXX"
}
```

### 2.2 EC2 Download ✅ PASS

![EC2 Download](../images/05-ec2-download.jpg)
*EC2 successfully downloads report1.txt from S3*

```bash
# Download report1.txt
aws s3 cp s3://secure-corp-storage/report1.txt ./report1.txt
```

**Result:**
```
download: s3://secure-corp-storage/report1.txt to ./report1.txt
```

✅ **PASS** — EC2 can download files (s3:GetObject allowed)

### 2.3 EC2 Upload ✅ PASS

![EC2 Upload](../images/06-ec2-upload.jpg)
*EC2 successfully uploads report5.txt to S3*

```bash
# Create and upload a new report
echo "EC2 generated report - $(date)" > report5.txt
aws s3 cp report5.txt s3://secure-corp-storage/report5.txt
```

**Result:**
```
upload: ./report5.txt to s3://secure-corp-storage/report5.txt
```

✅ **PASS** — EC2 can upload files (s3:PutObject allowed)

### 2.4 EC2 Delete ❌ DENIED

![EC2 Delete Denied](../images/07-ec2-delete-denied.jpg)
*EC2 receives AccessDenied when attempting to delete Data-report.csv*

```bash
# Attempt to delete Data-report.csv
aws s3 rm s3://secure-corp-storage/Data-report.csv
```

**Result:**
```
An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied
```

❌ **DENIED** — EC2 cannot delete files (s3:DeleteObject not in policy) ✅ Policy working correctly

### 2.5 EC2 File Listing ✅ PASS

![EC2 Uploads List](../images/12-ec2-uploads-list.jpg)
*EC2 lists all files in secure-corp-storage with sizes and timestamps*

```bash
# List all files
aws s3 ls s3://secure-corp-storage/
```

**Result:**
```
2026-01-31 08:15:23         234 Data-report.csv
2026-01-31 08:16:45         106 report1.txt
2026-01-31 08:17:02          97 report2.txt
2026-01-31 08:17:58         134 report3.txt
2026-01-31 08:18:30         156 report5.txt
```

✅ **PASS** — EC2 can list bucket contents (s3:ListBucket allowed)

---

## 3. Alice Testing (Read-Write)

Alice is an IAM user (`Alice-developer`) who assumes the `s3-read-write-get` role to access S3. She has read and write access but **cannot delete** files.

### 3.1 Alice's IAM Configuration

![IAM Users](../images/13-iam-users.jpg)
*IAM console showing Alice-developer and Bob-viewer users*

![Alice's Policy](../images/15-s3-read-write-policy.jpg)
*Alice's permission policy: ListBucket + GetObject + PutObject on secure-corp-storage*

### 3.2 Alice Assumes Her Role

```bash
# Alice authenticates and assumes her role (MFA required)
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/s3-read-write-get \
  --role-session-name alice-session \
  --serial-number arn:aws:iam::123456789012:mfa/Alice-developer \
  --token-code 123456

# Export temporary credentials
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

### 3.3 Alice Download ✅ PASS

```bash
aws s3 cp s3://secure-corp-storage/report1.txt ./alice-report1.txt
```

**Result:**
```
download: s3://secure-corp-storage/report1.txt to ./alice-report1.txt
```

✅ **PASS** — Alice can download files

### 3.4 Alice Upload ✅ PASS

```bash
# Alice uploads Data-report.csv
aws s3 cp ~/Downloads/Data-report.csv s3://secure-corp-storage/Data-report.csv
```

**Result:**
```
upload: ./Data-report.csv to s3://secure-corp-storage/Data-report.csv
```

✅ **PASS** — Alice can upload files

*Alice's local Downloads folder with Data-report.csv ready to upload:*

![Downloads Folder](../images/02-downloads-folder.jpg)
*Alice's Downloads folder showing Data-report.csv file*

### 3.5 Alice List ✅ PASS

```bash
aws s3 ls s3://secure-corp-storage/
```

**Result:**
```
2026-01-31 08:15:23         234 Data-report.csv
2026-01-31 08:16:45         106 report1.txt
...
```

✅ **PASS** — Alice can list bucket contents

### 3.6 Alice Delete ❌ DENIED

```bash
aws s3 rm s3://secure-corp-storage/report2.txt
```

**Result:**
```
An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied
```

❌ **DENIED** — Alice cannot delete files (no s3:DeleteObject) ✅ Policy working correctly

---

## 4. Bob Testing (Read-Only)

Bob is an IAM user (`Bob-viewer`) who assumes the `s3-read-only` role. He can only list and download files.

### 4.1 Bob's IAM Configuration

![IAM Roles](../images/14-iam-roles.jpg)
*IAM Roles showing s3-read-only role assigned to Bob*

![Bob's Policy](../images/16-s3-read-only-policy.jpg)
*Bob's permission policy: ListBucket + GetObject only on secure-corp-storage*

### 4.2 Bob Assumes His Role

```bash
# Bob authenticates and assumes his read-only role (MFA required)
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/s3-read-only \
  --role-session-name bob-session \
  --serial-number arn:aws:iam::123456789012:mfa/Bob-viewer \
  --token-code 654321

# Export temporary credentials
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

### 4.3 Bob Download ✅ PASS

```bash
aws s3 cp s3://secure-corp-storage/report3.txt ./bob-report3.txt
```

**Result:**
```
download: s3://secure-corp-storage/report3.txt to ./bob-report3.txt
```

✅ **PASS** — Bob can download files

*The clients-reports.txt file that Bob can view:*

![Clients Reports](../images/01-clients-reports.txt.jpg)
*clients-reports.txt content — January 31, 2026 data*

### 4.4 Bob List ✅ PASS

```bash
aws s3 ls s3://secure-corp-storage/
```

**Result:**
```
2026-01-31 08:15:23         234 Data-report.csv
2026-01-31 08:16:45         106 report1.txt
2026-01-31 08:17:02          97 report2.txt
2026-01-31 08:17:58         134 report3.txt
2026-01-31 08:18:30         156 report5.txt
```

✅ **PASS** — Bob can list bucket contents

### 4.5 Bob Upload ❌ DENIED

```bash
aws s3 cp newfile.txt s3://secure-corp-storage/
```

**Result:**
```
An error occurred (AccessDenied) when calling the PutObject operation: Access Denied
```

❌ **DENIED** — Bob cannot upload files ✅ Policy working correctly

### 4.6 Bob Delete ❌ DENIED

```bash
aws s3 rm s3://secure-corp-storage/report3.txt
```

**Result:**
```
An error occurred (AccessDenied) when calling the DeleteObject operation: Access Denied
```

❌ **DENIED** — Bob cannot delete files ✅ Policy working correctly

*S3 console confirming access denied for unauthorized operations:*

![S3 Access Denied](../images/04-s3-bucket-contents.jpg)
*S3 console showing Access Denied on report3.txt — Bob's read-only policy enforced*

---

## 5. Permission Summary Matrix

### Complete Test Results

| Test Case | EC2 | Alice | Bob | Expected | Result |
|---|:---:|:---:|:---:|---|---|
| List bucket contents | ✅ | ✅ | ✅ | ALLOW all | ✅ PASS |
| Download (GET) object | ✅ | ✅ | ✅ | ALLOW all | ✅ PASS |
| Upload (PUT) object | ✅ | ✅ | ❌ | ALLOW EC2+Alice, DENY Bob | ✅ PASS |
| Delete object | ❌ | ❌ | ❌ | DENY all | ✅ PASS |
| List other buckets | ❌ | ❌ | ❌ | DENY all | ✅ PASS |
| Access different bucket | ❌ | ❌ | ❌ | DENY all | ✅ PASS |

**Overall: 6/6 test scenarios PASS ✅**

### Policy Action Matrix

| IAM Action | EC2 Role | Alice Role | Bob Role |
|---|:---:|:---:|:---:|
| `s3:ListBucket` | ✅ | ✅ | ✅ |
| `s3:GetObject` | ✅ | ✅ | ✅ |
| `s3:PutObject` | ✅ | ✅ | ❌ |
| `s3:DeleteObject` | ❌ | ❌ | ❌ |
| `s3:DeleteBucket` | ❌ | ❌ | ❌ |
| `s3:GetBucketAcl` | ❌ | ❌ | ❌ |
| `s3:PutBucketAcl` | ❌ | ❌ | ❌ |

---

## 6. Automated Test Script

Run all tests automatically using the provided script:

```bash
# Make executable and run
chmod +x scripts/test-permissions.sh
./scripts/test-permissions.sh
```

The script will:
1. Test EC2 role permissions (list, get, put, delete)
2. Test Alice role permissions (list, get, put, delete)
3. Test Bob role permissions (list, get, put, delete)
4. Report PASS/FAIL for each scenario
5. Exit with code 0 if all pass, non-zero if any fail

### Sample Output

```
==========================================================
 S3 IAM RBAC Permission Validation
==========================================================

[EC2 ROLE TESTS]
✅ PASS: EC2 can list bucket
✅ PASS: EC2 can download file
✅ PASS: EC2 can upload file
✅ PASS: EC2 correctly denied delete

[ALICE ROLE TESTS]
✅ PASS: Alice can list bucket
✅ PASS: Alice can download file
✅ PASS: Alice can upload file
✅ PASS: Alice correctly denied delete

[BOB ROLE TESTS]
✅ PASS: Bob can list bucket
✅ PASS: Bob can download file
✅ PASS: Bob correctly denied upload
✅ PASS: Bob correctly denied delete

==========================================================
 RESULTS: 12/12 tests passed ✅
==========================================================
```

---

*Back to: [01-PROJECT-SETUP.md](01-PROJECT-SETUP.md) | [02-SECURITY-IMPROVEMENTS.md](02-SECURITY-IMPROVEMENTS.md)*
