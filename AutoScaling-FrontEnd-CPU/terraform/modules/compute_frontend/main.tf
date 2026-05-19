# User data script for frontend deployment
locals {
  frontend_userdata = base64encode(<<-EOT
    #!/bin/bash
    wget ${var.github_repo_url}/raw/main/AutoScaling-FrontEnd-CPU/deploy-frontend.sh
    chmod +x deploy-frontend.sh
    ./deploy-frontend.sh
  EOT
  )
}

# Launch Template for Frontend ASG
resource "aws_launch_template" "frontend" {
  name_prefix   = "${var.project_name}-frontend-"
  description   = "Launch template for frontend auto-scaling"
  image_id      = var.ami_id
  instance_type = var.instance_type
  
  iam_instance_profile {
    name = var.iam_instance_profile
  }
  
  vpc_security_group_ids = [var.security_group_id]
  
  user_data = local.frontend_userdata

  metadata_options{
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  
  block_device_mappings {
    device_name = "/dev/xvda"
    
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      delete_on_termination = true
      encrypted             = true
    }
  }
  
  tag_specifications {
    resource_type = "instance"
    
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-frontend-asg-instance"
      }
    )
  }
  
  tag_specifications {
    resource_type = "volume"
    
    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-frontend-asg-volume"
      }
    )
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for Frontend
resource "aws_autoscaling_group" "frontend" {
  name_prefix         = "${var.project_name}-frontend-asg-"
  vpc_zone_identifier = var.subnet_ids
  
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  
  target_group_arns = [var.target_group_arn]
  
  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }
  
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
  
  default_instance_warmup = var.warmup_time
  
  tag {
    key                 = "Name"
    value               = "${var.project_name}-frontend-asg"
    propagate_at_launch = false
  }
  
  dynamic "tag" {
    for_each = var.tags
    
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Target Tracking Scaling Policy - CPU Utilization
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    
    target_value = var.cpu_target
  }
}
