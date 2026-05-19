#!/bin/bash
# Frontend Golden AMI Preparation Script
# This script installs all prerequisites for the React frontend with nginx
# Run this once to create the Golden AMI

set -euo pipefail

echo "========================================="
echo "Frontend Golden AMI Setup - Prerequisites"
echo "========================================="

# Update system
echo "Updating system packages..."
sudo dnf update -y

# Install nginx
echo "Installing nginx..."
sudo dnf install -y nginx

# Install Node.js 20 (needed for building React app)
echo "Installing Node.js 20..."
sudo dnf install -y nodejs npm

# Verify installations
node --version
npm --version
nginx -v

# Install git
echo "Installing git..."
sudo dnf install -y git

# Create web directory
echo "Creating web directory..."
sudo mkdir -p /var/www
sudo chown ec2-user:ec2-user /var/www

# Start and enable nginx
echo "Starting nginx..."
sudo systemctl enable nginx
sudo systemctl start nginx

# Install CloudWatch agent (optional but recommended)
echo "Installing CloudWatch agent..."
sudo dnf install -y amazon-cloudwatch-agent

echo "========================================="
echo "Frontend Golden AMI Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Create AMI from this instance"
echo "2. Use deploy-frontend.sh as user-data when launching from this AMI"
