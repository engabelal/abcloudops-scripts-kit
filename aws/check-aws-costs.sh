#!/bin/bash

################################################################################
# Script Name:    check-aws-costs.sh
# Description:    AWS Cost & Resource Scanner - Identifies billable resources
#                 across your AWS account to help optimize costs
# Author:         Ahmed Belal
# Version:        v1.1
# Created:        2025-01-15
# Last Modified:  2025-01-15
# GitHub:         https://github.com/engabelal
# LinkedIn:       https://linkedin.com/in/engabelal
################################################################################

################################################################################
# CONFIGURATION
################################################################################

# AWS Region - Can be overridden with AWS_REGION environment variable
REGION="${AWS_REGION:-eu-north-1}"

# AWS Profile - Can be overridden with AWS_PROFILE environment variable
PROFILE="${AWS_PROFILE:-default}"

# Output report file with timestamp
OUTPUT_FILE="aws-cost-report-$(date +%Y%m%d-%H%M%S).txt"

################################################################################
# COLOR CODES FOR TERMINAL OUTPUT
################################################################################
RED='\033[0;31m'      # Red color for critical warnings
GREEN='\033[0;32m'    # Green color for success messages
YELLOW='\033[1;33m'   # Yellow color for warnings
NC='\033[0m'          # No Color - reset to default

################################################################################
# FUNCTIONS
################################################################################

# Function to log output to both console and file
# Usage: log_output "message"
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

################################################################################
# SCRIPT HEADER
################################################################################

log_output "="
log_output "🔍 AWS Cost & Resource Scanner v1.1"
log_output "Made by: Ahmed Belal | GitHub: @engabelal"
log_output "Region: $REGION | Profile: $PROFILE"
log_output "Date: $(date '+%Y-%m-%d %H:%M:%S')"
log_output "="
log_output ""

################################################################################
# INITIALIZE COUNTERS
################################################################################

# Counter for total billable resources found
TOTAL_COST_ITEMS=0

################################################################################
# 1️⃣ CHECK EC2 INSTANCES
# Running EC2 instances are billed per hour/second depending on instance type
################################################################################

log_output "\n💻 EC2 Instances (Running):"
EC2_COUNT=$(aws ec2 describe-instances --region "$REGION" --profile "$PROFILE" \
  --query "Reservations[].Instances[?State.Name=='running'] | length(@)" --output text)

if [ "$EC2_COUNT" -gt 0 ]; then
    aws ec2 describe-instances --region "$REGION" --profile "$PROFILE" \
      --query "Reservations[].Instances[?State.Name=='running'].[InstanceId,InstanceType,LaunchTime,Tags[?Key=='Name'].Value|[0]]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${YELLOW}⚠️  Found $EC2_COUNT running EC2 instance(s)${NC}"
    TOTAL_COST_ITEMS=$((TOTAL_COST_ITEMS + EC2_COUNT))
else
    log_output "${GREEN}✅ No running EC2 instances${NC}"
fi

################################################################################
# 2️⃣ CHECK ELASTIC IPs
# Unattached Elastic IPs are charged ~$0.005/hour
################################################################################

log_output "\n🌐 Elastic IPs (Unattached - Billed!):"
EIP_COUNT=$(aws ec2 describe-addresses --region "$REGION" --profile "$PROFILE" \
  --query "Addresses[?AssociationId==null] | length(@)" --output text)

if [ "$EIP_COUNT" -gt 0 ]; then
    aws ec2 describe-addresses --region "$REGION" --profile "$PROFILE" \
      --query "Addresses[?AssociationId==null].[PublicIp,AllocationId,Tags[?Key=='Name'].Value|[0]]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${RED}❌ Found $EIP_COUNT unattached Elastic IP(s) - WASTING MONEY!${NC}"
    TOTAL_COST_ITEMS=$((TOTAL_COST_ITEMS + EIP_COUNT))
else
    log_output "${GREEN}✅ No unattached Elastic IPs${NC}"
fi

################################################################################
# 3️⃣ CHECK EBS VOLUMES
# Detached EBS volumes are still billed for storage
################################################################################

log_output "\n💾 EBS Volumes (Detached - Still Billed!):"
EBS_COUNT=$(aws ec2 describe-volumes --region "$REGION" --profile "$PROFILE" \
  --query "Volumes[?State=='available'] | length(@)" --output text)

if [ "$EBS_COUNT" -gt 0 ]; then
    aws ec2 describe-volumes --region "$REGION" --profile "$PROFILE" \
      --query "Volumes[?State=='available'].[VolumeId,Size,VolumeType,CreateTime,Tags[?Key=='Name'].Value|[0]]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${RED}❌ Found $EBS_COUNT detached EBS volume(s) - WASTING MONEY!${NC}"
    TOTAL_COST_ITEMS=$((TOTAL_COST_ITEMS + EBS_COUNT))
