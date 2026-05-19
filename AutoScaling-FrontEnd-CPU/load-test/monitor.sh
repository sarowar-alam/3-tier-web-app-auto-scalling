#!/bin/bash
# Real-time monitoring script for Auto Scaling Group activity
# Displays ASG status, instance count, and CloudWatch metrics

set -uo pipefail
# Configuration
ASG_NAME="${1:-}"
REGION="${2:-us-east-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Auto Scaling Group Monitor${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Check if ASG name is provided
if [ -z "$ASG_NAME" ]; then
    echo -e "${RED}Error: Auto Scaling Group name not provided${NC}"
    echo "Usage: $0 <asg-name> [region]"
    echo "Example: $0 bmi-frontend-asg us-east-1"
    echo ""
    echo "Available ASGs:"
    aws autoscaling describe-auto-scaling-groups --region ${REGION} --query 'AutoScalingGroups[*].AutoScalingGroupName' --output table
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found. Please install it first.${NC}"
    exit 1
fi

echo -e "Monitoring ASG: ${YELLOW}${ASG_NAME}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "${CYAN}Press Ctrl+C to stop monitoring${NC}"
echo ""

# Function to get ASG details
get_asg_details() {
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --output json 2>/dev/null
}

# Function to get CloudWatch metrics
get_cpu_metrics() {
    local instance_id=$1
    aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 60 \
        --statistics Average \
        --region "$REGION" \
        --output json 2>/dev/null | \
        jq -r '.Datapoints | sort_by(.Timestamp) | last | .Average // 0' 2>/dev/null || echo "0"
}

# Monitoring loop
while true; do
    clear
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}Auto Scaling Group Status${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "Time: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # Get ASG details
    ASG_DATA=$(get_asg_details)
    
    if [ -z "$ASG_DATA" ] || [ "$ASG_DATA" == "null" ]; then
        echo -e "${RED}Error: Could not fetch ASG details${NC}"
        echo "Please verify:"
        echo "  1. ASG name is correct"
        echo "  2. AWS credentials are configured"
        echo "  3. Region is correct"
        sleep 5
        continue
    fi

    # Parse ASG information
    MIN_SIZE=$(echo "$ASG_DATA" | jq -r '.AutoScalingGroups[0].MinSize')
    MAX_SIZE=$(echo "$ASG_DATA" | jq -r '.AutoScalingGroups[0].MaxSize')
    DESIRED_CAPACITY=$(echo "$ASG_DATA" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
    CURRENT_INSTANCES=$(echo "$ASG_DATA" | jq -r '.AutoScalingGroups[0].Instances | length')
    
    echo -e "${CYAN}Capacity:${NC}"
    echo -e "  Min: ${YELLOW}${MIN_SIZE}${NC} | Desired: ${YELLOW}${DESIRED_CAPACITY}${NC} | Max: ${YELLOW}${MAX_SIZE}${NC} | Current: ${YELLOW}${CURRENT_INSTANCES}${NC}"
    echo ""

    # Display instances
    echo -e "${CYAN}Instances:${NC}"
    printf "%-20s %-15s %-15s %-10s %-10s\n" "Instance ID" "State" "Health" "AZ" "CPU %"
    echo "--------------------------------------------------------------------------------"
    
    echo "$ASG_DATA" | jq -r '.AutoScalingGroups[0].Instances[] | "\(.InstanceId) \(.LifecycleState) \(.HealthStatus) \(.AvailabilityZone)"' | \
    while read -r instance_id state health az; do
        # Get CPU metrics (this is slow, so we do it only for InService instances)
        if [ "$state" == "InService" ]; then
            cpu=$(get_cpu_metrics "$instance_id")
            cpu_formatted=$(printf "%.1f" "$cpu" 2>/dev/null || echo "N/A")
        else
            cpu_formatted="N/A"
        fi
        
        # Color code by state
        if [ "$state" == "InService" ]; then
            state_color="${GREEN}"
        elif [ "$state" == "Pending" ]; then
            state_color="${YELLOW}"
        else
            state_color="${RED}"
        fi
        
        printf "%-20s ${state_color}%-15s${NC} %-15s %-10s %-10s\n" \
            "$instance_id" "$state" "$health" "$az" "$cpu_formatted"
    done
    
    echo ""

    # Display recent scaling activities
    echo -e "${CYAN}Recent Scaling Activities (last 5):${NC}"
    aws autoscaling describe-scaling-activities \
        --auto-scaling-group-name "$ASG_NAME" \
        --max-records 5 \
        --region "$REGION" \
        --output json 2>/dev/null | \
    jq -r '.Activities[] | "\(.StartTime) | \(.Description) | \(.StatusCode)"' | \
    while IFS='|' read -r time desc status; do
        if [[ "$status" == *"Successful"* ]]; then
            status_color="${GREEN}"
        elif [[ "$status" == *"InProgress"* ]]; then
            status_color="${YELLOW}"
        else
            status_color="${RED}"
        fi
        echo -e "  ${time} | ${desc} | ${status_color}${status}${NC}"
    done
    
    echo ""
    echo -e "${CYAN}Refreshing in 10 seconds... (Ctrl+C to stop)${NC}"
    sleep 10
done
