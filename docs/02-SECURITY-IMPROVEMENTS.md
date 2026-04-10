# 🛡️ Security Improvements Guide

Production hardening recommendations for the S3 IAM RBAC system.

---

## Table of Contents

1. [Security Principles Implemented](#1-security-principles-implemented)
2. [Current Security Posture](#2-current-security-posture)
3. [8 Key Improvements for Production](#3-8-key-improvements-for-production)
4. [Compliance Considerations](#4-compliance-considerations)
5. [Best Practices Summary](#5-best-practices-summary)

---

## 1. Security Principles Implemented

The following foundational security principles are already in place:

### Principle of Least Privilege ✅
Every identity (Alice, Bob, EC2) has the minimum permissions required to perform its function. No identity has `s3:DeleteObject`, `s3:DeleteBucket`, or any administrative S3 permissions.

### Separation of Duties ✅
- **Alice** (Developer): read + write (no delete)
- **Bob** (Viewer): read-only
- **EC2**: read + write (no delete)
- No single identity has complete control

### Defense in Depth ✅
Multiple layers of security are enforced:
1. IAM policies restrict what each identity can do
2. S3 Block Public Access prevents any public exposure
3. VPC isolates EC2 in a private subnet
4. ALB acts as the public-facing entry point

### No Long-Term Credentials on EC2 ✅
EC2 uses an IAM instance profile (temporary credentials via STS) — no hardcoded `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`.

### MFA Enforcement ✅
Trust policies for Alice and Bob require `aws:MultiFactorAuthPresent: "true"` before they can assume their respective roles.

---

## 2. Current Security Posture

### Strengths

| Control | Status | Details |
|---|---|---|
| Public Access Block | ✅ Enabled | All 4 settings enabled |
| S3 Encryption | ✅ SSE-S3 | AES-256 at rest |
| Versioning | ✅ Enabled | Protects against overwrites |
| IAM Roles over Keys | ✅ EC2 | Instance profile used |
| MFA Required | ✅ Alice + Bob | Trust policy condition |
| No Delete Permission | ✅ All roles | No `s3:DeleteObject` |
| VPC Isolation | ✅ EC2 | Private subnet |
| Lifecycle Management | ✅ Enabled | Cost + data retention |

### Gaps to Address

| Gap | Risk | Priority |
|---|---|---|
| No S3 bucket policy | Relies only on IAM | High |
| No CloudTrail alerts | Delayed incident detection | High |
| HTTP (not HTTPS) on ALB | Data in transit exposure | High |
| No VPC endpoint for S3 | Traffic via public internet | Medium |
| No AWS Config rules | Policy drift undetected | Medium |
| No GuardDuty | Threat detection gap | Medium |
| No resource tags | Compliance/audit gap | Low |
| No IAM Access Analyzer | External exposure unknown | Medium |

---

## 3. Eight Key Improvements for Production

### Improvement 1: Add S3 Bucket Policy (Critical)

An S3 bucket policy provides an additional layer of defense. Even if IAM policy is misconfigured, the bucket policy acts as a second gate.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonSSL",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::secure-corp-storage",
        "arn:aws:s3:::secure-corp-storage/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyDelete",
      "Effect": "Deny",
      "Principal": "*",
      "Action": [
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:DeleteBucket"
      ],
      "Resource": [
        "arn:aws:s3:::secure-corp-storage",
        "arn:aws:s3:::secure-corp-storage/*"
      ]
    },
    {
      "Sid": "AllowOnlyAuthorizedRoles",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::secure-corp-storage",
        "arn:aws:s3:::secure-corp-storage/*"
      ],
      "Condition": {
        "StringNotLike": {
          "aws:PrincipalArn": [
            "arn:aws:iam::ACCOUNT_ID:role/ec2-s3-access-role",
            "arn:aws:iam::ACCOUNT_ID:role/s3-read-write-get",
            "arn:aws:iam::ACCOUNT_ID:role/s3-read-only",
            "arn:aws:iam::ACCOUNT_ID:root"
          ]
        }
      }
    }
  ]
}
```

```bash
aws s3api put-bucket-policy \
  --bucket secure-corp-storage \
  --policy file://bucket-policy.json
```

---

### Improvement 2: Enable CloudTrail with Alerting (High Priority)

Every S3 API call should be logged and alerts sent for suspicious activity.

```bash
# Create CloudTrail
aws cloudtrail create-trail \
  --name secure-s3-audit-trail \
  --s3-bucket-name audit-logs-bucket \
  --is-multi-region-trail \
  --enable-log-file-validation

# Start logging
aws cloudtrail start-logging --name secure-s3-audit-trail

# Enable S3 data events
aws cloudtrail put-event-selectors \
  --trail-name secure-s3-audit-trail \
  --event-selectors '[{
    "ReadWriteType": "All",
    "IncludeManagementEvents": true,
    "DataResources": [{
      "Type": "AWS::S3::Object",
      "Values": ["arn:aws:s3:::secure-corp-storage/"]
    }]
  }]'
