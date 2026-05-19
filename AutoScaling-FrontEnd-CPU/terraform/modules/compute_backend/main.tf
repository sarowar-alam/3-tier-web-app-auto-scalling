# User data script for backend deployment
locals {
  backend_userdata = base64encode(<<-EOT
    #!/bin/bash
    wget ${var.github_repo_url}/raw/main/AutoScaling-FrontEnd-CPU/deploy-backend.sh
    chmod +x deploy-backend.sh
    ./deploy-backend.sh
  EOT
  )
}

# Backend EC2 Instances
resource "aws_instance" "backend" {
  count = var.instance_count
  
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.iam_instance_profile
  
  user_data = local.backend_userdata

  metadata_options{
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }
  
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-backend-${count.index + 1}"
    }
  )
  
  lifecycle {
    ignore_changes = [ami]
  }
}

# Register instances with target group
resource "aws_lb_target_group_attachment" "backend" {
  count = var.instance_count
  
  target_group_arn = var.target_group_arn
  target_id        = aws_instance.backend[count.index].id
  port             = 3000
}
