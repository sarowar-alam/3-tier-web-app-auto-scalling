# AWS Security Groups + VPC Endpoints + ALBs Creation Script
# Profile: sarowar-ostad
# Region: ap-south-1
# VPC: vpc-06f7dead5c49ece64
# Key Pair: sarowar-ostad-mumbai (for EC2 instance launches)

$PROFILE      = "sarowar-ostad"
$REGION       = "ap-south-1"
$VPC_ID       = "vpc-055b1b2b5a0e18ecc"
$KEY_PAIR     = "sarowar-ostad-mumbai"
$DB_NAME      = "bmidb"
$DB_USER      = "postgres"
$DB_PASSWORD  = ""  # Set here, or leave empty to be prompted at runtime

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Creating Security Groups + VPC Endpoints + ALBs for BMI App" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# ===========================================================
# Helper: Idempotent SSM Parameter creation (skip if exists)
# ===========================================================
function New-SsmParamIfNotExists {
    param(
        [string]$Name,
        [string]$Value,
        [string]$Type,        # String | SecureString
        [string]$Description,
        [string]$Profile,
        [string]$Region
    )
    # Check if parameter already exists
    aws ssm get-parameter --name $Name `
        --profile $Profile --region $Region `
        --output text 2>$null | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [EXISTS] $Name" -ForegroundColor Yellow
        return
    }

    aws ssm put-parameter `
        --name $Name `
        --value $Value `
        --type $Type `
        --description $Description `
        --profile $Profile --region $Region | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Created: $Name ($Type)" -ForegroundColor Green
    } else {
        Write-Host "  [FAILED] Failed to create: $Name" -ForegroundColor Red
        exit 1
    }
}

# ===========================================================
# Helper: Idempotent VPC Endpoint creation
# ===========================================================
function New-VpcEndpointIfNotExists {
    param(
        [string]$Name,
        [string]$ServiceName,
        [string]$VpcId,
        [string[]]$SubnetIds,
        [string]$SgId,
        [string]$Profile,
        [string]$Region
    )
    $existing = aws ec2 describe-vpc-endpoints `
        --filters "Name=service-name,Values=$ServiceName" `
                  "Name=vpc-id,Values=$VpcId" `
                  "Name=vpc-endpoint-state,Values=available,pending" `
        --profile $Profile --region $Region `
        --query 'VpcEndpoints[0].VpcEndpointId' --output text 2>$null

    if ($existing -and $existing -ne "None") {
        Write-Host "[EXISTS] $Name already exists ($existing)" -ForegroundColor Yellow
        return $existing
    }

    $endpointId = aws ec2 create-vpc-endpoint `
        --vpc-id $VpcId `
        --vpc-endpoint-type Interface `
        --service-name $ServiceName `
        --subnet-ids $SubnetIds `
        --security-group-ids $SgId `
        --private-dns-enabled `
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$Name}]" `
        --profile $Profile --region $Region `
        --query 'VpcEndpoint.VpcEndpointId' --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: $Name ($endpointId)" -ForegroundColor Green
        return $endpointId
    } else {
        Write-Host "[FAILED] Failed to create $Name" -ForegroundColor Red
        exit 1
    }
}

# ===========================================================
# Phase 1: Lookup private subnets (needed for VPC endpoints)
# ===========================================================
Write-Host "[SUBNETS] Looking up private subnets in VPC..." -ForegroundColor Yellow

$PRIVATE_SUBNET_1A = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$VPC_ID" `
              "Name=tag:Name,Values=DevOps-subnet-private1-ap-south-1a" `
    --profile $PROFILE --region $REGION `
    --query 'Subnets[0].SubnetId' --output text 2>$null

$PRIVATE_SUBNET_1B = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$VPC_ID" `
              "Name=tag:Name,Values=DevOps-subnet-private2-ap-south-1b" `
    --profile $PROFILE --region $REGION `
    --query 'Subnets[0].SubnetId' --output text 2>$null