```

**CloudWatch Alarm for suspicious activity:**
```bash
# Alert on any DeleteObject attempts (even denied)
aws cloudwatch put-metric-alarm \
  --alarm-name S3DeleteAttempt \
  --alarm-description "Alert on any S3 delete attempt" \
  --metric-name DeleteRequests \
  --namespace AWS/S3 \
  --dimensions Name=BucketName,Value=secure-corp-storage \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT_ID:security-alerts
```

---

### Improvement 3: Enforce HTTPS on ALB (High Priority)

All traffic between clients and the ALB must be encrypted.

```bash
# Add HTTPS listener (requires ACM certificate)
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/XXXX \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

# Redirect HTTP to HTTPS
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions '[{
    "Type": "redirect",
    "RedirectConfig": {
      "Protocol": "HTTPS",
      "Port": "443",
      "StatusCode": "HTTP_301"
    }
  }]'
```

---

### Improvement 4: VPC Endpoint for S3 (Medium Priority)

S3 traffic should stay within the AWS network — not traverse the public internet.

```bash
# Create S3 VPC endpoint (Gateway type — free)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-SECURE-S3-VPC \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-PRIVATE-SUBNET \
  --vpc-endpoint-type Gateway

# Update S3 bucket policy to require VPC endpoint
# Add to bucket policy:
{
  "Sid": "DenyNonVPCEndpoint",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::secure-corp-storage",
    "arn:aws:s3:::secure-corp-storage/*"
  ],
  "Condition": {
    "StringNotEquals": {
      "aws:SourceVpce": "vpce-XXXXXXXX"
    }
  }
}
```

---

### Improvement 5: AWS Config Rules (Medium Priority)

Continuously monitor for policy drift and compliance violations.

```bash
# Enable AWS Config
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::ACCOUNT_ID:role/AWSConfigRole \
  --recording-group allSupported=true,includeGlobalResourceTypes=true

# Key rules to enable:
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "s3-bucket-public-read-prohibited",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}'

aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "s3-bucket-server-side-encryption-enabled",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }
}'

aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "s3-bucket-versioning-enabled",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "S3_BUCKET_VERSIONING_ENABLED"
  }
}'

aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "iam-no-inline-policy-check",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "IAM_NO_INLINE_POLICY_CHECK"
  }
}'
```

---

### Improvement 6: Enable Amazon GuardDuty (Medium Priority)

GuardDuty detects anomalous behavior like unusual API calls, cryptocurrency mining, and credential compromise.

```bash
# Enable GuardDuty
aws guardduty create-detector --enable --finding-publishing-frequency FIFTEEN_MINUTES

# Enable S3 protection
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty update-detector \
  --detector-id $DETECTOR_ID \
  --data-sources '{
    "S3Logs": {"Enable": true}
  }'
```

---

### Improvement 7: IAM Access Analyzer (Medium Priority)

Continuously check for any IAM policies that grant access to external principals.

```bash
# Create analyzer for the account
aws accessanalyzer create-analyzer \
  --analyzer-name secure-corp-analyzer \
  --type ACCOUNT

