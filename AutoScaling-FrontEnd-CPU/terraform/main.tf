# BMI Auto-Scaling Application - Main Orchestration

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = merge(
    var.additional_tags,
    {
      Application = "BMI Health Tracker"
      Environment = var.environment
      Terraform   = "true"
    }
  )
}

# Network Module - VPC Endpoints and Security Groups
module "network" {
  source = "./modules/network"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = data.aws_vpc.devops.id
  vpc_cidr     = data.aws_vpc.devops.cidr_block
  
  private_subnet_ids = [
    data.aws_subnet.private_1a.id,
    data.aws_subnet.private_1b.id
  ]
  
  public_subnet_ids = [
    data.aws_subnet.public_1a.id,
    data.aws_subnet.public_1b.id
  ]
  
  tags = local.common_tags
}

# IAM Module - Roles and Policies
module "iam" {
  source = "./modules/iam"
  
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id
  
  tags = local.common_tags
}

# Database Module - Aurora Serverless v2
module "database" {
  source = "./modules/database"
  
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = data.aws_vpc.devops.id
  private_subnet_ids = [
    data.aws_subnet.private_1a.id,
    data.aws_subnet.private_1b.id
  ]
  
  database_name   = var.db_name
  master_username = var.db_username
  master_password = var.db_password
  
  min_capacity = var.aurora_min_capacity
  max_capacity = var.aurora_max_capacity

  deletion_protection = var.aurora_deletion_protection

  allowed_security_group_id = module.network.backend_ec2_sg_id
  
  tags = local.common_tags
  
  depends_on = [module.network]
}

# Load Balancing Module - ALBs and Target Groups
module "load_balancing" {
  source = "./modules/load_balancing"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = data.aws_vpc.devops.id
  
  public_subnet_ids = [
    data.aws_subnet.public_1a.id,
    data.aws_subnet.public_1b.id
  ]
  
  private_subnet_ids = [
    data.aws_subnet.private_1a.id,
    data.aws_subnet.private_1b.id
  ]
  
  frontend_alb_sg_id = module.network.frontend_alb_sg_id
  backend_alb_sg_id  = module.network.backend_alb_sg_id
  
  tags = local.common_tags
  
  depends_on = [module.network]
}

# Parameter Store Module - SSM Parameters
module "parameter_store" {
  source = "./modules/parameter_store"
  
  project_name = var.project_name
  
  db_host         = module.database.cluster_endpoint
  db_name         = var.db_name
  db_user         = var.db_username
  db_password     = var.db_password
  backend_alb_url = "http://${module.load_balancing.backend_alb_dns}"
  
  tags = local.common_tags
  
  depends_on = [module.database, module.load_balancing]
}

# Backend Compute Module - Fixed EC2 Instances
module "compute_backend" {
  source = "./modules/compute_backend"
  
  project_name   = var.project_name
  environment    = var.environment
  instance_count = var.backend_instance_count
  ami_id         = var.backend_ami_id
  instance_type  = var.backend_instance_type
  
  subnet_ids = [
    data.aws_subnet.private_1a.id,
    data.aws_subnet.private_1b.id
  ]
  
  security_group_id    = module.network.backend_ec2_sg_id
  iam_instance_profile = module.iam.ec2_instance_profile_name
  target_group_arn     = module.load_balancing.backend_tg_arn
  
  github_repo_url = var.github_repo_url
  
  tags = local.common_tags
  
  depends_on = [
    module.network,
    module.iam,
    module.parameter_store,
    module.load_balancing
  ]
}

# Frontend Compute Module - Auto Scaling Group
module "compute_frontend" {
  source = "./modules/compute_frontend"
  
  project_name  = var.project_name
  environment   = var.environment
  ami_id        = var.frontend_ami_id
  instance_type = var.frontend_instance_type
  
  subnet_ids = [
    data.aws_subnet.private_1a.id,
    data.aws_subnet.private_1b.id
  ]
  
  security_group_id    = module.network.frontend_ec2_sg_id
  iam_instance_profile = module.iam.ec2_instance_profile_name
  target_group_arn     = module.load_balancing.frontend_tg_arn
  
  min_size                  = var.frontend_asg_min_size
  max_size                  = var.frontend_asg_max_size
  desired_capacity          = var.frontend_asg_desired_capacity
  cpu_target                = var.frontend_cpu_target
  warmup_time               = var.frontend_warmup_time
  health_check_grace_period = var.frontend_health_check_grace_period
  
  github_repo_url = var.github_repo_url
  
  tags = local.common_tags
  
  depends_on = [
    module.network,
    module.iam,
    module.parameter_store,
    module.load_balancing,
    module.compute_backend
  ]
}
