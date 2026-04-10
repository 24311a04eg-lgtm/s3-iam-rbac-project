# 📂 PDF Reference & Visual Learning Path

This document maps every screenshot and image in the repository to its corresponding documentation section and explains what each image demonstrates. Use this as your visual learning guide when reading the setup documentation.

---

## 🗺️ Image-to-Section Map

| Image File | What It Shows | Where Used | Section |
|---|---|---|---|
| `architecture.png` | Full AWS architecture diagram (VPC, ALB, EC2, IAM, S3) | README + 01-SETUP | [Architecture](#architecture-diagram) |
| `s3bucketname.png` | S3 bucket list — secure-corp-storage created | README + 01-SETUP §5.2 | [S3 Bucket](#s3-bucket-creation) |
| `Screenshot ...224601.png` | S3 bucket contents (4 report files with sizes) | README + 01-SETUP §5.6 | [S3 Contents](#s3-bucket-contents) |
| `Screenshot ...224612.png` | S3 lifecycle policy transitions (Day 0→30→60→90→120) | 01-SETUP §5.5 | [Lifecycle Policy](#s3-lifecycle-policy) |
| `Screenshot ...224620.png` | IAM Users — Alice-developer, Bob-viewer | README + 01-SETUP §6.1 | [IAM Users](#iam-users) |
| `Screenshot ...224627.png` | IAM Roles list (all 5 roles) | README + 01-SETUP §6.2 | [IAM Roles](#iam-roles) |
| `Screenshot ...224635.png` | Read-Write policy JSON (ListBucket + GetObject + PutObject) | 01-SETUP §6.3 | [EC2/Alice Policy](#ecalice-read-write-policy) |
| `Screenshot ...224646.png` | Read-Only policy JSON (ListBucket + GetObject only) | 01-SETUP §6.4 | [Bob Policy](#bob-read-only-policy) |
| `Screenshot ...224706.png` | EC2 trust policy (ec2.amazonaws.com as principal) | 01-SETUP §6.5 | [EC2 Trust Policy](#ec2-trust-policy) |
| `Screenshot ...224749.png` | Alice's user policy (sts:AssumeRole on s3-read-write-get) | 01-SETUP §6.6 | [Alice Assume Role](#alice-assume-role-policy) |
| `Screenshot ...224759.png` | ALB details (active, Internet-facing, multi-AZ) | 01-SETUP §8.1 | [ALB Setup](#alb-details) |
| `Screenshot ...224808.png` | EC2 CLI: `s3 ls` lists 4 files ✅ | README + 01-SETUP §9.1 | [EC2 List Test](#ec2-list-test) |
| `Screenshot ...224817.png` | EC2 CLI: `s3 cp` download succeeds ✅ | README + 01-SETUP §9.2 | [EC2 Download Test](#ec2-download-test) |
| `Screenshot ...224826.png` | EC2 CLI: `s3 cp` upload succeeds ✅ | README + 01-SETUP §9.3 | [EC2 Upload Test](#ec2-upload-test) |
| `Screenshot ...224834.png` | EC2 CLI: `s3 rm` → AccessDenied ❌ | README + 01-SETUP §9.4 | [EC2 Delete Denied](#ec2-delete-denied) |
| `Screenshot ...224855.png` | S3 file: clients-reports.txt (sample file in bucket) | 01-SETUP §1 | [Use Case](#use-case) |
| `Screenshot ...224920.png` | Bob: report3.txt Access denied in S3 console ❌ | 01-SETUP §9.9 | [Bob Access Denied](#bob-access-denied) |
| `downloading.png` | Local Downloads folder showing Data-report.csv | 01-SETUP §1 | [Use Case](#use-case) |

---

## 📚 Visual Learning Path

Follow this sequence to understand the project from start to finish using the images as signposts.

---

### Step 1: Understand the Problem (Use Case)

Before looking at any technical setup, understand **why** this project exists.

> *"We need to store sensitive client reports in S3, but different people need different access levels — and nobody should ever be able to delete production data."*

![Client Report File](<../images/Screenshot 2026-04-08 224855.png>)
*This is the kind of file we're protecting — clients-reports.txt stored in S3*

![Downloaded File](../images/downloading.png)
*A user successfully downloaded Data-report.csv — proof the access control is working from the user's perspective*

**📖 Read more:** [01-PROJECT-SETUP.md §1](01-PROJECT-SETUP.md#1-real-world-scenario)

---

### Step 2: See the Architecture

Before writing a single line of config, understand the full picture.

![Architecture Diagram](../images/architecture.png)

What this diagram tells us:
- **Alice** (Admin) → connects over HTTPS → IAM → assumes `S3READWRITEROLE` → can list, get, put objects
- **Bob** (Developer/Viewer) → connects over HTTPS → IAM → assumes `S3READONLYROLE` → can only list and get
- **Internet traffic** → enters via **ALB** → routed to **EC2** inside `SECURE-S3-VPC`
- **EC2** → uses `EC2S3ACCESSROLE` via instance profile → can list, get, put objects
- **S3 bucket** (`secure-corp-storage`) → no direct public access, only reachable via authorized roles

> 💡 The dotted and solid arrows show authorized paths. There is **no arrow for delete** — because delete is not permitted anywhere.

**📖 Read more:** [01-PROJECT-SETUP.md §2](01-PROJECT-SETUP.md#2-architecture-overview)

---

### Step 3: Create the S3 Bucket

First infrastructure component — the S3 bucket that stores all the files.

![S3 Bucket Created](../images/s3bucketname.png)
*S3 console showing `secure-corp-storage` created in US East (N. Virginia), January 31 2026. Public access is blocked.*

After uploading test files:

![S3 Bucket Contents](<../images/Screenshot 2026-04-08 224601.png>)
*Bucket contents: Data-report.csv (184B), report1.txt (97B), report2.txt (106B), report3.txt (134B) — all Standard storage*

Configure the lifecycle policy to save costs as files age:

![S3 Lifecycle Policy](<../images/Screenshot 2026-04-08 224612.png>)
*Lifecycle transitions: Day 0 = Standard, Day 30 = Standard-IA, Day 60 = Intelligent-Tiering, Day 90 = One Zone-IA, Day 120 = Glacier*

**📖 Read more:** [01-PROJECT-SETUP.md §5](01-PROJECT-SETUP.md#5-s3-bucket-configuration)

---

### Step 4: Create IAM Users and Roles

Now set up the identity layer — who can access what.

#### IAM Users

![IAM Users](<../images/Screenshot 2026-04-08 224620.png>)
*Two users created: Alice-developer (read-write) and Bob-viewer (read-only)*

#### IAM Roles

![IAM Roles](<../images/Screenshot 2026-04-08 224627.png>)
*All 5 IAM roles: ec2-s3-access-role, rds-proxy-role, s3-read-only, s3-read-write-get, ssm-role*

**📖 Read more:** [01-PROJECT-SETUP.md §6.1–6.2](01-PROJECT-SETUP.md#6-iam-design--implementation)

---

### Step 5: Configure Permission Policies

Each role needs a permission policy defining exactly what S3 actions it can perform.

#### EC2 / Alice — Read-Write Policy (ListBucket + GetObject + PutObject)

![EC2/Alice Policy JSON](<../images/Screenshot 2026-04-08 224635.png>)
*JSON policy for read-write access — allows s3:ListBucket, s3:GetObject, s3:PutObject on secure-corp-storage. No s3:DeleteObject.*

#### Bob — Read-Only Policy (ListBucket + GetObject)

![Bob's Read-Only Policy JSON](<../images/Screenshot 2026-04-08 224646.png>)
*JSON policy for read-only access — allows s3:ListBucket, s3:GetObject only. No put, no delete.*

**📖 Read more:** [01-PROJECT-SETUP.md §6.3–6.4](01-PROJECT-SETUP.md#63-permission-policy--ec2-and-alice-read-write)

---

### Step 6: Configure Trust Policies

Trust policies define **who** can assume each role.

#### EC2 Trust Policy (ec2.amazonaws.com)

![EC2 Trust Policy](<../images/Screenshot 2026-04-08 224706.png>)
*EC2 trust policy — the EC2 service itself (ec2.amazonaws.com) is the trusted principal*

#### Alice's Assume-Role Policy

![Alice Assume Role Policy](<../images/Screenshot 2026-04-08 224749.png>)
*Alice-developer's inline policy allowing sts:AssumeRole on the s3-read-write-get role ARN*

> 🔐 **MFA requirement:** The trust policies for `s3-read-write-get` (Alice) and `s3-read-only` (Bob) include a condition: `aws:MultiFactorAuthPresent: "true"`. This means both users must have an active MFA session to assume their roles.

**📖 Read more:** [01-PROJECT-SETUP.md §6.5–6.6](01-PROJECT-SETUP.md#65-trust-policy--ec2-role)

---

### Step 7: Launch EC2 and Set Up ALB

The EC2 instance gets the `ec2-s3-access-profile` instance profile, giving it temporary credentials automatically.

![ALB Details](<../images/Screenshot 2026-04-08 224759.png>)
*ALB details: Application type, Active status, VPC vpc-0b81859c003a21abf, Internet-facing, Availability Zones: us-east-1a and us-east-1d*

**📖 Read more:** [01-PROJECT-SETUP.md §7–8](01-PROJECT-SETUP.md#7-ec2-instance-setup)

---

### Step 8: Test and Validate Everything

Now prove the permission matrix works correctly — both the allowed operations and the denials.

#### EC2 List Files ✅

![EC2 List](<../images/Screenshot 2026-04-08 224808.png>)
*`aws s3 ls s3://secure-corp-storage/` — returns 4 files: Uploads/Data-report.csv, report1.txt, report2.txt, report3.txt. List works. ✅*

#### EC2 Download ✅

![EC2 Download](<../images/Screenshot 2026-04-08 224817.png>)
*`aws s3 cp s3://secure-corp-storage/report1.txt .` — download succeeds. `cat report1.txt` shows the content. ✅*

#### EC2 Upload ✅

![EC2 Upload](<../images/Screenshot 2026-04-08 224826.png>)
*Creates `report5.txt` with nano, then `aws s3 cp /home/ec2-user/report5.txt s3://secure-corp-storage/` — upload succeeds. ✅*

#### EC2 Delete ❌ (Expected Denial)

![EC2 Delete Denied](<../images/Screenshot 2026-04-08 224834.png>)
*`aws s3 rm s3://secure-corp-storage/Data-report.csv` — AccessDenied. The assumed-role `ec2-s3-access-role` is not authorized because the policy has no `s3:DeleteObject`. ❌*

#### Bob — Access Denied in Console ❌

![Bob Access Denied](<../images/Screenshot 2026-04-08 224920.png>)
*Bob attempting to access report3.txt in the S3 console — Status: Failed, Error: Access denied. Bob's s3-read-only role does not allow download via the S3 console's presigned URL flow. ❌*

**📖 Read more:** [01-PROJECT-SETUP.md §9](01-PROJECT-SETUP.md#9-testing--validation) | [03-TESTING-VALIDATION.md](03-TESTING-VALIDATION.md)

---

## 🎯 Key Concepts Illustrated by Images

### Concept 1: Least Privilege
Every image of an IAM policy shows **only the minimum required actions**. The read-write policy has 3 actions, the read-only has 2. No policy has `s3:DeleteObject`.

### Concept 2: IAM Roles vs Users
- Users (`Alice-developer`, `Bob-viewer`) are human identities with long-term credentials
- Roles (`s3-read-write-get`, `ec2-s3-access-role`) provide **temporary credentials** via `sts:AssumeRole`
- EC2 uses a role directly via instance profile — **no human involvement needed**

### Concept 3: Deny by Default
AWS IAM is **deny by default**. The delete-denied screenshots (EC2 delete, Bob access denied) aren't special "deny rules" — they happen because no policy grants those permissions.

### Concept 4: MFA Enforcement
The trust policies for Alice and Bob have `aws:MultiFactorAuthPresent: "true"`. If MFA isn't configured, the assume-role call will be rejected by IAM — not by any custom code.

### Concept 5: Separation of Concerns
- Alice's **lifecycle policy** image shows cost optimization (automatic storage tier transitions)
- Alice's **ALB image** shows the network entry point — separate from S3 permissions
- These concerns are deliberately separated: network → EC2 → IAM → S3

---

## 🔗 Cross-Reference Table

| PDF Concept | Implementation File | Screenshot Evidence |
|---|---|---|
| S3 bucket creation | `scripts/setup-s3.sh` | `s3bucketname.png` |
| S3 bucket contents | S3 console | `Screenshot ...224601.png` |
| Lifecycle policy | `scripts/setup-s3.sh` | `Screenshot ...224612.png` |
| IAM users | `scripts/setup-iam.sh` | `Screenshot ...224620.png` |
| IAM roles list | `scripts/setup-iam.sh` | `Screenshot ...224627.png` |
| Read-write policy JSON | `iam-policies/s3-read-write-policy.json` | `Screenshot ...224635.png` |
| Read-only policy JSON | `iam-policies/s3-read-only-policy.json` | `Screenshot ...224646.png` |
| EC2 trust policy | `iam-policies/trust-policy-ec2.json` | `Screenshot ...224706.png` |
| Alice assume-role policy | `iam-policies/trust-policy-alice.json` | `Screenshot ...224749.png` |
| ALB configuration | `scripts/setup-ec2.sh` | `Screenshot ...224759.png` |
| Full architecture | All scripts combined | `architecture.png` |
| EC2 list test | `scripts/test-permissions.sh` | `Screenshot ...224808.png` |
| EC2 download test | `scripts/test-permissions.sh` | `Screenshot ...224817.png` |
| EC2 upload test | `scripts/test-permissions.sh` | `Screenshot ...224826.png` |
| EC2 delete denied | `scripts/test-permissions.sh` | `Screenshot ...224834.png` |
| Bob access denied | `scripts/test-permissions.sh` | `Screenshot ...224920.png` |

---

*This reference guide pairs every visual element in the project with its corresponding code, CLI command, and documentation section.*