if (-not $PRIVATE_SUBNET_1A -or $PRIVATE_SUBNET_1A -eq "None") {
    Write-Host "[FAILED] Could not find devops-subnet-private1-ap-south-1a" -ForegroundColor Red
    exit 1
}
if (-not $PRIVATE_SUBNET_1B -or $PRIVATE_SUBNET_1B -eq "None") {
    Write-Host "[FAILED] Could not find devops-subnet-private2-ap-south-1b" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Private subnet 1a : $PRIVATE_SUBNET_1A" -ForegroundColor Green
Write-Host "[OK] Private subnet 1b : $PRIVATE_SUBNET_1B" -ForegroundColor Green

$PUBLIC_SUBNET_1A = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$VPC_ID" `
              "Name=tag:Name,Values=DevOps-subnet-public1-ap-south-1a" `
    --profile $PROFILE --region $REGION `
    --query 'Subnets[0].SubnetId' --output text 2>$null

$PUBLIC_SUBNET_1B = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$VPC_ID" `
              "Name=tag:Name,Values=DevOps-subnet-public2-ap-south-1b" `
    --profile $PROFILE --region $REGION `
    --query 'Subnets[0].SubnetId' --output text 2>$null

if (-not $PUBLIC_SUBNET_1A -or $PUBLIC_SUBNET_1A -eq "None") {
    Write-Host "[FAILED] Could not find DevOps-subnet-public1-ap-south-1a" -ForegroundColor Red
    exit 1
}
if (-not $PUBLIC_SUBNET_1B -or $PUBLIC_SUBNET_1B -eq "None") {
    Write-Host "[FAILED] Could not find DevOps-subnet-public2-ap-south-1b" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Public  subnet 1a : $PUBLIC_SUBNET_1A" -ForegroundColor Green
Write-Host "[OK] Public  subnet 1b : $PUBLIC_SUBNET_1B" -ForegroundColor Green
Write-Host ""

# ===========================================================
# Phase 2: SSM Endpoint Security Group
# ===========================================================
Write-Host "[EP-SG] Creating SSM Endpoint Security Group (ssm-endpoint-sg)..." -ForegroundColor Yellow

$SSM_ENDPOINT_SG = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=ssm-endpoint-sg" "Name=vpc-id,Values=$VPC_ID" `
    --profile $PROFILE --region $REGION `
    --query 'SecurityGroups[0].GroupId' --output text 2>$null

if ($SSM_ENDPOINT_SG -and $SSM_ENDPOINT_SG -ne "None") {
    Write-Host "[EXISTS] ssm-endpoint-sg already exists ($SSM_ENDPOINT_SG)" -ForegroundColor Yellow
} else {
    $SSM_ENDPOINT_SG = aws ec2 create-security-group `
        --group-name "ssm-endpoint-sg" `
        --description "Security group for SSM VPC Endpoints" `
        --vpc-id $VPC_ID `
        --profile $PROFILE --region $REGION `
        --query 'GroupId' --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: ssm-endpoint-sg ($SSM_ENDPOINT_SG)" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create ssm-endpoint-sg" -ForegroundColor Red
        exit 1
    }
}

$EXISTING_443 = aws ec2 describe-security-groups `
    --group-ids $SSM_ENDPOINT_SG `
    --profile $PROFILE --region $REGION `
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`443`]' --output text 2>$null

if (-not $EXISTING_443) {
    aws ec2 authorize-security-group-ingress `
        --group-id $SSM_ENDPOINT_SG `
        --protocol tcp --port 443 --cidr 10.0.0.0/16 `
        --profile $PROFILE --region $REGION 2>$null | Out-Null
    Write-Host "  [OK] Added HTTPS (443) inbound from 10.0.0.0/16" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Inbound rules already configured" -ForegroundColor Yellow
}
Write-Host ""

# ===========================================================
# Phase 3: VPC Interface Endpoints for SSM
# ===========================================================
$SUBNET_IDS = @($PRIVATE_SUBNET_1A, $PRIVATE_SUBNET_1B)

Write-Host "[EP-1/3] SSM endpoint (com.amazonaws.$REGION.ssm)..." -ForegroundColor Yellow
$EP_SSM = New-VpcEndpointIfNotExists `
    -Name "bmi-ssm-endpoint" `
    -ServiceName "com.amazonaws.$REGION.ssm" `
    -VpcId $VPC_ID -SubnetIds $SUBNET_IDS -SgId $SSM_ENDPOINT_SG `
    -Profile $PROFILE -Region $REGION
Write-Host ""

