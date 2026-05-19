# AWS Auto-Scaling Demo - Frontend CPU-Based Scaling

**Quick 1-Hour Setup Guide for BMI Health Tracker**

This guide sets up a 3-tier architecture with **Frontend Auto-Scaling based on CPU utilization** (60% target).

---

## Architecture Overview

```
Internet
   ↓
[Public ALB] ← Frontend Load Balancer
   ↓
[Frontend ASG] ← 2-4 EC2 instances (Auto-scales on CPU 60%)
   ↓ (proxies /api requests)
[Internal ALB] ← Backend Load Balancer
   ↓
[Backend EC2] ← 2 fixed instances
   ↓
[Aurora Serverless v2] ← PostgreSQL (0.5-2 ACU, auto-scales)
```

**Key Features:**
- ✅ Frontend auto-scales based on CPU utilization (60% target)
- ✅ Backend fixed at 2 instances (no auto-scaling)
- ✅ Aurora Serverless v2 auto-scales compute (0.5→2 ACU)
- ✅ SSM Session Manager for secure access (no SSH keys)
- ✅ All private subnets (frontend + backend in private)
- ✅ Multi-AZ setup for high availability

**Estimated Costs:**
- ~$2-3 for 1-hour demo
- ~$10-15 if left running for 24 hours

---

## Prerequisites

- AWS Account with admin access
- AWS CLI installed locally (for monitoring)
- Basic understanding of AWS Console
- GitHub repo: `https://github.com/sarowar-alam/3-tier-web-app-auto-scalling.git`

---

## Phase 1: Network Setup (5 minutes)

### Step 1.1: Use Existing VPC ✅

**You already have the VPC infrastructure!** We'll use:
- **VPC**: `devops-vpc` (10.0.0.0/16)
- **Region**: `ap-south-1` (Mumbai)
- **Public Subnets**:
  - `devops-subnet-public1-ap-south-1a` (10.0.0.0/20)
  - `devops-subnet-public2-ap-south-1b` (10.0.16.0/20)
- **Private Subnets**:
  - `devops-subnet-private1-ap-south-1a` (10.0.128.0/20)
  - `devops-subnet-private2-ap-south-1b` (10.0.144.0/20)
- **NAT Gateway**: `devops-regional-nat` ✅ (already exists)
- **Internet Gateway**: `devops-igw` ✅ (already exists)
- **S3 Gateway Endpoint**: `devops-vpce-s3` ✅ (already exists)

**No VPC creation needed!** Skip to creating SSM endpoints.

### Step 1.2: Create VPC Endpoints for SSM

1. Go to **VPC** → **Endpoints** → **Create endpoint**

**Create 3 endpoints:**

**Endpoint 1: SSM**
- **Name**: `bmi-ssm-endpoint`
- **Service**: `com.amazonaws.ap-south-1.ssm`
- **VPC**: Select `devops-vpc`
- **Subnets**: Select both private subnets:
  - `devops-subnet-private1-ap-south-1a`
  - `devops-subnet-private2-ap-south-1b`
- **Security group**: Create new → `ssm-endpoint-sg`
  - Inbound: HTTPS (443) from `10.0.0.0/16`
- Click **Create endpoint**

**Endpoint 2: EC2 Messages**
- **Name**: `bmi-ec2messages-endpoint`
- **Service**: `com.amazonaws.ap-south-1.ec2messages`
- **VPC**: Select `devops-vpc`
- **Subnets**: Select both private subnets (same as above)
- **Security group**: Select `ssm-endpoint-sg`
- Click **Create endpoint**

**Endpoint 3: SSM Messages**
- **Name**: `bmi-ssmmessages-endpoint`
- **Service**: `com.amazonaws.ap-south-1.ssmmessages`
- **VPC**: Select `devops-vpc`
- **Subnets**: Select both private subnets (same as above)
- **Security group**: Select `ssm-endpoint-sg`
- Click **Create endpoint**

---

## Phase 2: Database Setup (15 minutes)

### Step 2.1: Create DB Subnet Group

1. Go to **RDS** → **Subnet groups** → **Create DB subnet group**
2. Configure:
   - **Name**: `bmi-db-subnet-group`
   - **Description**: `Subnet group for BMI Aurora cluster`
   - **VPC**: Select `devops-vpc`
   - **Availability Zones**: Select **ap-south-1a** and **ap-south-1b**
   - **Subnets**: Select **both private subnets**:
     - `devops-subnet-private1-ap-south-1a` (10.0.128.0/20)
     - `devops-subnet-private2-ap-south-1b` (10.0.144.0/20)
