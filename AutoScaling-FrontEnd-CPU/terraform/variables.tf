variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "bmi"
}

# Existing VPC Infrastructure IDs
variable "vpc_id" {
  description = "ID of existing VPC"
  type        = string
}

variable "public_subnet_1a_id" {
  description = "ID of existing public subnet in AZ 1a"
  type        = string
}

variable "public_subnet_1b_id" {
  description = "ID of existing public subnet in AZ 1b"
  type        = string
}

variable "private_subnet_1a_id" {
  description = "ID of existing private subnet in AZ 1a"
  type        = string
}

variable "private_subnet_1b_id" {
  description = "ID of existing private subnet in AZ 1b"
  type        = string
}

# Golden AMI IDs (Pre-built by instructor)
variable "backend_ami_id" {
  description = "Golden AMI ID for backend EC2 instances"
  type        = string
  default     = "ami-032e8cf6d0d558851"
}

variable "frontend_ami_id" {
  description = "Golden AMI ID for frontend EC2 instances"
  type        = string
  default     = "ami-0dab0b890a96c6f37"
}

# Database Configuration
variable "db_name" {
  description = "Aurora database name"
  type        = string
  default     = "bmidb"
}

variable "db_username" {
  description = "Aurora master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Aurora master password"
  type        = string
  sensitive   = true
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 2
}

variable "aurora_deletion_protection" {
  description = "Enable deletion protection on Aurora cluster (set true for production)"
  type        = bool
  default     = false
}

# Instance Configuration
variable "backend_instance_type" {
  description = "EC2 instance type for backend"
  type        = string
  default     = "t3.micro"
}

variable "frontend_instance_type" {
  description = "EC2 instance type for frontend ASG"
  type        = string
  default     = "t3.micro"
}

variable "backend_instance_count" {
  description = "Number of backend EC2 instances (fixed)"
  type        = number
  default     = 2
}

# Auto Scaling Configuration
variable "frontend_asg_min_size" {
  description = "Minimum number of frontend instances"
  type        = number
  default     = 1
}

variable "frontend_asg_max_size" {
  description = "Maximum number of frontend instances"
  type        = number
  default     = 4
}

variable "frontend_asg_desired_capacity" {
  description = "Desired number of frontend instances"
  type        = number
  default     = 2
}

variable "frontend_cpu_target" {
  description = "Target CPU utilization percentage for frontend ASG"
  type        = number
  default     = 60
}

variable "frontend_warmup_time" {
  description = "Frontend instance warmup time in seconds"
  type        = number
  default     = 60
}

variable "frontend_health_check_grace_period" {
  description = "Health check grace period for frontend ASG in seconds"
  type        = number
  default     = 300
}

# Deployment Scripts Repository
variable "github_repo_url" {
  description = "GitHub repository URL for deployment scripts"
  type        = string
  default     = "https://github.com/sarowar-alam/3-tier-web-app-auto-scalling.git"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
