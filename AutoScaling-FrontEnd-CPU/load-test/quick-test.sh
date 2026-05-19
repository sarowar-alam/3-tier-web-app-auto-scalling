#!/bin/bash
# Load Testing Script for Frontend Auto-Scaling Demo
# Generates heavy CPU load on frontend instances to trigger auto-scaling

set -euo pipefail

# Configuration
FRONTEND_ALB_URL="${1:-}"
CONCURRENT_USERS=100
TOTAL_REQUESTS=50000
TEST_DURATION=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}BMI App Auto-Scaling Load Test${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Check if ALB URL is provided
if [ -z "$FRONTEND_ALB_URL" ]; then
    echo -e "${RED}Error: Frontend ALB URL not provided${NC}"
    echo "Usage: $0 <frontend-alb-url>"
    echo "Example: $0 http://bmi-frontend-alb-1234567890.us-east-1.elb.amazonaws.com"
    exit 1
fi

# Remove trailing slash if present
FRONTEND_ALB_URL=${FRONTEND_ALB_URL%/}

echo -e "Target: ${YELLOW}${FRONTEND_ALB_URL}${NC}"
echo -e "Concurrent Users: ${YELLOW}${CONCURRENT_USERS}${NC}"
echo -e "Total Requests: ${YELLOW}${TOTAL_REQUESTS}${NC}"
echo -e "Duration: ${YELLOW}${TEST_DURATION} seconds${NC}"
echo ""

# Check if Apache Bench is installed
if ! command -v ab &> /dev/null; then
    echo -e "${YELLOW}Apache Bench (ab) not found. Installing...${NC}"
    
    # Detect OS and install
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo yum install -y httpd-tools || sudo apt-get install -y apache2-utils
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "ab should be pre-installed on macOS"
    else
        echo -e "${RED}Please install Apache Bench (ab) manually${NC}"
        exit 1
    fi
fi

# Test connectivity
echo -e "${YELLOW}Testing connectivity...${NC}"
if ! curl -s -o /dev/null -w "%{http_code}" "${FRONTEND_ALB_URL}" | grep -q "200"; then
    echo -e "${RED}Error: Cannot connect to ${FRONTEND_ALB_URL}${NC}"
    echo "Please verify the ALB URL is correct and accessible"
    exit 1
fi
echo -e "${GREEN}✓ Connection successful${NC}"
echo ""

# Function to generate POST data
generate_post_data() {
    cat << EOF
{
  "weightKg": $((RANDOM % 50 + 50)),
  "heightCm": $((RANDOM % 50 + 150)),
  "age": $((RANDOM % 40 + 20)),
  "sex": "male",
  "activity": "moderate",
  "measurementDate": "$(date +%Y-%m-%d)"
}
EOF
}

# Create temp file for POST data
POST_DATA=$(mktemp)
generate_post_data > "$POST_DATA"

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Starting Load Test${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Phase 1: Warmup (30 seconds)${NC}"
ab -n 1000 -c 10 "${FRONTEND_ALB_URL}/" > /dev/null 2>&1 &
sleep 30

echo -e "${YELLOW}Phase 2: Gradual Increase (60 seconds)${NC}"
ab -n 5000 -c 25 "${FRONTEND_ALB_URL}/" > /dev/null 2>&1 &
sleep 60

echo -e "${YELLOW}Phase 3: Heavy Load - GET Requests${NC}"
echo "Target: ${FRONTEND_ALB_URL}/"
ab -n $((TOTAL_REQUESTS / 2)) -c ${CONCURRENT_USERS} -t ${TEST_DURATION} "${FRONTEND_ALB_URL}/" &
GET_PID=$!

echo ""
echo -e "${YELLOW}Phase 4: Heavy Load - API POST Requests${NC}"
echo "Target: ${FRONTEND_ALB_URL}/api/measurements"
ab -n $((TOTAL_REQUESTS / 4)) -c $((CONCURRENT_USERS / 2)) -t ${TEST_DURATION} \
   -p "$POST_DATA" -T "application/json" \
   "${FRONTEND_ALB_URL}/api/measurements" &
POST_PID=$!

echo ""
echo -e "${YELLOW}Phase 5: Heavy Load - API GET Requests${NC}"
echo "Target: ${FRONTEND_ALB_URL}/api/measurements"
ab -n $((TOTAL_REQUESTS / 4)) -c $((CONCURRENT_USERS / 2)) -t ${TEST_DURATION} \
   "${FRONTEND_ALB_URL}/api/measurements" &
API_GET_PID=$!

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Load Test Running...${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Monitor CloudWatch metrics to see:${NC}"
echo "  1. CPU utilization increasing to 60%+"
echo "  2. Auto Scaling Group launching new instances"
echo "  3. New instances registering with target group"
echo "  4. Load distributed across instances"
echo ""
echo -e "${YELLOW}In AWS Console:${NC}"
echo "  - EC2 > Auto Scaling Groups > [Your ASG] > Activity"
echo "  - CloudWatch > Dashboards > EC2 Metrics"
echo "  - Target Group > Targets (watch new instances registering)"
echo ""
echo -e "${RED}Press Ctrl+C to stop the test early${NC}"
echo ""

# Wait for tests to complete
wait $GET_PID
wait $POST_PID
wait $API_GET_PID

# Cleanup
rm -f "$POST_DATA"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Load Test Complete${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Check Auto Scaling Group activity history"
echo "  2. Wait 5-10 minutes for scale-in (after cooldown period)"
echo "  3. Verify instances terminating back to desired capacity"
echo ""
echo -e "${GREEN}Done!${NC}"
