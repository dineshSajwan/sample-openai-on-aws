# Network Access Patterns for LiteLLM Gateway

This guide explains how to configure network access to the LiteLLM gateway for different deployment scenarios.

## ⚠️ Security Warning

**AWS automated security scans will delete publicly accessible ALB listeners** (0.0.0.0/0) that lack proper authentication and protection. If you deploy with public access, the listener will be auto-remediated and your gateway will become unreachable.

## Recommended Patterns by Use Case

### 1. Enterprise Deployment (Recommended)

**Use Case:** Developers access gateway from corporate network or VPN

**Configuration:**
```bash
# During cxwb init, set AllowedCidr to your corporate network CIDR
AllowedCidr: 10.0.0.0/8          # Example: Corporate RFC1918 network
AllowedCidr: 172.16.0.0/12       # Example: Corporate network
AllowedCidr: 203.0.113.0/24      # Example: Corporate public IP range
```

**Advantages:**
- ✅ Passes AWS security scans
- ✅ No additional infrastructure cost
- ✅ Simple configuration
- ✅ Works with VPN and Direct Connect

**How to Get Your Corporate CIDR:**
Ask your network team for:
- VPN IP range
- Corporate office IP ranges
- AWS VPC CIDR (if using VPC peering/transit gateway)

---

### 2. Single Developer / Testing

**Use Case:** Individual developer testing the gateway

**Configuration:**
```bash
# Get your current IP
curl https://checkip.amazonaws.com

# Set AllowedCidr to your IP
AllowedCidr: 24.226.123.4/32    # Your specific IP only
```

**Advantages:**
- ✅ Fastest to set up
- ✅ Passes AWS security scans
- ✅ Maximum security (only your IP)

**Limitations:**
- ❌ IP may change (home internet, coffee shop)
- ❌ Need to update security group when IP changes

**Update Security Group When IP Changes:**
```bash
# Get current security group ID
SG_ID=$(aws cloudformation describe-stack-resources \
  --stack-name codex-litellm-gateway \
  --region us-west-2 \
  --query 'StackResources[?LogicalResourceId==`ALBSecurityGroup`].PhysicalResourceId' \
  --output text)

# Remove old rule
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr OLD_IP/32

# Add new rule
NEW_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr $NEW_IP/32
```

---

### 3. Public Access with WAF (Advanced)

**Use Case:** Gateway needs to be accessible from internet with protection

**Configuration:**
1. Deploy with `AllowedCidr: 0.0.0.0/0`
2. **Immediately** attach AWS WAF WebACL with:
   - Rate limiting (e.g., 2000 req/5min per IP)
   - AWS Managed Rules: IP reputation list
   - Geographic restrictions (if applicable)
   - Bot detection

**CloudFormation Addition Required:**
```yaml
Resources:
  WAFWebACL:
    Type: AWS::WAFv2::WebACL
    Properties:
      Scope: REGIONAL
      DefaultAction:
        Allow: {}
      Rules:
        - Name: RateLimitRule
          Priority: 1
          Statement:
            RateBasedStatement:
              Limit: 2000
              AggregateKeyType: IP
          Action:
            Block: {}
          VisibilityConfig:
            SampledRequestsEnabled: true
            CloudWatchMetricsEnabled: true
            MetricName: RateLimitRule
        - Name: AWSManagedRulesIPReputationList
          Priority: 2
          Statement:
            ManagedRuleGroupStatement:
              VendorName: AWS
              Name: AWSManagedRulesAmazonIpReputationList
          OverrideAction:
            None: {}
          VisibilityConfig:
            SampledRequestsEnabled: true
            CloudWatchMetricsEnabled: true
            MetricName: IPReputationList

  WAFAssociation:
    Type: AWS::WAFv2::WebACLAssociation
    Properties:
      ResourceArn: !Ref ApplicationLoadBalancer
      WebACLArn: !GetAtt WAFWebACL.Arn
```

**Advantages:**
- ✅ Public internet access
- ✅ Protection against attacks
- ✅ Rate limiting per IP
- ✅ Passes security compliance

**Limitations:**
- ❌ Additional cost (~$5/month + $1 per million requests)
- ❌ More complex setup
- ❌ May still trigger security alerts without proper tagging

---

