#!/bin/bash
# Backend Golden AMI Preparation Script
# This script installs all prerequisites for the Node.js backend
# Run this once to create the Golden AMI

set -euo pipefail

echo "========================================="
echo "Backend Golden AMI Setup - Prerequisites"
echo "========================================="

# Update system
echo "Updating system packages..."
sudo dnf update -y

# Install Node.js 20 from NodeSource (ensures v20.x)
echo "Installing Node.js 20 from NodeSource..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs

# Verify Node.js installation (should be v20.x)
echo "Node.js version:"
node --version
echo "NPM version:"
npm --version

# Install PM2 globally
echo "Installing PM2 globally..."
sudo npm install -g pm2

# Verify PM2 installation
echo "PM2 version:"
pm2 --version

# Install PostgreSQL client (for running migrations)
echo "Installing PostgreSQL client..."
sudo dnf install -y postgresql15

# Install git
echo "Installing git..."
sudo dnf install -y git

# Create application directory
echo "Creating application directory..."
sudo mkdir -p /var/www
sudo chown ec2-user:ec2-user /var/www

# Install CloudWatch agent (optional but recommended)
echo "Installing CloudWatch agent..."
sudo dnf install -y amazon-cloudwatch-agent

# Configure PM2 to start on boot (as root for userdata scripts)
echo "Configuring PM2 startup for root user..."
sudo env PATH=$PATH:/usr/bin:/usr/local/bin pm2 startup systemd -u root --hp /root

echo "========================================="
echo "Backend Golden AMI Setup Complete!"
echo "========================================="
echo ""
echo "Verification:"
node --version
npm --version
pm2 --version
psql --version
echo ""
echo "Next steps:"
echo "1. Create AMI from this instance"
echo "2. Use deploy-backend.sh as user-data when launching from this AMI"