else
    log_output "${GREEN}✅ No detached EBS volumes${NC}"
fi

################################################################################
# 4️⃣ CHECK LAMBDA FUNCTIONS
# Lambda functions are billed per invocation and execution time
################################################################################

log_output "\n⚙️ Lambda Functions:"
LAMBDA_COUNT=$(aws lambda list-functions --region "$REGION" --profile "$PROFILE" \
  --query "Functions | length(@)" --output text)

if [ "$LAMBDA_COUNT" -gt 0 ]; then
    aws lambda list-functions --region "$REGION" --profile "$PROFILE" \
      --query "Functions[].[FunctionName,Runtime,MemorySize,LastModified]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${YELLOW}📊 Found $LAMBDA_COUNT Lambda function(s)${NC}"
else
    log_output "${GREEN}✅ No Lambda functions${NC}"
fi

################################################################################
# 5️⃣ CHECK S3 BUCKETS
# S3 buckets are billed for storage and data transfer
################################################################################

log_output "\n🪣 S3 Buckets:"
S3_COUNT=$(aws s3 ls --profile "$PROFILE" 2>/dev/null | wc -l)

if [ "$S3_COUNT" -gt 0 ]; then
    aws s3 ls --profile "$PROFILE" | tee -a "$OUTPUT_FILE"
    log_output "${YELLOW}📊 Found $S3_COUNT S3 bucket(s)${NC}"
else
    log_output "${GREEN}✅ No S3 buckets${NC}"
fi

################################################################################
# 6️⃣ CHECK NAT GATEWAYS
# NAT Gateways are expensive: ~$0.045/hour + data processing charges
################################################################################

log_output "\n🚦 NAT Gateways (Very Expensive!):"
NAT_COUNT=$(aws ec2 describe-nat-gateways --region "$REGION" --profile "$PROFILE" \
  --query "NatGateways[?State=='available'] | length(@)" --output text)

if [ "$NAT_COUNT" -gt 0 ]; then
    aws ec2 describe-nat-gateways --region "$REGION" --profile "$PROFILE" \
      --query "NatGateways[?State=='available'].[NatGatewayId,State,CreateTime,Tags[?Key=='Name'].Value|[0]]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${RED}💸 Found $NAT_COUNT NAT Gateway(s) - ~$0.045/hour each!${NC}"
    TOTAL_COST_ITEMS=$((TOTAL_COST_ITEMS + NAT_COUNT))
else
    log_output "${GREEN}✅ No NAT Gateways${NC}"
fi

################################################################################
# 7️⃣ CHECK LOAD BALANCERS
# Application/Network Load Balancers are billed per hour + data processed
################################################################################

log_output "\n⚖️ Load Balancers:"
ALB_COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" --profile "$PROFILE" \
  --query "LoadBalancers | length(@)" --output text 2>/dev/null || echo "0")

if [ "$ALB_COUNT" -gt 0 ]; then
    aws elbv2 describe-load-balancers --region "$REGION" --profile "$PROFILE" \
      --query "LoadBalancers[].[LoadBalancerName,Type,State.Code,CreatedTime]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${YELLOW}⚠️  Found $ALB_COUNT Load Balancer(s)${NC}"
    TOTAL_COST_ITEMS=$((TOTAL_COST_ITEMS + ALB_COUNT))
else
    log_output "${GREEN}✅ No Load Balancers${NC}"
fi

################################################################################
# 8️⃣ CHECK RDS INSTANCES
# RDS instances are billed per hour based on instance class
################################################################################

log_output "\n🗄️ RDS Instances:"
RDS_COUNT=$(aws rds describe-db-instances --region "$REGION" --profile "$PROFILE" \
  --query "DBInstances | length(@)" --output text 2>/dev/null || echo "0")

if [ "$RDS_COUNT" -gt 0 ]; then
    aws rds describe-db-instances --region "$REGION" --profile "$PROFILE" \
      --query "DBInstances[].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus]" \
      --output table | tee -a "$OUTPUT_FILE"
    log_output "${YELLOW}⚠️  Found $RDS_COUNT RDS instance(s)${NC}"
    TOTAL_COST_ITEMS=$((TOTAL_COST_ITEMS + RDS_COUNT))
else
    log_output "${GREEN}✅ No RDS instances${NC}"
fi

################################################################################
# FINAL SUMMARY
################################################################################

log_output "\n="
log_output "📊 SUMMARY"
log_output "="
log_output "Total billable resources found: $TOTAL_COST_ITEMS"

if [ "$TOTAL_COST_ITEMS" -gt 0 ]; then
    log_output "${RED}⚠️  WARNING: You have $TOTAL_COST_ITEMS resources that may be costing money!${NC}"
else
    log_output "${GREEN}✅ Great! No costly resources found.${NC}"
fi

log_output "\n💾 Report saved to: $OUTPUT_FILE"
log_output "\n✅ Scan complete. Review the report above."