# Check for findings
aws accessanalyzer list-findings \
  --analyzer-name secure-corp-analyzer \
  --filter '{"status": {"eq": ["ACTIVE"]}}'
```

---

### Improvement 8: Enforce IAM Password Policy and Access Key Rotation (High Priority)

```bash
# Strong password policy
aws iam update-account-password-policy \
  --minimum-password-length 16 \
  --require-symbols \
  --require-numbers \
  --require-uppercase-characters \
  --require-lowercase-characters \
  --allow-users-to-change-password \
  --max-password-age 90 \
  --password-reuse-prevention 12 \
  --hard-expiry

# Find access keys older than 90 days
aws iam list-users --query 'Users[].UserName' --output text | \
  xargs -I{} aws iam list-access-keys --user-name {} \
  --query 'AccessKeyMetadata[?CreateDate<=`90 days ago`]'
```

---

## 4. Compliance Considerations

### CIS AWS Benchmark Alignment

| CIS Control | Requirement | Status |
|---|---|---|
| 1.4 | Ensure no root access keys | ✅ No root keys used |
| 1.5 | Ensure MFA is enabled for IAM users | ✅ MFA required in trust policies |
| 1.12 | Ensure no access keys for root | ✅ Roles only |
| 2.1.1 | S3 public access blocked | ✅ All 4 settings |
| 2.1.2 | S3 MFA delete | ⚠️ Not enabled — recommendation |
| 2.1.5 | S3 encryption | ✅ SSE-S3 |
| 3.1 | CloudTrail enabled | ⚠️ Improvement #2 |
| 3.7 | CloudTrail log validation | ⚠️ Part of improvement #2 |

### PCI-DSS Requirements

| Requirement | Control | Implementation |
|---|---|---|
| 7 (Restrict access) | Least privilege IAM | ✅ Implemented |
| 8 (Identify users) | Named IAM users | ✅ Alice-developer, Bob-viewer |
| 8.3 (MFA) | MFA in trust policies | ✅ Implemented |
| 10 (Track access) | CloudTrail | ⚠️ Improvement #2 |
| 10.5 (Log integrity) | CloudTrail validation | ⚠️ Improvement #2 |

### HIPAA Alignment (if applicable)

| HIPAA Safeguard | Implementation |
|---|---|
| Access Control (§164.312(a)) | IAM roles with least privilege |
| Audit Controls (§164.312(b)) | CloudTrail (improvement #2) |
| Transmission Security (§164.312(e)) | HTTPS on ALB (improvement #3) |
| Encryption at Rest | SSE-S3 enabled |

---

## 5. Best Practices Summary

### IAM Best Practices

```
✅ Use roles instead of users for applications (EC2 instance profile)
✅ Use MFA for all human users
✅ Follow least-privilege principle
✅ Use groups to assign permissions (future improvement)
✅ Rotate access keys regularly
✅ Never share credentials
✅ Use IAM Access Analyzer to detect over-permissive policies
```

### S3 Best Practices

```
✅ Block all public access
✅ Enable versioning
✅ Enable server-side encryption
✅ Enable lifecycle policies for cost management
✅ Enable access logging (future improvement)
✅ Use bucket policies as second layer of defense
✅ Enforce TLS with bucket policy
✅ Enable MFA delete for critical buckets
```

### Network Best Practices

```
✅ Use VPC to isolate resources
✅ Place EC2 in private subnet
✅ Use ALB as public entry point
⚠️ Use VPC endpoints for S3 (improvement #4)
⚠️ Enforce HTTPS on ALB (improvement #3)
✅ Use security groups for fine-grained network control
```

### Monitoring Best Practices

```
⚠️ Enable CloudTrail for all regions (improvement #2)
⚠️ Enable GuardDuty (improvement #6)
⚠️ Set up CloudWatch alarms for suspicious activity (improvement #2)
⚠️ Enable AWS Config for compliance monitoring (improvement #5)
⚠️ Use IAM Access Analyzer (improvement #7)
✅ Review IAM policies regularly
```

---

*Next: See [03-TESTING-VALIDATION.md](03-TESTING-VALIDATION.md) for complete test results.*
