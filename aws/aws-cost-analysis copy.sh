#!/bin/bash

################################################################################
# AWS Cost Analysis Script
# 
# Description: Analyzes AWS costs for specified date ranges
# Requirements: aws-cli, jq, python3
# 
# Usage: 
#   ./aws-cost-analysis.sh
#       # Interactive mode (prompts for dates)
#   ./aws-cost-analysis.sh 2025-10-01 2025-11-01 2025-11-01 2025-11-07
#       # Non-interactive mode with explicit previous/current periods
#   ./aws-cost-analysis.sh --range 2025-11-01 2025-11-07
#       # Non-interactive mode (enter current period once; previous derived automatically)
#
# Arguments (non-interactive):
#   $1: Previous period start date (YYYY-MM-DD)
#   $2: Previous period end date (YYYY-MM-DD)
#   $3: Current period start date (YYYY-MM-DD)
#   $4: Current period end date (YYYY-MM-DD)
#   --range <Curr Start> <Curr End>: Provide a single period and derive the previous one
#
# Examples:
#   # Compare October vs November MTD
#   ./aws-cost-analysis.sh 2025-10-01 2025-11-01 2025-11-01 2025-11-07
#
#   # Compare Q3 vs Q4
#   ./aws-cost-analysis.sh 2025-07-01 2025-10-01 2025-10-01 2026-01-01
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
AUTO_RANGE_MODE=false

# Temp files
TEMP_DIR=$(mktemp -d)
CURRENT_MONTH_FILE="${TEMP_DIR}/current_month.json"
PREVIOUS_MONTH_FILE="${TEMP_DIR}/previous_month.json"

# Cleanup on exit
trap "rm -rf ${TEMP_DIR}" EXIT

################################################################################
# Functions
################################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v aws &> /dev/null; then
        log_error "aws-cli not found. Install: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install: brew install jq"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found"
        exit 1
    fi
    
    log_success "All requirements met"
}

verify_aws_credentials() {
    log_info "Verifying AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    
    log_success "Authenticated as: ${USER_ARN}"
    log_success "Account ID: ${ACCOUNT_ID}"
}