3. Click **Create**

### Step 2.2: Create Aurora Security Group

1. Go to **EC2** → **Security Groups** → **Create security group**
2. Configure:
   - **Name**: `aurora-sg`
   - **Description**: `Security group for Aurora PostgreSQL`
   - **VPC**: Select `devops-vpc`
3. **Inbound rules**:
   - Type: `PostgreSQL` (5432)
   - Source: `10.0.0.0/16` (entire VPC)
   - Description: `Allow from VPC`
4. Click **Create security group**

### Step 2.3: Create Aurora Serverless v2 Cluster

1. Go to **RDS** → **Databases** → **Create database**
2. Configure:

**Engine options:**
- **Engine type**: `Aurora (PostgreSQL Compatible)`
- **Engine version**: `Aurora PostgreSQL (Compatible with PostgreSQL 15.x)` (latest)
- **Template**: `Dev/Test` (not Production - saves cost)

**DB cluster identifier:**
- **Name**: `bmi-aurora-cluster`

**Credentials:**
- **Master username**: `postgres`
- **Master password**: `YourSecurePassword123!` (remember this!)
- **Confirm password**: Same as above

**Instance configuration:**
- **DB instance class**: `Serverless v2`
- **Minimum ACUs**: `0.5`
- **Maximum ACUs**: `2`

**Connectivity:**
- **VPC**: Select `devops-vpc`
- **DB subnet group**: Select `bmi-db-subnet-group`
- **Public access**: `No`
- **VPC security group**: Choose existing → Select `aurora-sg`
- **Availability Zone**: `No preference`

**Database options:**
- **Initial database name**: `bmidb`
- Leave other options as default

**Backup:**
- **Automated backups**: Uncheck (for demo only)

**Monitoring:**
- **Enhanced monitoring**: Uncheck (for demo only)

3. Click **Create database**
4. Wait ~10-12 minutes for Aurora cluster to be available

**Note the endpoint:**
- Go to **RDS** → **Databases** → Click `bmi-aurora-cluster`
- Copy **Writer endpoint** (e.g., `bmi-aurora-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com`)

---

## Phase 3: IAM Role Setup (5 minutes)

### Step 3.1: Create IAM Role

1. Go to **IAM** → **Roles** → **Create role**
2. **Trusted entity**: Select `AWS service` → `EC2`
3. Click **Next**

**Attach policies:**
- Search and select: `AmazonSSMManagedInstanceCore`
- Search and select: `CloudWatchAgentServerPolicy`
- Click **Next**

4. **Role name**: `EC2RoleForBMIApp`
5. **Description**: `Role for BMI App EC2 instances with SSM and Parameter Store access`
6. Click **Create role**

### Step 3.2: Add Inline Policy for Parameter Store