### 4. VPC PrivateLink (Multi-Account)

**Use Case:** Central account hosts gateway, developers in other accounts access privately

**Architecture:**
```
Developer Account (VPC)
  └── VPC Endpoint (Interface)
      └── PrivateLink Connection
          └── Gateway Account (VPC)
              └── ALB (Internal)
```

**Configuration:**
- ALB must be `Scheme: internal` (not internet-facing)
- Create VPC Endpoint Service in gateway account
- Create VPC Endpoint in each developer account
- No public internet exposure

**CloudFormation Changes:**
```yaml
Parameters:
  ALBScheme:
    Type: String
    Default: internal
    AllowedValues: [internal, internet-facing]

Resources:
  ApplicationLoadBalancer:
    Properties:
      Scheme: !Ref ALBScheme  # Change to 'internal'

  VPCEndpointService:
    Type: AWS::EC2::VPCEndpointService
    Properties:
      NetworkLoadBalancerArns:
        - !Ref NetworkLoadBalancer
      AcceptanceRequired: true
```

**Advantages:**
- ✅ No public internet exposure
- ✅ No AWS security scan issues
- ✅ Works across accounts/regions
- ✅ Low latency (AWS backbone)

**Limitations:**
- ❌ Requires NLB in front of ALB (~$16/month)
- ❌ More complex setup
- ❌ Developers need VPN or Direct Connect to their VPC

---

## Decision Matrix

| Scenario | Recommended Pattern | AllowedCidr |
|----------|---------------------|-------------|
| Enterprise with VPN | Corporate CIDR | `10.0.0.0/8` or corp range |
| Single developer testing | Your IP only | `YOUR_IP/32` |
| Public API (protected) | WAF + public access | `0.0.0.0/0` + WAF |
| Multi-account private | VPC PrivateLink | `10.0.0.0/16` (VPC CIDR) |

## Getting Corporate Network CIDR

**Ask your network/security team:**
1. "What is our corporate VPN IP range?"
2. "What CIDR should we whitelist for internal services?"
3. "Do we use AWS Direct Connect or Transit Gateway?"

**Common formats:**
- RFC1918 private: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- Corporate public: `203.0.113.0/24` (example)
- VPN range: `172.31.0.0/16` (example)

## Troubleshooting

### Listener Deleted by AWS Security Scan

**Symptom:** `curl: (7) Failed to connect` after deployment

**Cause:** ALB is publicly accessible (`0.0.0.0/0`) without WAF

**Fix:**
1. Update `AllowedCidr` to corporate CIDR or your IP
2. Destroy and redeploy stack:
   ```bash
   cd guidance-for-codex-on-amazon-bedrock/source
   poetry run cxwb destroy --profile <profile> --yes
   poetry run cxwb deploy --profile <profile>
   ```

### IP Changed, Can't Access Gateway

**Symptom:** Gateway was working, now `Connection refused`

**Fix:** Update security group with new IP (see "Single Developer" section above)

### Corporate Network Access Not Working

**Check:**
1. Verify you're connected to VPN
2. Verify VPN assigns IPs in the CIDR range you configured
3. Check VPN routes include the AWS region
4. Test with: `curl http://<gateway-url>/health`

## Security Best Practices

1. ✅ **Never use 0.0.0.0/0 without WAF** - AWS will auto-delete the listener
2. ✅ **Use API keys** - Even with network restrictions, require authentication
3. ✅ **Monitor CloudWatch Logs** - Track who accesses the gateway
4. ✅ **Enable VPC Flow Logs** - Detect unusual access patterns
5. ✅ **Tag resources** - Mark as "internal" or "protected" for security scans
6. ✅ **Use SSL/TLS** - Add ACM certificate and HTTPS listener (not covered here)

## Next Steps

1. Determine your deployment scenario (enterprise, testing, multi-account)
2. Get corporate CIDR from network team (if enterprise)
3. Run `cxwb init` and set `AllowedCidr` appropriately
4. Deploy: `cxwb build && cxwb deploy`
5. Test access: `curl http://<gateway-url>/health`

## References

- [AWS WAF Documentation](https://docs.aws.amazon.com/waf/)
- [VPC PrivateLink Guide](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [ALB Security Groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-update-security-groups.html)