Write-Host "[EP-2/3] EC2 Messages endpoint (com.amazonaws.$REGION.ec2messages)..." -ForegroundColor Yellow
$EP_EC2MSG = New-VpcEndpointIfNotExists `
    -Name "bmi-ec2messages-endpoint" `
    -ServiceName "com.amazonaws.$REGION.ec2messages" `
    -VpcId $VPC_ID -SubnetIds $SUBNET_IDS -SgId $SSM_ENDPOINT_SG `
    -Profile $PROFILE -Region $REGION
Write-Host ""

Write-Host "[EP-3/3] SSM Messages endpoint (com.amazonaws.$REGION.ssmmessages)..." -ForegroundColor Yellow
$EP_SSMMSG = New-VpcEndpointIfNotExists `
    -Name "bmi-ssmmessages-endpoint" `
    -ServiceName "com.amazonaws.$REGION.ssmmessages" `
    -VpcId $VPC_ID -SubnetIds $SUBNET_IDS -SgId $SSM_ENDPOINT_SG `
    -Profile $PROFILE -Region $REGION
Write-Host ""

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Phase 3 complete. Creating Security Groups..." -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create Frontend ALB Security Group
Write-Host "[1/5] Creating Frontend ALB Security Group..." -ForegroundColor Yellow

# Check if it already exists
$FRONTEND_ALB_SG = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=frontend-alb-sg" "Name=vpc-id,Values=$VPC_ID" `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].GroupId' `
    --output text 2>$null