1. Go to **IAM** → **Roles** → Find `EC2RoleForBMIApp`
2. Click on the role → **Permissions** tab
3. Click **Add permissions** → **Create inline policy**
4. Switch to **JSON** tab
5. Paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:ap-south-1:YOUR_ACCOUNT_ID:parameter/bmi-app/*"
    },
    {
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "arn:aws:kms:ap-south-1:YOUR_ACCOUNT_ID:key/*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "ssm.ap-south-1.amazonaws.com"
        }
      }
    }
  ]
}
```

> Replace `YOUR_ACCOUNT_ID` with your 12-digit AWS account number.
> The KMS resource is now scoped to your account only — previously it was `"*"` which allowed decrypting any key in the account (audit fix #11).

6. Click **Review policy**
7. **Name**: `BMIAppParameterStoreAccess`
8. Click **Create policy**

---

## Phase 4: Parameter Store Configuration (3 minutes)

### Step 4.1: Create Parameters

Go to **Systems Manager** → **Parameter Store** → **Create parameter**

Create these 5 parameters:

**Parameter 1: Database Host**
- **Name**: `/bmi-app/db-host`
- **Description**: `Aurora cluster endpoint`
- **Type**: `String`
- **Value**: `<Your-Aurora-Writer-Endpoint>` (e.g., `bmi-aurora-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com`)
- Click **Create parameter**

**Parameter 2: Database Name**
- **Name**: `/bmi-app/db-name`
- **Type**: `String`
- **Value**: `bmidb`
- Click **Create parameter**

**Parameter 3: Database User**
- **Name**: `/bmi-app/db-user`
- **Type**: `String`
- **Value**: `postgres`
- Click **Create parameter**

**Parameter 4: Database Password**
- **Name**: `/bmi-app/db-password`
- **Type**: `SecureString`
- **Value**: `YourSecurePassword123!` (same as Aurora password)
- Click **Create parameter**

**Parameter 5: Backend ALB URL (Placeholder)**
- **Name**: `/bmi-app/backend-alb-url`
- **Type**: `String`
- **Value**: `http://placeholder` (will update later)
- Click **Create parameter**

---

## Phase 5: Security Groups Setup (5 minutes)

### Step 5.1: Create Frontend ALB Security Group

1. Go to **EC2** → **Security Groups** → **Create security group**
2. Configure:
   - **Name**: `frontend-alb-sg`
   - **Description**: `Security group for Frontend ALB`
   - **VPC**: Select `devops-vpc`
3. **Inbound rules**:
   - Type: `HTTP` (80), Source: `0.0.0.0/0`, Description: `Allow HTTP from internet`
   - Type: `HTTPS` (443), Source: `0.0.0.0/0`, Description: `Allow HTTPS from internet`
4. **Outbound rules**: Leave default (all traffic)
5. Click **Create security group**

### Step 5.2: Create Frontend EC2 Security Group

1. **Create security group**:
   - **Name**: `frontend-ec2-sg`
   - **Description**: `Security group for Frontend EC2 instances`
   - **VPC**: Select `devops-vpc`
2. **Inbound rules**:
   - Type: `HTTP` (80), Source: Select `frontend-alb-sg`, Description: `Allow from Frontend ALB`
   - Type: `HTTPS` (443), Source: `10.0.0.0/16`, Description: `Allow HTTPS within VPC`
3. Click **Create security group**

### Step 5.3: Create Backend ALB Security Group

1. **Create security group**:
   - **Name**: `backend-alb-sg`
   - **Description**: `Security group for Backend Internal ALB`
   - **VPC**: Select `devops-vpc`
2. **Inbound rules**:
   - Type: `HTTP` (80), Source: Select `frontend-ec2-sg`, Description: `Allow from Frontend EC2`
3. Click **Create security group**

### Step 5.4: Create Backend EC2 Security Group

1. **Create security group**:
   - **Name**: `backend-ec2-sg`
   - **Description**: `Security group for Backend EC2 instances`
   - **VPC**: Select `devops-vpc`
2. **Inbound rules**:
   - Type: `Custom TCP` (3000), Source: Select `backend-alb-sg`, Description: `Allow from Backend ALB`
3. Click **Create security group**

### Step 5.5: Update Aurora Security Group

1. Go to **Security Groups** → Find `aurora-sg`
2. **Edit inbound rules**:
   - Delete existing rule
   - Add: Type `PostgreSQL` (5432), Source: Select `backend-ec2-sg`, Description: `Allow from Backend EC2`
3. Click **Save rules**

---

## Phase 6: Create Golden AMIs (20 minutes)

### Step 6.1: Launch Temporary Backend Instance

1. Go to **EC2** → **Launch instance**
2. Configure:
   - **Name**: `backend-golden-ami-temp`
   - **AMI**: `Amazon Linux 2023 AMI` (latest)
   - **Instance type**: `t3.micro`
   - **Key pair**: Select existing or create new
   - **Network**:
     - VPC: `devops-vpc`
     - Subnet: Select `devops-subnet-public1-ap-south-1a` (for initial setup)
     - Auto-assign public IP: `Enable`
   - **Security group**: Create new → Allow SSH (22) from your IP
   - **IAM instance profile**: Select `EC2RoleForBMIApp`
3. Click **Launch instance**
4. Wait for instance to be running

### Step 6.2: Connect and Setup Backend AMI

1. Connect via **Session Manager** (or SSH)
2. Run setup script:

```bash
# Download and run the backend setup script
wget https://raw.githubusercontent.com/sarowar-alam/3-tier-web-app-auto-scalling/main/AutoScaling-FrontEnd-CPU/backend-userdata.sh
chmod +x backend-userdata.sh
sudo ./backend-userdata.sh
```

3. Wait ~5 minutes for installation
4. Verify installations:
```bash
node --version  # Should show v20.x
pm2 --version   # Should show PM2
psql --version  # Should show PostgreSQL 15
```

### Step 6.3: Create Backend AMI

1. Go to **EC2** → **Instances**
2. Select `backend-golden-ami-temp`
3. **Actions** → **Image and templates** → **Create image**
4. Configure:
   - **Image name**: `bmi-backend-golden-ami`
   - **Description**: `Golden AMI for BMI Backend with Node.js 20 and PM2`
   - **No reboot**: Leave unchecked
5. Click **Create image**
6. Wait ~3-5 minutes
7. Go to **AMIs** and note the AMI ID (e.g., `ami-xxxxxxxxx`)

### Step 6.4: Launch Temporary Frontend Instance

1. **Launch instance**:
   - **Name**: `frontend-golden-ami-temp`
   - **AMI**: `Amazon Linux 2023 AMI`
   - **Instance type**: `t3.micro`
   - **Network**: Same as backend (public subnet)
   - **Security group**: Allow SSH from your IP
   - **IAM instance profile**: `EC2RoleForBMIApp`
2. Click **Launch instance**

### Step 6.5: Connect and Setup Frontend AMI

1. Connect via **Session Manager**
2. Run setup script:

```bash
wget https://raw.githubusercontent.com/sarowar-alam/3-tier-web-app-auto-scalling/main/AutoScaling-FrontEnd-CPU/frontend-userdata.sh
chmod +x frontend-userdata.sh
sudo ./frontend-userdata.sh
```

3. Wait ~5 minutes
4. Verify:
```bash
node --version   # v20.x
nginx -v         # nginx version
```

### Step 6.6: Create Frontend AMI

1. Select `frontend-golden-ami-temp`
2. **Actions** → **Create image**
3. Configure:
   - **Image name**: `bmi-frontend-golden-ami`
   - **Description**: `Golden AMI for BMI Frontend with nginx and Node.js 20`
4. Click **Create image**
5. Wait ~3-5 minutes
6. Note the AMI ID

### Step 6.7: Terminate Temporary Instances

1. Select both temporary instances
2. **Instance state** → **Terminate instance**

---

## Phase 7: Application Load Balancers (10 minutes)

### Step 7.1: Create Backend Target Group

1. Go to **EC2** → **Target Groups** → **Create target group**
2. Configure:
   - **Target type**: `Instances`
   - **Name**: `bmi-backend-tg`
   - **Protocol**: `HTTP`, Port: `3000`
   - **VPC**: Select `devops-vpc`
   - **Health check**:
     - Protocol: `HTTP`
     - Path: `/health`
     - Interval: `10 seconds`
     - Timeout: `5 seconds`
     - Healthy threshold: `2`
     - Unhealthy threshold: `3`
3. Click **Next**
4. **Don't register any targets yet**
5. Click **Create target group**

### Step 7.2: Create Backend ALB (Internal)

1. Go to **EC2** → **Load Balancers** → **Create Load Balancer**
2. Choose **Application Load Balancer**
3. Configure:
   - **Name**: `bmi-backend-alb`
   - **Scheme**: `Internal` ⚠️ (not internet-facing)
   - **IP address type**: `IPv4`
   - **VPC**: Select `devops-vpc`
   - **Mappings**: Select **both AZs** and **both private subnets**:
     - ap-south-1a: `devops-subnet-private1-ap-south-1a`
     - ap-south-1b: `devops-subnet-private2-ap-south-1b`
   - **Security groups**: Select `backend-alb-sg`
   - **Listeners**: HTTP (80)
   - **Default action**: Forward to `bmi-backend-tg`
4. Click **Create load balancer**
5. Wait ~2 minutes
6. **Copy the DNS name** (e.g., `internal-bmi-backend-alb-xxxxx.us-east-1.elb.amazonaws.com`)

### Step 7.3: Update Parameter Store with Backend ALB URL

1. Go to **Systems Manager** → **Parameter Store**
2. Click `/bmi-app/backend-alb-url`
3. Click **Edit**
4. Update **Value**: `http://<backend-alb-dns-name>` (e.g., `http://internal-bmi-backend-alb-xxxxx.us-east-1.elb.amazonaws.com`)
5. Click **Save changes**

### Step 7.4: Create Frontend Target Group

1. **Create target group**:
   - **Target type**: `Instances`
   - **Name**: `bmi-frontend-tg`
   - **Protocol**: `HTTP`, Port: `80`
   - **VPC**: Select `devops-vpc`
   - **Health check**:
     - Path: `/health`
     - Interval: `10 seconds`
     - Timeout: `5 seconds`
     - Healthy threshold: `2`
     - Unhealthy threshold: `3`
2. Click **Create target group**

### Step 7.5: Create Frontend ALB (Public)

1. **Create Load Balancer** → **Application Load Balancer**
2. Configure:
   - **Name**: `bmi-frontend-alb`
   - **Scheme**: `Internet-facing`
   - **VPC**: Select `devops-vpc`
   - **Mappings**: Select **both AZs** and **both public subnets**:
     - ap-south-1a: `devops-subnet-public1-ap-south-1a`
     - ap-south-1b: `devops-subnet-public2-ap-south-1b`
   - **Security groups**: Select `frontend-alb-sg`
   - **Listeners**: HTTP (80) → Forward to `bmi-frontend-tg`
3. Click **Create load balancer**
4. Wait ~2 minutes
5. **Copy the DNS name** (this is your application URL!)

---

## Phase 8: Backend EC2 Instances (Manual - Fixed 2 Instances) (10 minutes)

### Step 8.1: Launch Backend Instance 1

1. Go to **EC2** → **Launch instance**
2. Configure:
   - **Name**: `bmi-backend-1`
   - **AMI**: Select `bmi-backend-golden-ami` (from Phase 6.3)
   - **Instance type**: `t3.micro`
   - **Key pair**: Not needed (using SSM)
   - **Network**:
     - VPC: `devops-vpc`
     - Subnet: Select `devops-subnet-private1-ap-south-1a`
     - Auto-assign public IP: `Disable`
   - **Security group**: Select `backend-ec2-sg`
   - **IAM instance profile**: Select `EC2RoleForBMIApp`
   - **Advanced details** → **User data**:

```bash
#!/bin/bash
wget https://raw.githubusercontent.com/sarowar-alam/3-tier-web-app-auto-scalling/main/AutoScaling-FrontEnd-CPU/deploy-backend.sh
chmod +x deploy-backend.sh
./deploy-backend.sh
```

3. Click **Launch instance**

### Step 8.2: Launch Backend Instance 2

1. Repeat above steps with:
   - **Name**: `bmi-backend-2`
   - **Subnet**: Select **second private subnet** (different AZ)
   - Same user data script

### Step 8.3: Register Backend Instances with Target Group

1. Wait ~5-7 minutes for instances to run deployment scripts
2. Go to **Target Groups** → Select `bmi-backend-tg`
3. **Targets** tab → **Register targets**
4. Select both `bmi-backend-1` and `bmi-backend-2`
5. Click **Include as pending below** → **Register pending targets**
6. Wait 2-3 minutes for health checks to pass (status: `healthy`)

---

## Phase 9: Frontend Auto Scaling Group (10 minutes)

### Step 9.1: Create Launch Template

1. Go to **EC2** → **Launch Templates** → **Create launch template**
2. Configure:

**Template name**: `bmi-frontend-lt`
**Description**: `Launch template for frontend auto-scaling`

**AMI**: Select `bmi-frontend-golden-ami`
**Instance type**: `t3.micro`

**Key pair**: Not needed

**Network settings**:
- **Subnet**: Don't include in template
- **Security groups**: Select `frontend-ec2-sg`

**Advanced details**:
- **IAM instance profile**: Select `EC2RoleForBMIApp`
- **Metadata version**: `V2 only (token required)`
- **User data**:

```bash
#!/bin/bash
wget https://raw.githubusercontent.com/sarowar-alam/3-tier-web-app-auto-scalling/main/AutoScaling-FrontEnd-CPU/deploy-frontend.sh
chmod +x deploy-frontend.sh
./deploy-frontend.sh
```

3. Click **Create launch template**

### Step 9.2: Create Auto Scaling Group

1. Go to **EC2** → **Auto Scaling Groups** → **Create Auto Scaling group**
2. **Step 1: Choose launch template**
   - **Name**: `bmi-frontend-asg`
   - **Launch template**: Select `bmi-frontend-lt`
   - Click **Next**

3. **Step 2: Network**
   - **VPC**: Select `devops-vpc`
   - **Availability Zones and subnets**: Select **both private subnets**:
     - `devops-subnet-private1-ap-south-1a`
     - `devops-subnet-private2-ap-south-1b`
   - Click **Next**

4. **Step 3: Load balancing**
   - **Load balancing**: `Attach to an existing load balancer`
   - **Choose target groups**: Select `bmi-frontend-tg`
   - **Health checks**:
     - ELB health check: `Enable`
     - Health check grace period: `300 seconds` (5 minutes)
   - Click **Next**

5. **Step 4: Group size and scaling**
   - **Desired capacity**: `2`
   - **Min**: `1`
   - **Max**: `4`
   - **Scaling policies**: `Target tracking scaling policy`
     - **Policy name**: `cpu-target-tracking`
     - **Metric type**: `Average CPU utilization`
     - **Target value**: `60`
     - **Instances need**: `60` seconds warmup
   - Click **Next**

6. **Step 5: Notifications** - Skip
7. **Step 6: Tags**
   - Add tag: Key=`Name`, Value=`bmi-frontend-asg-instance`
8. Click **Next** → **Create Auto Scaling Group**

### Step 9.3: Verify Frontend Deployment

1. Wait ~5-7 minutes for instances to launch and deploy
2. Go to **Target Groups** → `bmi-frontend-tg` → **Targets** tab
3. Verify 2 instances are `healthy`
4. Go to **Load Balancers** → Copy Frontend ALB DNS name
5. Open in browser: `http://<frontend-alb-dns>.elb.amazonaws.com`
6. You should see the BMI Health Tracker app! 🎉

---

## Phase 10: Load Testing and Monitoring (15 minutes)

### Step 10.1: Setup Load Testing (On Your Local Machine)

1. Install Apache Bench:
   - **macOS**: Pre-installed
   - **Linux**: `sudo yum install httpd-tools` or `sudo apt-get install apache2-utils`
   - **Windows**: Use WSL or download from Apache website

2. Download test scripts:

```bash
wget https://raw.githubusercontent.com/sarowar-alam/3-tier-web-app-auto-scalling/main/AutoScaling-FrontEnd-CPU/load-test/quick-test.sh
chmod +x quick-test.sh

wget https://raw.githubusercontent.com/sarowar-alam/3-tier-web-app-auto-scalling/main/AutoScaling-FrontEnd-CPU/load-test/monitor.sh
chmod +x monitor.sh
```

### Step 10.2: Start Monitoring

Open a **second terminal** and run:

```bash
./monitor.sh bmi-frontend-asg ap-south-1
```

This will show real-time ASG status and instance CPU metrics.

### Step 10.3: Run Load Test

In the **first terminal**:

```bash
./quick-test.sh http://<frontend-alb-dns>.elb.amazonaws.com
```

**What to expect:**
1. **0-2 minutes**: Initial warmup, CPU starts climbing
2. **2-4 minutes**: CPU hits 60%+, ASG triggers scale-out
3. **4-6 minutes**: New instances launch and deploy app
4. **6-8 minutes**: New instances register as healthy, load distributes
5. **After test ends**: Wait 5-7 minutes, ASG scales in (terminates excess instances)

### Step 10.4: Monitor in AWS Console

Open these tabs:

1. **Auto Scaling Group Activity**:
   - EC2 → Auto Scaling Groups → `bmi-frontend-asg` → Activity tab
   - Watch for "Launching a new EC2 instance" messages

2. **CloudWatch Metrics**:
   - CloudWatch → Metrics → EC2 → Per-Instance Metrics
   - Select your instances → CPUUtilization
   - Set refresh to 1 minute

3. **Target Group Health**:
   - EC2 → Target Groups → `bmi-frontend-tg` → Targets tab
   - Watch new instances appear and become healthy

---

## Phase 11: Verification and Testing (5 minutes)

### Verify Auto-Scaling Works:

**Expected Behavior:**
- Start: 2 instances (desired capacity)
- During load: Scales to 3-4 instances
- After cooldown (5-7 min): Scales back to 2 instances

**Check these:**
- [ ] Frontend ALB accessible via browser
- [ ] App loads and displays UI correctly
- [ ] Can submit measurements via form
- [ ] Backend API responding (check Network tab)
- [ ] ASG activity shows scaling events
- [ ] CloudWatch shows CPU spikes
- [ ] Instances scale up during load
- [ ] Instances scale down after load stops

### Test Aurora Auto-Scaling:

1. Go to **RDS** → **Databases** → `bmi-aurora-cluster`
2. Click **Monitoring** tab
3. Check **Serverless Database Capacity** metric
4. During load test, capacity should increase from 0.5 ACU → 1-2 ACU
5. After load stops, scales back down

---

## Troubleshooting

### Frontend not loading?
- Check Target Group health status
- Connect to instance via SSM: `aws ssm start-session --target <instance-id>`
- Check logs: `tail -f /var/log/frontend-deploy.log`
- Verify nginx: `sudo systemctl status nginx`

### Backend API not responding?
- Check backend target group health
- Connect via SSM to backend instance
- Check logs: `tail -f /var/log/backend-deploy.log`
- Check PM2: `pm2 status`
- Check database: `pm2 logs`

### Auto-scaling not triggering?
- Verify scaling policy: ASG → Automatic scaling tab
- Check CloudWatch alarms: CloudWatch → Alarms
- Ensure load test is actually hitting the ALB
- Wait longer - scaling has cooldown periods (60-120 seconds)

### Can't connect via SSM?
- Verify IAM role has `AmazonSSMManagedInstanceCore`
- Check VPC endpoints are created and available
- Ensure security groups allow outbound HTTPS (443)
- Wait 5 minutes after instance launch

---

## Cost Optimization

**During demo:**
- Use t3.micro instances ($0.0104/hour)
- Single NAT Gateway ($0.045/hour)
- Aurora Serverless v2 minimal ACUs

**After demo:**
- **DELETE EVERYTHING** using [TEARDOWN-CHECKLIST.md](TEARDOWN-CHECKLIST.md)
- Most expensive: NAT Gateway and Aurora (even when idle)

---

## Next Steps

1. **Test the application** - Add measurements, view trends
2. **Run load tests** - Trigger auto-scaling multiple times
3. **Monitor metrics** - Watch CloudWatch dashboards
4. **Experiment** - Change scaling thresholds, test different loads
5. **CLEANUP** - Follow [TEARDOWN-CHECKLIST.md](TEARDOWN-CHECKLIST.md) to avoid charges

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└──────────────────────────┬──────────────────────────────────┘
                           │
                  ┌────────▼─────────┐
                  │  Public ALB      │ (Internet-facing)
                  │  Port 80         │
                  └────────┬─────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼────┐        ┌────▼────┐       ┌────▼────┐
   │Frontend │        │Frontend │       │Frontend │
   │EC2      │        │EC2      │       │EC2      │
   │(nginx)  │        │(nginx)  │       │(nginx)  │
   └────┬────┘        └────┬────┘       └────┬────┘
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │ /api proxy
                  ┌────────▼─────────┐
                  │ Internal ALB     │ (private)
                  │ Port 80          │
                  └────────┬─────────┘
                           │
                  ┌────────┼─────────┐
                  │        │         │
             ┌────▼────┐  ┌▼────────┐
             │Backend  │  │Backend  │
             │EC2      │  │EC2      │
             │Node/PM2 │  │Node/PM2 │
             └────┬────┘  └┬────────┘
                  │        │
                  └────┬───┘
                       │
              ┌────────▼────────┐
              │ Aurora          │
              │ Serverless v2   │
              │ PostgreSQL      │
              │ (0.5-2 ACU)     │
              └─────────────────┘
```

---

## Summary

**What You've Built:**
- ✅ 3-tier auto-scaling architecture
- ✅ Frontend ASG with CPU-based scaling (60% target)
- ✅ Backend on fixed EC2 instances (2)
- ✅ Aurora Serverless v2 with auto-scaling compute
- ✅ Multi-AZ high availability
- ✅ Private subnets with SSM access
- ✅ Load testing and monitoring tools

**Total Setup Time:** ~60-75 minutes
**Demo Time:** 15-20 minutes
**Teardown Time:** 20-30 minutes

---

## Support

For issues with this setup:
1. Check [Troubleshooting](#troubleshooting) section
2. Review AWS CloudWatch logs
3. Verify all security group rules
4. Ensure Parameter Store values are correct

**Remember to clean up!** See [TEARDOWN-CHECKLIST.md](TEARDOWN-CHECKLIST.md)

---

**Demo complete! 🎉**

---
## 🧑‍💻 Author
*Md. Sarowar Alam*  
Lead DevOps Engineer, Hogarth Worldwide  
📧 Email: sarowar@hotmail.com  
🔗 LinkedIn: [linkedin.com/in/sarowar](https://www.linkedin.com/in/sarowar/)
---
