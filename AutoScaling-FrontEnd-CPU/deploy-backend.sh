#!/bin/bash
# Backend Deployment Script (runs on instance boot from Golden AMI)
# This script clones the repo, configures, and starts the application

set -euo pipefail

LOG_FILE="/var/log/backend-deploy.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "========================================="
echo "Backend Deployment Started: $(date)"
echo "========================================="

# Ensure PM2 is accessible
export PATH=$PATH:/usr/bin:/usr/local/bin

# Get instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
REGION=$(ec2-metadata --availability-zone | cut -d " " -f 2 | sed 's/[a-z]$//')

echo "Instance ID: ${INSTANCE_ID}"
echo "Region: ${REGION}"

# Verify Node.js and PM2 are available
echo "Node.js version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "PM2 version: $(pm2 --version)"

# Fetch database credentials from Parameter Store
echo "Fetching database credentials from Parameter Store..."
DB_HOST=$(aws ssm get-parameter --name "/bmi-app/db-host" --region ${REGION} --query 'Parameter.Value' --output text)
[[ -z "${DB_HOST}" ]] && { echo "FATAL: DB_HOST empty — check SSM parameter /bmi-app/db-host"; exit 1; }
DB_NAME=$(aws ssm get-parameter --name "/bmi-app/db-name" --region ${REGION} --query 'Parameter.Value' --output text)
[[ -z "${DB_NAME}" ]] && { echo "FATAL: DB_NAME empty — check SSM parameter /bmi-app/db-name"; exit 1; }
DB_USER=$(aws ssm get-parameter --name "/bmi-app/db-user" --region ${REGION} --query 'Parameter.Value' --output text)
[[ -z "${DB_USER}" ]] && { echo "FATAL: DB_USER empty — check SSM parameter /bmi-app/db-user"; exit 1; }
DB_PASSWORD=$(aws ssm get-parameter --name "/bmi-app/db-password" --with-decryption --region ${REGION} --query 'Parameter.Value' --output text)
[[ -z "${DB_PASSWORD}" ]] && { echo "FATAL: DB_PASSWORD empty — check SSM parameter /bmi-app/db-password"; exit 1; }

echo "Database host: ${DB_HOST}"
echo "Database name: ${DB_NAME}"

# Clone repository
echo "Cloning repository..."
cd /var/www
if [ -d "app" ]; then
    echo "Removing existing app directory..."
    rm -rf app
fi
git clone https://github.com/sarowar-alam/3-tier-web-app-auto-scalling.git app
cd app/backend

# Install dependencies
echo "Installing npm dependencies..."
npm install --production

# Create .env file
echo "Creating .env file..."
cat > .env << EOF
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:5432/${DB_NAME}
DB_HOST=${DB_HOST}
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
EOF

echo ".env file created successfully"

# Wait for database to be ready
echo "Waiting for database to be ready..."
DB_READY=false
for i in {1..60}; do
    if PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -c "SELECT 1" > /dev/null 2>&1; then
        echo "Database is ready!"
        DB_READY=true
        break
    fi
    echo "Waiting for database... (attempt $i/60)"
    sleep 10
done

if [ "$DB_READY" = false ]; then
    echo "WARNING: Database not ready after 10 minutes. Continuing anyway..."
fi

# Run migrations (idempotent — safe to run every boot thanks to IF NOT EXISTS guards)
echo "Running database migrations..."
for migration in migrations/*.sql; do
    if [ -f "$migration" ]; then
        echo "Running migration: $migration"
        PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -f "$migration"
        echo "Migration applied: $migration"
    fi
done
echo "All migrations applied successfully"

# Verify tables exist
echo "Verifying database tables..."
PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -c "\dt" || echo "Could not list tables"

# Kill any existing Node.js processes on port 3000
echo "Checking for existing Node.js processes..."
if lsof -ti:3000 > /dev/null 2>&1; then
    echo "Killing existing process on port 3000..."
    kill -9 $(lsof -ti:3000) || true
fi

# Start application with PM2 (running as root since userdata runs as root)
echo "Starting application with PM2..."
pm2 delete bmi-backend 2>/dev/null || true
pm2 start ecosystem.config.js --env production

# Set PM2 to start on system boot
echo "Configuring PM2 to start on boot..."
sudo env PATH=$PATH:/usr/bin:/usr/local/bin pm2 startup systemd -u root --hp /root \
    || { echo "ERROR: pm2 startup failed — app will not survive reboots"; exit 1; }
pm2 save || { echo "ERROR: pm2 save failed — app will not survive reboots"; exit 1; }

echo "========================================="
echo "Backend Deployment Complete: $(date)"
echo "========================================="
echo ""
echo "Application running on port 3000"
echo ""
echo "PM2 Status:"
pm2 status
echo ""
echo "PM2 Logs (last 20 lines):"
pm2 logs --lines 20 --nostream
echo ""
echo "Testing health endpoint:"
sleep 3
curl -s localhost:3000/health || echo "Health endpoint not responding yet"
echo ""
echo "========================================="
echo "Deployment log saved to: ${LOG_FILE}"
echo "To view PM2 status: sudo pm2 status"
echo "To view PM2 logs: sudo pm2 logs"
echo "========================================="