if ($FRONTEND_ALB_SG -and $FRONTEND_ALB_SG -ne "None") {
    Write-Host "[EXISTS] frontend-alb-sg already exists ($FRONTEND_ALB_SG)" -ForegroundColor Yellow
    Write-Host "  Skipping creation, will use existing security group..." -ForegroundColor Yellow
} else {
    # Create new security group
    $FRONTEND_ALB_SG = aws ec2 create-security-group `
        --group-name "frontend-alb-sg" `
        --description "Security group for Frontend ALB" `
        --vpc-id $VPC_ID `
        --profile $PROFILE `
        --region $REGION `
        --query 'GroupId' `
        --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: frontend-alb-sg ($FRONTEND_ALB_SG)" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create frontend-alb-sg" -ForegroundColor Red
        exit 1
    }
}

# Add rules only if they don't exist
$EXISTING_RULES = aws ec2 describe-security-groups `
    --group-ids $FRONTEND_ALB_SG `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]' `
    --output text 2>$null

if (-not $EXISTING_RULES) {
    
    # Add inbound rules for Frontend ALB - HTTP
    aws ec2 authorize-security-group-ingress `
        --group-id $FRONTEND_ALB_SG `
        --protocol tcp `
        --port 80 `
        --cidr 0.0.0.0/0 `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null
    
    Write-Host "  [OK] Added HTTP (80) from 0.0.0.0/0" -ForegroundColor Green
    
    # Add HTTPS rule
    aws ec2 authorize-security-group-ingress `
        --group-id $FRONTEND_ALB_SG `
        --protocol tcp `
        --port 443 `
        --cidr 0.0.0.0/0 `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null
    
    Write-Host "  [OK] Added HTTPS (443) from 0.0.0.0/0" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Rules already configured" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Create Frontend EC2 Security Group
Write-Host "[2/5] Creating Frontend EC2 Security Group..." -ForegroundColor Yellow

# Check if it already exists
$FRONTEND_EC2_SG = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=frontend-ec2-sg" "Name=vpc-id,Values=$VPC_ID" `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].GroupId' `
    --output text 2>$null

if ($FRONTEND_EC2_SG -and $FRONTEND_EC2_SG -ne "None") {
    Write-Host "[EXISTS] frontend-ec2-sg already exists ($FRONTEND_EC2_SG)" -ForegroundColor Yellow
    Write-Host "  Skipping creation, will use existing security group..." -ForegroundColor Yellow
} else {
    # Create new security group
    $FRONTEND_EC2_SG = aws ec2 create-security-group `
        --group-name "frontend-ec2-sg" `
        --description "Security group for Frontend EC2 instances" `
        --vpc-id $VPC_ID `
        --profile $PROFILE `
        --region $REGION `
        --query 'GroupId' `
        --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: frontend-ec2-sg ($FRONTEND_EC2_SG)" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create frontend-ec2-sg" -ForegroundColor Red
        exit 1
    }
}

# Add rules only if they don't exist
$EXISTING_RULES = aws ec2 describe-security-groups `
    --group-ids $FRONTEND_EC2_SG `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]' `
    --output text 2>$null

if (-not $EXISTING_RULES) {
    
    # Add inbound rules for Frontend EC2 - HTTP from ALB
    aws ec2 authorize-security-group-ingress `
        --group-id $FRONTEND_EC2_SG `
        --protocol tcp `
        --port 80 `
        --source-group $FRONTEND_ALB_SG `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null
    
    Write-Host "  [OK] Added HTTP (80) from frontend-alb-sg" -ForegroundColor Green
    
    # Add HTTPS from VPC CIDR
    aws ec2 authorize-security-group-ingress `
        --group-id $FRONTEND_EC2_SG `
        --protocol tcp `
        --port 443 `
        --cidr 10.0.0.0/16 `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null
    
    Write-Host "  [OK] Added HTTPS (443) from 10.0.0.0/16" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Rules already configured" -ForegroundColor Yellow
}
Write-Host ""

# Step 3: Create Backend ALB Security Group
Write-Host "[3/5] Creating Backend ALB Security Group..." -ForegroundColor Yellow

# Check if it already exists
$BACKEND_ALB_SG = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=backend-alb-sg" "Name=vpc-id,Values=$VPC_ID" `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].GroupId' `
    --output text 2>$null

if ($BACKEND_ALB_SG -and $BACKEND_ALB_SG -ne "None") {
    Write-Host "[EXISTS] backend-alb-sg already exists ($BACKEND_ALB_SG)" -ForegroundColor Yellow
    Write-Host "  Skipping creation, will use existing security group..." -ForegroundColor Yellow
} else {
    # Create new security group
    $BACKEND_ALB_SG = aws ec2 create-security-group `
        --group-name "backend-alb-sg" `
        --description "Security group for Backend Internal ALB" `
        --vpc-id $VPC_ID `
        --profile $PROFILE `
        --region $REGION `
        --query 'GroupId' `
        --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: backend-alb-sg ($BACKEND_ALB_SG)" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create backend-alb-sg" -ForegroundColor Red
        exit 1
    }
}

# Add rules only if they don't exist
$EXISTING_RULES = aws ec2 describe-security-groups `
    --group-ids $BACKEND_ALB_SG `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]' `
    --output text 2>$null

if (-not $EXISTING_RULES) {
    
    # Add inbound rules for Backend ALB from Frontend EC2
    aws ec2 authorize-security-group-ingress `
        --group-id $BACKEND_ALB_SG `
        --protocol tcp `
        --port 80 `
        --source-group $FRONTEND_EC2_SG `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null
    
    Write-Host "  [OK] Added HTTP (80) from frontend-ec2-sg" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Rules already configured" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Create Backend EC2 Security Group
Write-Host "[4/5] Creating Backend EC2 Security Group..." -ForegroundColor Yellow

# Check if it already exists
$BACKEND_EC2_SG = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=backend-ec2-sg" "Name=vpc-id,Values=$VPC_ID" `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].GroupId' `
    --output text 2>$null

if ($BACKEND_EC2_SG -and $BACKEND_EC2_SG -ne "None") {
    Write-Host "[EXISTS] backend-ec2-sg already exists ($BACKEND_EC2_SG)" -ForegroundColor Yellow
    Write-Host "  Skipping creation, will use existing security group..." -ForegroundColor Yellow
} else {
    # Create new security group
    $BACKEND_EC2_SG = aws ec2 create-security-group `
        --group-name "backend-ec2-sg" `
        --description "Security group for Backend EC2 instances" `
        --vpc-id $VPC_ID `
        --profile $PROFILE `
        --region $REGION `
        --query 'GroupId' `
        --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: backend-ec2-sg ($BACKEND_EC2_SG)" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create backend-ec2-sg" -ForegroundColor Red
        exit 1
    }
}

# Add rules only if they don't exist
$EXISTING_RULES = aws ec2 describe-security-groups `
    --group-ids $BACKEND_EC2_SG `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`3000`]' `
    --output text 2>$null

if (-not $EXISTING_RULES) {
    
    # Add inbound rules for Backend EC2 from Backend ALB
    aws ec2 authorize-security-group-ingress `
        --group-id $BACKEND_EC2_SG `
        --protocol tcp `
        --port 3000 `
        --source-group $BACKEND_ALB_SG `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null
    
    Write-Host "  [OK] Added TCP (3000) from backend-alb-sg" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] Rules already configured" -ForegroundColor Yellow
}
Write-Host ""

# Step 5: Create or Update Aurora Security Group
Write-Host "[5/5] Creating Aurora Security Group (aurora-sg)..." -ForegroundColor Yellow
$AURORA_SG = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=aurora-sg" "Name=vpc-id,Values=$VPC_ID" `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].GroupId' `
    --output text 2>$null

if ($AURORA_SG -and $AURORA_SG -ne "None") {
    Write-Host "[EXISTS] aurora-sg already exists ($AURORA_SG)" -ForegroundColor Yellow
} else {
    $AURORA_SG = aws ec2 create-security-group `
        --group-name "aurora-sg" `
        --description "Security group for Aurora PostgreSQL cluster" `
        --vpc-id $VPC_ID `
        --profile $PROFILE `
        --region $REGION `
        --query 'GroupId' `
        --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: aurora-sg ($AURORA_SG)" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create aurora-sg" -ForegroundColor Red
        exit 1
    }
}

# Check if the correct rule already exists (port 5432 from VPC CIDR)
$EXISTING_RULES = aws ec2 describe-security-groups `
    --group-ids $AURORA_SG `
    --profile $PROFILE `
    --region $REGION `
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]' `
    --output text 2>$null

if (-not $EXISTING_RULES) {
    # Remove any stale inbound rules before adding the correct one
    $ALL_RULES = aws ec2 describe-security-groups `
        --group-ids $AURORA_SG `
        --profile $PROFILE `
        --region $REGION `
        --query 'SecurityGroups[0].IpPermissions' `
        --output json | ConvertFrom-Json

    if ($ALL_RULES.Count -gt 0) {
        Write-Host "  Removing stale inbound rules..." -ForegroundColor Yellow
        foreach ($rule in $ALL_RULES) {
            aws ec2 revoke-security-group-ingress `
                --group-id $AURORA_SG `
                --ip-permissions (ConvertTo-Json -Depth 10 @($rule) -Compress) `
                --profile $PROFILE `
                --region $REGION 2>$null | Out-Null
        }
        Write-Host "  [OK] Removed stale rules" -ForegroundColor Green
    }

    aws ec2 authorize-security-group-ingress `
        --group-id $AURORA_SG `
        --protocol tcp `
        --port 5432 `
        --cidr 10.0.0.0/16 `
        --profile $PROFILE `
        --region $REGION 2>$null | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Added PostgreSQL (5432) from 10.0.0.0/16 (entire VPC)" -ForegroundColor Green
    } else {
        Write-Host "  [FAILED] Failed to add PostgreSQL rule" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [EXISTS] Rules already configured" -ForegroundColor Yellow
}
Write-Host ""
# ===========================================================
# Phase 4: SSM Parameter Store
# ===========================================================
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Phase 4: Creating SSM Parameter Store entries..." -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for password if not set
if (-not $DB_PASSWORD) {
    $DB_PASSWORD = Read-Host "Enter database password for /bmi-app/db-password"
}
if (-not $DB_PASSWORD) {
    Write-Host "[FAILED] DB password cannot be empty" -ForegroundColor Red
    exit 1
}

# Try to resolve Aurora writer endpoint dynamically
$AURORA_CLUSTER = "bmi-aurora-cluster"
$DB_HOST = aws rds describe-db-clusters `
    --db-cluster-identifier $AURORA_CLUSTER `
    --profile $PROFILE --region $REGION `
    --query 'DBClusters[0].Endpoint' --output text 2>$null

if (-not $DB_HOST -or $DB_HOST -eq "None") {
    $DB_HOST = "placeholder-update-after-aurora-creation"
    Write-Host "[WARN] Aurora cluster not found yet - using placeholder for /bmi-app/db-host" -ForegroundColor Yellow
    Write-Host "       Re-run this script after creating the Aurora cluster to update it." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Resolved Aurora endpoint: $DB_HOST" -ForegroundColor Green
}
Write-Host ""

Write-Host "[PARAM-1/5] /bmi-app/db-host" -ForegroundColor Yellow
New-SsmParamIfNotExists `
    -Name "/bmi-app/db-host" -Value $DB_HOST -Type "String" `
    -Description "Aurora cluster writer endpoint" `
    -Profile $PROFILE -Region $REGION

Write-Host "[PARAM-2/5] /bmi-app/db-name" -ForegroundColor Yellow
New-SsmParamIfNotExists `
    -Name "/bmi-app/db-name" -Value $DB_NAME -Type "String" `
    -Description "Aurora database name" `
    -Profile $PROFILE -Region $REGION

Write-Host "[PARAM-3/5] /bmi-app/db-user" -ForegroundColor Yellow
New-SsmParamIfNotExists `
    -Name "/bmi-app/db-user" -Value $DB_USER -Type "String" `
    -Description "Aurora database user" `
    -Profile $PROFILE -Region $REGION

Write-Host "[PARAM-4/5] /bmi-app/db-password" -ForegroundColor Yellow
New-SsmParamIfNotExists `
    -Name "/bmi-app/db-password" -Value $DB_PASSWORD -Type "SecureString" `
    -Description "Aurora database password" `
    -Profile $PROFILE -Region $REGION

Write-Host "[PARAM-5/5] /bmi-app/backend-alb-url" -ForegroundColor Yellow
New-SsmParamIfNotExists `
    -Name "/bmi-app/backend-alb-url" -Value "http://placeholder" -Type "String" `
    -Description "Internal ALB URL for backend (update after ALB creation)" `
    -Profile $PROFILE -Region $REGION

Write-Host ""# ===========================================================
# Phase 7: Application Load Balancers
# ===========================================================
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Phase 7: Creating Target Groups and ALBs..." -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 7.1: Backend Target Group ---
Write-Host "[TG-1/2] Backend target group (bmi-backend-tg, port 3000)..." -ForegroundColor Yellow

$BACKEND_TG_ARN = aws elbv2 describe-target-groups `
    --names "bmi-backend-tg" `
    --profile $PROFILE --region $REGION `
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>$null

if ($BACKEND_TG_ARN -and $BACKEND_TG_ARN -ne "None") {
    Write-Host "[EXISTS] bmi-backend-tg already exists" -ForegroundColor Yellow
} else {
    $BACKEND_TG_ARN = aws elbv2 create-target-group `
        --name "bmi-backend-tg" `
        --protocol HTTP `
        --port 3000 `
        --vpc-id $VPC_ID `
        --target-type instance `
        --health-check-protocol HTTP `
        --health-check-path "/health" `
        --health-check-interval-seconds 10 `
        --health-check-timeout-seconds 5 `
        --healthy-threshold-count 2 `
        --unhealthy-threshold-count 3 `
        --profile $PROFILE --region $REGION `
        --query 'TargetGroups[0].TargetGroupArn' --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: bmi-backend-tg" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create bmi-backend-tg" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# --- Step 7.2: Backend ALB (Internal) ---
Write-Host "[ALB-1/2] Backend ALB (bmi-backend-alb, internal)..." -ForegroundColor Yellow

$BACKEND_ALB_DNS = ""
$BACKEND_ALB_ARN = aws elbv2 describe-load-balancers `
    --names "bmi-backend-alb" `
    --profile $PROFILE --region $REGION `
    --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>$null

if ($BACKEND_ALB_ARN -and $BACKEND_ALB_ARN -ne "None") {
    Write-Host "[EXISTS] bmi-backend-alb already exists" -ForegroundColor Yellow
    $BACKEND_ALB_DNS = aws elbv2 describe-load-balancers `
        --names "bmi-backend-alb" `
        --profile $PROFILE --region $REGION `
        --query 'LoadBalancers[0].DNSName' --output text
} else {
    $BACKEND_ALB_ARN = aws elbv2 create-load-balancer `
        --name "bmi-backend-alb" `
        --scheme internal `
        --ip-address-type ipv4 `
        --subnets $PRIVATE_SUBNET_1A $PRIVATE_SUBNET_1B `
        --security-groups $BACKEND_ALB_SG `
        --profile $PROFILE --region $REGION `
        --query 'LoadBalancers[0].LoadBalancerArn' --output text

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAILED] Failed to create bmi-backend-alb" -ForegroundColor Red
        exit 1
    }
    $BACKEND_ALB_DNS = aws elbv2 describe-load-balancers `
        --load-balancer-arns $BACKEND_ALB_ARN `
        --profile $PROFILE --region $REGION `
        --query 'LoadBalancers[0].DNSName' --output text
    Write-Host "[OK] Created: bmi-backend-alb" -ForegroundColor Green
}
Write-Host "  DNS: $BACKEND_ALB_DNS" -ForegroundColor Cyan

# Attach HTTP:80 listener if not already present
$BACKEND_LISTENERS = aws elbv2 describe-listeners `
    --load-balancer-arn $BACKEND_ALB_ARN `
    --profile $PROFILE --region $REGION `
    --query 'Listeners[?Port==`80`].ListenerArn' --output text 2>$null

if (-not $BACKEND_LISTENERS) {
    aws elbv2 create-listener `
        --load-balancer-arn $BACKEND_ALB_ARN `
        --protocol HTTP --port 80 `
        --default-actions "Type=forward,TargetGroupArn=$BACKEND_TG_ARN" `
        --profile $PROFILE --region $REGION | Out-Null
    Write-Host "  [OK] Added HTTP:80 listener -> bmi-backend-tg" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] HTTP:80 listener already configured" -ForegroundColor Yellow
}
Write-Host ""

# --- Step 7.3: Update SSM /bmi-app/backend-alb-url ---
Write-Host "[SSM] Updating /bmi-app/backend-alb-url..." -ForegroundColor Yellow
aws ssm put-parameter `
    --name "/bmi-app/backend-alb-url" `
    --value "http://$BACKEND_ALB_DNS" `
    --type String `
    --overwrite `
    --profile $PROFILE --region $REGION | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] /bmi-app/backend-alb-url = http://$BACKEND_ALB_DNS" -ForegroundColor Green
} else {
    Write-Host "[FAILED] Failed to update /bmi-app/backend-alb-url" -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Step 7.4: Frontend Target Group ---
Write-Host "[TG-2/2] Frontend target group (bmi-frontend-tg, port 80)..." -ForegroundColor Yellow

$FRONTEND_TG_ARN = aws elbv2 describe-target-groups `
    --names "bmi-frontend-tg" `
    --profile $PROFILE --region $REGION `
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>$null

if ($FRONTEND_TG_ARN -and $FRONTEND_TG_ARN -ne "None") {
    Write-Host "[EXISTS] bmi-frontend-tg already exists" -ForegroundColor Yellow
} else {
    $FRONTEND_TG_ARN = aws elbv2 create-target-group `
        --name "bmi-frontend-tg" `
        --protocol HTTP `
        --port 80 `
        --vpc-id $VPC_ID `
        --target-type instance `
        --health-check-protocol HTTP `
        --health-check-path "/health" `
        --health-check-interval-seconds 10 `
        --health-check-timeout-seconds 5 `
        --healthy-threshold-count 2 `
        --unhealthy-threshold-count 3 `
        --profile $PROFILE --region $REGION `
        --query 'TargetGroups[0].TargetGroupArn' --output text

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Created: bmi-frontend-tg" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Failed to create bmi-frontend-tg" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# --- Step 7.5: Frontend ALB (Internet-Facing) ---
Write-Host "[ALB-2/2] Frontend ALB (bmi-frontend-alb, internet-facing)..." -ForegroundColor Yellow

$FRONTEND_ALB_DNS = ""
$FRONTEND_ALB_ARN = aws elbv2 describe-load-balancers `
    --names "bmi-frontend-alb" `
    --profile $PROFILE --region $REGION `
    --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>$null

if ($FRONTEND_ALB_ARN -and $FRONTEND_ALB_ARN -ne "None") {
    Write-Host "[EXISTS] bmi-frontend-alb already exists" -ForegroundColor Yellow
    $FRONTEND_ALB_DNS = aws elbv2 describe-load-balancers `
        --names "bmi-frontend-alb" `
        --profile $PROFILE --region $REGION `
        --query 'LoadBalancers[0].DNSName' --output text
} else {
    $FRONTEND_ALB_ARN = aws elbv2 create-load-balancer `
        --name "bmi-frontend-alb" `
        --scheme internet-facing `
        --ip-address-type ipv4 `
        --subnets $PUBLIC_SUBNET_1A $PUBLIC_SUBNET_1B `
        --security-groups $FRONTEND_ALB_SG `
        --profile $PROFILE --region $REGION `
        --query 'LoadBalancers[0].LoadBalancerArn' --output text

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAILED] Failed to create bmi-frontend-alb" -ForegroundColor Red
        exit 1
    }
    $FRONTEND_ALB_DNS = aws elbv2 describe-load-balancers `
        --load-balancer-arns $FRONTEND_ALB_ARN `
        --profile $PROFILE --region $REGION `
        --query 'LoadBalancers[0].DNSName' --output text
    Write-Host "[OK] Created: bmi-frontend-alb" -ForegroundColor Green
}
Write-Host "  DNS: $FRONTEND_ALB_DNS" -ForegroundColor Cyan

# Attach HTTP:80 listener if not already present
$FRONTEND_LISTENERS = aws elbv2 describe-listeners `
    --load-balancer-arn $FRONTEND_ALB_ARN `
    --profile $PROFILE --region $REGION `
    --query 'Listeners[?Port==`80`].ListenerArn' --output text 2>$null

if (-not $FRONTEND_LISTENERS) {
    aws elbv2 create-listener `
        --load-balancer-arn $FRONTEND_ALB_ARN `
        --protocol HTTP --port 80 `
        --default-actions "Type=forward,TargetGroupArn=$FRONTEND_TG_ARN" `
        --profile $PROFILE --region $REGION | Out-Null
    Write-Host "  [OK] Added HTTP:80 listener -> bmi-frontend-tg" -ForegroundColor Green
} else {
    Write-Host "  [EXISTS] HTTP:80 listener already configured" -ForegroundColor Yellow
}
Write-Host ""
# Summary
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] All Resources Created Successfully!" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "VPC Endpoints:" -ForegroundColor White
Write-Host "  ssm-endpoint-sg        : $SSM_ENDPOINT_SG" -ForegroundColor White
Write-Host "  bmi-ssm-endpoint       : $EP_SSM" -ForegroundColor White
Write-Host "  bmi-ec2messages-endpoint: $EP_EC2MSG" -ForegroundColor White
Write-Host "  bmi-ssmmessages-endpoint: $EP_SSMMSG" -ForegroundColor White
Write-Host ""
Write-Host "Security Groups:" -ForegroundColor White
Write-Host "  1. frontend-alb-sg    : $FRONTEND_ALB_SG" -ForegroundColor White
Write-Host "  2. frontend-ec2-sg    : $FRONTEND_EC2_SG" -ForegroundColor White
Write-Host "  3. backend-alb-sg     : $BACKEND_ALB_SG" -ForegroundColor White
Write-Host "  4. backend-ec2-sg     : $BACKEND_EC2_SG" -ForegroundColor White
Write-Host "  5. aurora-sg          : $AURORA_SG" -ForegroundColor White
Write-Host ""
Write-Host "SSM Parameters:" -ForegroundColor White
Write-Host "  /bmi-app/db-host        : $DB_HOST" -ForegroundColor White
Write-Host "  /bmi-app/db-name        : $DB_NAME" -ForegroundColor White
Write-Host "  /bmi-app/db-user        : $DB_USER" -ForegroundColor White
Write-Host "  /bmi-app/db-password    : (SecureString - not shown)" -ForegroundColor White
Write-Host "  /bmi-app/backend-alb-url: http://$BACKEND_ALB_DNS" -ForegroundColor White
Write-Host ""
Write-Host "Load Balancers:" -ForegroundColor White
Write-Host "  bmi-backend-alb (internal)      : $BACKEND_ALB_DNS" -ForegroundColor White
Write-Host "  bmi-frontend-alb (internet-facing): $FRONTEND_ALB_DNS" -ForegroundColor White
Write-Host ""
Write-Host "Target Groups:" -ForegroundColor White
Write-Host "  bmi-backend-tg  : $BACKEND_TG_ARN" -ForegroundColor White
Write-Host "  bmi-frontend-tg : $FRONTEND_TG_ARN" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  - Phase 3 : Create IAM role EC2RoleForBMIApp" -ForegroundColor White
Write-Host "  - Phase 6 : Build Golden AMIs (backend + frontend)" -ForegroundColor White
Write-Host "  - Phase 8 : Launch 2 backend EC2s and register to bmi-backend-tg" -ForegroundColor White
Write-Host "  - Phase 9 : Create frontend Launch Template + ASG targeting bmi-frontend-tg" -ForegroundColor White
Write-Host ""
Write-Host "Application URL (once instances are healthy):" -ForegroundColor Cyan
Write-Host "  http://$FRONTEND_ALB_DNS" -ForegroundColor Green
Write-Host ""