validate_date() {
    local date_str=$1
    local date_name=$2
    
    # Check format YYYY-MM-DD
    if ! [[ $date_str =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "${date_name}: Invalid format '${date_str}'. Use YYYY-MM-DD"
        return 1
    fi
    
    # Validate date is real
    if ! date -j -f "%Y-%m-%d" "$date_str" &>/dev/null 2>&1 && ! date -d "$date_str" &>/dev/null 2>&1; then
        log_error "${date_name}: Invalid date '${date_str}'"
        return 1
    fi
    
    return 0
}

calculate_days_between() {
    local start_date=$1
    local end_date=$2
    
    # Try macOS date command first, then Linux
    if date -j -f "%Y-%m-%d" "$start_date" &>/dev/null 2>&1; then
        # macOS
        local start_epoch=$(date -j -f "%Y-%m-%d" "$start_date" +%s)
        local end_epoch=$(date -j -f "%Y-%m-%d" "$end_date" +%s)
    else
        # Linux
        local start_epoch=$(date -d "$start_date" +%s)
        local end_epoch=$(date -d "$end_date" +%s)
    fi
    
    echo $(( (end_epoch - start_epoch) / 86400 ))
}

shift_date_by_days() {
    local base_date=$1
    local day_offset=$2
    
    python3 - "$base_date" "$day_offset" <<'PYTHON'
import sys
from datetime import datetime, timedelta

date_str = sys.argv[1]
offset = int(sys.argv[2])

dt = datetime.strptime(date_str, "%Y-%m-%d")
print((dt + timedelta(days=offset)).strftime("%Y-%m-%d"))
PYTHON
}

prompt_for_dates() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                         AWS COST ANALYSIS - DATE SELECTION"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Enter the date range to analyze AWS costs."
    echo ""
    echo "Format options:"
    echo "  • Provide both periods:"
    echo "        YYYY-MM-DD YYYY-MM-DD YYYY-MM-DD YYYY-MM-DD"
    echo "        [Prev Start] [Prev End] [Curr Start] [Curr End]"
    echo "  • Provide only the current period (previous derived automatically):"
    echo "        YYYY-MM-DD YYYY-MM-DD"
    echo "        [Curr Start] [Curr End]"
    echo ""
    echo "Examples:"
    echo "  • Compare October vs November MTD:"
    echo "    2025-10-01 2025-11-01 2025-11-01 2025-11-07"
    echo ""
    echo "  • Single entry (current week only):"
    echo "    2025-11-01 2025-11-07"
    echo "    (Previous week will be calculated automatically)"
    echo ""
    echo "  • Compare Q3 vs Q4:"
    echo "    2025-07-01 2025-10-01 2025-10-01 2026-01-01"
    echo ""
    echo "  • Compare same week in different months:"
    echo "    2025-10-01 2025-10-07 2025-11-01 2025-11-07"
    echo ""
    echo "────────────────────────────────────────────────────────────────────────────────"
    echo ""
    
    while true; do
        read -p "Enter dates: " date_input
        
        # Parse input into array
        read -ra dates <<< "$date_input"
        
        if [ ${#dates[@]} -eq 4 ]; then
            AUTO_RANGE_MODE=false
            PREVIOUS_MONTH_START="${dates[0]}"
            CURRENT_MONTH_FIRST="${dates[1]}"
            CURRENT_MONTH_START="${dates[2]}"
            CURRENT_MONTH_END="${dates[3]}"
            
            # Validate all dates
            local all_valid=true
            
            if ! validate_date "$PREVIOUS_MONTH_START" "Previous start date"; then
                all_valid=false
            fi
            
            if ! validate_date "$CURRENT_MONTH_FIRST" "Previous end date"; then
                all_valid=false
            fi
            
            if ! validate_date "$CURRENT_MONTH_START" "Current start date"; then
                all_valid=false
            fi
            
            if ! validate_date "$CURRENT_MONTH_END" "Current end date"; then
                all_valid=false
            fi
            
            if [ "$all_valid" = false ]; then
                echo ""
                continue
            fi
            
            if [[ ! "$CURRENT_MONTH_FIRST" > "$PREVIOUS_MONTH_START" ]]; then
                log_error "Previous end date must be after previous start date"
                echo ""
                continue
            fi
            
            if [[ ! "$CURRENT_MONTH_END" > "$CURRENT_MONTH_START" ]]; then
                log_error "Current end date must be after current start date"
                echo ""
                continue
            fi
            
            break
        elif [ ${#dates[@]} -eq 2 ]; then
            AUTO_RANGE_MODE=true
            PREVIOUS_MONTH_START=""
            CURRENT_MONTH_FIRST=""
            CURRENT_MONTH_START="${dates[0]}"
            CURRENT_MONTH_END="${dates[1]}"
            
            local all_valid=true
            
            if ! validate_date "$CURRENT_MONTH_START" "Current start date"; then
                all_valid=false
            fi
            
            if ! validate_date "$CURRENT_MONTH_END" "Current end date"; then
                all_valid=false
            fi
            
            if [ "$all_valid" = false ]; then
                echo ""
                continue
            fi
            
            if [[ ! "$CURRENT_MONTH_END" > "$CURRENT_MONTH_START" ]]; then
                log_error "Current end date must be after current start date"
                echo ""
                continue
            fi
            
            break
        else
            log_error "Expected 2 or 4 dates, got ${#dates[@]}. Please try again."
            echo ""
        fi
    done
    
    echo ""
    echo "────────────────────────────────────────────────────────────────────────────────"
}

get_date_ranges() {
    if [ $# -eq 0 ]; then
        prompt_for_dates
    elif [ "$1" = "--range" ]; then
        if [ $# -ne 3 ]; then
            log_error "Usage: $0 --range <current-start> <current-end>"
            exit 1
        fi
        
        AUTO_RANGE_MODE=true
        PREVIOUS_MONTH_START=""
        CURRENT_MONTH_FIRST=""
        CURRENT_MONTH_START=$2
        CURRENT_MONTH_END=$3
        
        log_info "Using provided current period and deriving previous period automatically..."
        
        validate_date "$CURRENT_MONTH_START" "Current start date" || exit 1
        validate_date "$CURRENT_MONTH_END" "Current end date" || exit 1
        
        if [[ ! "$CURRENT_MONTH_END" > "$CURRENT_MONTH_START" ]]; then
            log_error "Current end date must be after current start date"
            exit 1
        fi
    elif [ $# -eq 4 ]; then
        AUTO_RANGE_MODE=false
        PREVIOUS_MONTH_START=$1
        CURRENT_MONTH_FIRST=$2
        CURRENT_MONTH_START=$3
        CURRENT_MONTH_END=$4
        
        log_info "Using provided date ranges..."
        
        validate_date "$PREVIOUS_MONTH_START" "Previous start date" || exit 1
        validate_date "$CURRENT_MONTH_FIRST" "Previous end date" || exit 1
        validate_date "$CURRENT_MONTH_START" "Current start date" || exit 1
        validate_date "$CURRENT_MONTH_END" "Current end date" || exit 1
        
        if [[ ! "$CURRENT_MONTH_FIRST" > "$PREVIOUS_MONTH_START" ]]; then
            log_error "Previous end date must be after previous start date"
            exit 1
        fi
        
        if [[ ! "$CURRENT_MONTH_END" > "$CURRENT_MONTH_START" ]]; then
            log_error "Current end date must be after current start date"
            exit 1
        fi
    else
        log_error "Invalid arguments. Provide four dates or use --range <current-start> <current-end>."
        exit 1
    fi
    
    if [ "$AUTO_RANGE_MODE" = true ]; then
        CURRENT_MONTH_FIRST="$CURRENT_MONTH_START"
        local derived_days
        derived_days=$(calculate_days_between "$CURRENT_MONTH_START" "$CURRENT_MONTH_END")
        
        if [ "$derived_days" -le 0 ]; then
            log_error "Current end date must be after current start date"
            exit 1
        fi
        
        if ! PREVIOUS_MONTH_START=$(shift_date_by_days "$CURRENT_MONTH_START" "-$derived_days"); then
            log_error "Failed to derive previous period from supplied dates"
            exit 1
        fi
    fi
    
    # Calculate days in each period
    PREVIOUS_DAYS=$(calculate_days_between "$PREVIOUS_MONTH_START" "$CURRENT_MONTH_FIRST")
    CURRENT_DAY=$(calculate_days_between "$CURRENT_MONTH_START" "$CURRENT_MONTH_END")
    
    if [ "$PREVIOUS_DAYS" -le 0 ]; then
        log_error "Previous period end date must be after its start date"
        exit 1
    fi
    
    if [ "$CURRENT_DAY" -le 0 ]; then
        log_error "Current period end date must be after its start date"
        exit 1
    fi
    
    # Generate period names
    PREVIOUS_MONTH_NAME="${PREVIOUS_MONTH_START} to ${CURRENT_MONTH_FIRST}"
    CURRENT_MONTH_NAME="${CURRENT_MONTH_START} to ${CURRENT_MONTH_END}"
    
    echo ""
    log_success "Date ranges configured:"
    log_info "  Previous Period: ${PREVIOUS_MONTH_NAME} (${PREVIOUS_DAYS} days)"
    log_info "  Current Period:  ${CURRENT_MONTH_NAME} (${CURRENT_DAY} days)"
    echo ""
}

fetch_cost_data() {
    log_info "Fetching current month cost data..."
    
    aws ce get-cost-and-usage \
        --time-period Start="${CURRENT_MONTH_START}",End="${CURRENT_MONTH_END}" \
        --granularity DAILY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --output json > "${CURRENT_MONTH_FILE}"
    
    log_success "Current month data fetched"
    
    log_info "Fetching previous month cost data..."
    
    aws ce get-cost-and-usage \
        --time-period Start="${PREVIOUS_MONTH_START}",End="${CURRENT_MONTH_FIRST}" \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --output json > "${PREVIOUS_MONTH_FILE}"
    
    log_success "Previous month data fetched"
}

analyze_costs() {
    log_info "Analyzing cost data..."
    
    python3 - "${CURRENT_MONTH_FILE}" "${PREVIOUS_MONTH_FILE}" "${CURRENT_DAY}" "${CURRENT_MONTH_NAME}" "${PREVIOUS_MONTH_NAME}" << 'PYTHON_EOF'
import json
import sys

# Get arguments from bash
current_month_file = sys.argv[1]
previous_month_file = sys.argv[2]
days_in_month = int(sys.argv[3])
current_month_name = sys.argv[4]
previous_month_name = sys.argv[5]

# Load data
with open(current_month_file, 'r') as f:
    current_data = json.load(f)

with open(previous_month_file, 'r') as f:
    previous_data = json.load(f)

# Process current month (MTD)
current_services = {}
current_total = 0

for day in current_data['ResultsByTime']:
    for group in day['Groups']:
        service = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        current_services[service] = current_services.get(service, 0) + cost
        current_total += cost

# Process previous month (full month or multi-month range)
previous_services = {}
previous_total = 0

for period in previous_data['ResultsByTime']:
    for group in period['Groups']:
        service = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        previous_services[service] = previous_services.get(service, 0) + cost
        previous_total += cost

# Sort services by cost
current_sorted = sorted(current_services.items(), key=lambda x: x[1], reverse=True)
previous_sorted = sorted(previous_services.items(), key=lambda x: x[1], reverse=True)

# Calculate projections
daily_avg = current_total / days_in_month if days_in_month > 0 else 0
projected_month = daily_avg * 30

print("=" * 80)
print("AWS COST ANALYSIS REPORT")
print("=" * 80)
print()

# Current Month Section
print(f"📊 {current_month_name} (Month-to-Date: {days_in_month} days)")
print("-" * 80)
print(f"Current Total:       \${current_total:>10.2f}")
print(f"Daily Average:       \${daily_avg:>10.2f}")
print(f"Projected Month:     \${projected_month:>10.2f}")
print()

if current_sorted:
    print("Top Services:")
    for service, cost in current_sorted[:15]:
        if cost > 0.01:
            pct = (cost/current_total)*100 if current_total > 0 else 0
            print(f"  {service:50s} \${cost:8.2f} ({pct:5.1f}%)")
else:
    print("  No significant costs recorded")
print()

# Previous Month Section
print("=" * 80)
print(f"📊 {previous_month_name} (Full Month)")
print("-" * 80)
print(f"Total:               \${previous_total:>10.2f}")
print()

if previous_sorted:
    print("Top Services:")
    for service, cost in previous_sorted[:15]:
        if cost > 0.01:
            pct = (cost/previous_total)*100 if previous_total > 0 else 0
            print(f"  {service:50s} \${cost:8.2f} ({pct:5.1f}%)")
else:
    print("  No significant costs recorded")
print()

# Comparison Section
print("=" * 80)
print("📈 COMPARISON & INSIGHTS")
print("-" * 80)

change = projected_month - previous_total
change_pct = (change/previous_total)*100 if previous_total > 0 else 0

print(f"Previous Month:      \${previous_total:>10.2f}")
print(f"Current Projected:   \${projected_month:>10.2f}")
print(f"Expected Change:     \${change:>+10.2f} ({change_pct:>+6.1f}%)")
print()

# Service-level changes
print("Service Changes (Top movers):")
service_changes = []
all_services = set(list(current_services.keys()) + list(previous_services.keys()))

for service in all_services:
    current_cost = current_services.get(service, 0)
    previous_cost = previous_services.get(service, 0)
    current_projected_svc = (current_cost/days_in_month)*30 if days_in_month > 0 else 0
    change = current_projected_svc - previous_cost
    
    if abs(change) > 0.10:  # Only show changes > \$0.10
        service_changes.append((service, previous_cost, current_projected_svc, change))

if service_changes:
    service_changes.sort(key=lambda x: abs(x[3]), reverse=True)
    for service, prev_cost, curr_proj, change in service_changes[:15]:
        arrow = "↑" if change > 0 else "↓"
        print(f"  {arrow} {service:48s} \${prev_cost:7.2f} → \${curr_proj:7.2f} ({change:+7.2f})")
else:
    print("  No significant changes detected")

print()

# Cost Optimization Recommendations
print("=" * 80)
print("💡 COST OPTIMIZATION RECOMMENDATIONS")
print("-" * 80)

recommendations = []

# Check for high-cost services
for service, cost in current_sorted[:5]:
    if cost > current_total * 0.2:  # Service is >20% of total
        recommendations.append(f"• {service} accounts for {(cost/current_total)*100:.1f}% of costs - review for optimization")

# Check for unusual spikes
for service, prev_cost, curr_proj, change in service_changes[:3]:
    if prev_cost > 0 and change > prev_cost * 0.5 and change > 1.0:  # >50% increase and >$1
        recommendations.append(f"• {service} increased by {(change/prev_cost)*100:.0f}% - investigate cause")
    elif prev_cost == 0 and change > 1.0:  # New service with significant cost
        recommendations.append(f"• {service} is a new service costing ${change:.2f}/month - verify if needed")

# Check for idle resources
if 'Amazon Elastic Compute Cloud - Compute' in current_services:
    recommendations.append("• Review EC2 instances for right-sizing opportunities")

if 'Amazon Relational Database Service' in current_services:
    recommendations.append("• Check RDS instances for unused capacity")

if 'Amazon Elastic Load Balancing' in current_services:
    recommendations.append("• Review load balancers - remove unused ones")

if recommendations:
    for rec in recommendations[:10]:
        print(rec)
else:
    print("• No immediate optimization opportunities detected")
    print("• Continue monitoring for cost trends")

print()
print("=" * 80)
from datetime import datetime, timezone
print(f"Report Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
print("=" * 80)

PYTHON_EOF
}

################################################################################
# Main
################################################################################

main() {
    echo ""
    log_info "Starting AWS Cost Analysis..."
    echo ""
    
    check_requirements
    verify_aws_credentials
    get_date_ranges "$@"
    fetch_cost_data
    analyze_costs
    
    echo ""
    log_success "Analysis complete!"
    echo ""
}

main "$@"
