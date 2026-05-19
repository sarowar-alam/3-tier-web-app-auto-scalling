#!/bin/bash
# Frontend Deployment Script (runs on instance boot from Golden AMI)
# This script clones the repo, builds React app, and configures nginx

set -euo pipefail

LOG_FILE="/var/log/frontend-deploy.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "========================================="
echo "Frontend Deployment Started: $(date)"
echo "========================================="

# Get instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
REGION=$(ec2-metadata --availability-zone | cut -d " " -f 2 | sed 's/[a-z]$//')

echo "Instance ID: ${INSTANCE_ID}"
echo "Region: ${REGION}"

# Fetch backend ALB URL from Parameter Store
echo "Fetching backend ALB URL from Parameter Store..."
BACKEND_ALB_URL=$(aws ssm get-parameter --name "/bmi-app/backend-alb-url" --region ${REGION} --query 'Parameter.Value' --output text)
[[ -z "${BACKEND_ALB_URL}" ]] && { echo "FATAL: BACKEND_ALB_URL empty — check SSM parameter /bmi-app/backend-alb-url"; exit 1; }
echo "Backend ALB URL: ${BACKEND_ALB_URL}"

# Clone repository
echo "Cloning repository..."
cd /var/www
if [ -d "app" ]; then
    rm -rf app
fi
git clone https://github.com/sarowar-alam/3-tier-web-app-auto-scalling.git app
cd app/frontend

# Update API endpoint to use relative URL (nginx will proxy to backend ALB)
echo "Updating API endpoint..."
cat > src/api.js << 'EOF'
import axios from 'axios';

const api = axios.create({
  baseURL: '/api',
  headers: {
    'Content-Type': 'application/json',
  },
  timeout: 10000,
});

export default api;
EOF

# Install dependencies
echo "Installing npm dependencies..."
npm install

# Build React app
echo "Building React application..."
npm run build

# Configure nginx
# Unquoted heredoc: ${BACKEND_ALB_URL} is expanded by bash;
# nginx $-variables are escaped with \ so bash leaves them as literals.
echo "Configuring nginx..."
sudo tee /etc/nginx/conf.d/frontend.conf > /dev/null << EOF
server {
    listen 80;
    server_name _;
    root /var/www/app/frontend/dist;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json;

    # Main application
    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # Static assets caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Health check endpoint for ALB
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Proxy API requests to backend ALB
    location /api/ {
        proxy_pass ${BACKEND_ALB_URL}/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Remove conflicting default server block from nginx.conf
echo "Removing default nginx server block to avoid conflicts..."
sudo sed -i '37,54s/^/# /' /etc/nginx/nginx.conf

# Test nginx configuration
echo "Testing nginx configuration..."
sudo nginx -t

# Reload nginx
echo "Reloading nginx..."
sudo systemctl reload nginx

# Ensure nginx is running
sudo systemctl status nginx

echo "========================================="
echo "Frontend Deployment Complete: $(date)"
echo "========================================="
echo "Application accessible on port 80"
echo "Backend ALB: ${BACKEND_ALB_URL}"
