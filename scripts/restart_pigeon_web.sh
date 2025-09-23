#!/bin/bash

# Copyright(c) 2025
# All rights reserved.
#
# Author: yukun.xing <xingyukun@gmail.com>
# Date:   2025/09/11

# Strict error handling
set -e          # Exit on any error
set -u          # Exit on undefined variables
set -o pipefail # Exit on pipe failures

# Global variables for error reporting
SCRIPT_NAME="$(basename "$0")"
CURRENT_STEP=""
ERROR_OCCURRED=false

# Error trap function
error_exit() {
    local exit_code=$?
    ERROR_OCCURRED=true
    
    echo ""
    print_error "=================================="
    print_error "❌ SCRIPT EXECUTION FAILED!"
    print_error "=================================="
    print_error "Script: $SCRIPT_NAME"
    print_error "Current step: $CURRENT_STEP"
    print_error "Exit code: $exit_code"
    print_error "Line: ${BASH_LINENO[0]}"
    print_error "Command: ${BASH_COMMAND}"
    echo ""
    print_error "The script has been terminated due to an error."
    print_error "Please check the output above for details."
    print_error "Fix the issue and run the script again."
    echo ""
    exit $exit_code
}

# Set trap for error handling
trap 'error_exit' ERR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIGEON_WEB_DIR="$SCRIPT_DIR/pigeon_web"

CURRENT_STEP="Initialization"
print_info "Starting pigeon_web system restart..."
print_info "Script directory: $SCRIPT_DIR"
print_info "Pigeon web directory: $PIGEON_WEB_DIR"
print_info "⚠️  Script will EXIT IMMEDIATELY on any error with detailed reporting"

# Step 1: Check .env file
CURRENT_STEP="Step 1: Checking .env file"
print_info "$CURRENT_STEP..."
ENV_FILE="$PIGEON_WEB_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    print_error ".env file not found at: $ENV_FILE"
    print_error "Please create .env file first!"
    exit 1
fi

print_success ".env file found: $ENV_FILE"

# Step 2: Read DATABASE_URL from .env
CURRENT_STEP="Step 2: Reading DATABASE_URL from .env"
print_info "$CURRENT_STEP..."

# Source .env file to get DATABASE_URL
if ! source "$ENV_FILE"; then
    print_error "Failed to source .env file"
    exit 1
fi

if [ -z "$DATABASE_URL" ]; then
    print_error "DATABASE_URL not found in .env file"
    exit 1
fi

print_success "DATABASE_URL found: $DATABASE_URL"

# Parse DATABASE_URL (macOS compatible)
# Format: postgresql://user:password@host:port/database
# Remove protocol prefix
DB_URL_WITHOUT_PROTOCOL=$(echo "$DATABASE_URL" | sed 's|postgresql://||')

# Extract user:password@host:port/database
DB_CREDENTIALS_HOST=$(echo "$DB_URL_WITHOUT_PROTOCOL" | cut -d'/' -f1)
DB_NAME=$(echo "$DB_URL_WITHOUT_PROTOCOL" | cut -d'/' -f2 | cut -d'?' -f1)

# Extract user:password and host:port
DB_CREDENTIALS=$(echo "$DB_CREDENTIALS_HOST" | cut -d'@' -f1)
DB_HOST_PORT=$(echo "$DB_CREDENTIALS_HOST" | cut -d'@' -f2)

# Extract user and password
DB_USER=$(echo "$DB_CREDENTIALS" | cut -d':' -f1)
DB_PASS=$(echo "$DB_CREDENTIALS" | cut -d':' -f2)

# Extract host and port
DB_HOST=$(echo "$DB_HOST_PORT" | cut -d':' -f1)
DB_PORT=$(echo "$DB_HOST_PORT" | cut -d':' -f2)

print_info "Database connection details:"
print_info "  Host: $DB_HOST"
print_info "  Port: $DB_PORT"
print_info "  User: $DB_USER"
print_info "  Database: $DB_NAME"

# Step 3: Check if PostgreSQL is running in Docker
CURRENT_STEP="Step 3: Checking PostgreSQL Docker container"
print_info "$CURRENT_STEP..."

# Check for any PostgreSQL container (more flexible)
if docker ps --format "table {{.Names}}" | grep -i "postgres" > /dev/null 2>&1; then
    PG_CONTAINER=$(docker ps --format "table {{.Names}}" | grep -i "postgres" | head -1)
    print_success "PostgreSQL container is already running: $PG_CONTAINER"
    PG_ALREADY_RUNNING=true
else
    print_info "PostgreSQL container not found. Will start new container..."
    PG_ALREADY_RUNNING=false
fi

# Step 4: Handle data directory for macOS
CURRENT_STEP="Step 4: Setting up data directories for macOS"
print_info "$CURRENT_STEP..."

HOME_DATA_DIR="$HOME/pigeon_data"
POSTGRES_DATA_DIR="$HOME_DATA_DIR/postgres/data"

# Create data directories in home
if [ ! -d "$POSTGRES_DATA_DIR" ]; then
    print_info "Creating PostgreSQL data directory: $POSTGRES_DATA_DIR"
    mkdir -p "$POSTGRES_DATA_DIR"
    print_success "Data directory created"
fi

# Create /data symlink if it doesn't exist
if [ ! -L "/data" ] && [ ! -d "/data" ]; then
    print_info "Creating /data symlink to $HOME_DATA_DIR"
    sudo ln -sf "$HOME_DATA_DIR" /data
    print_success "/data symlink created"
elif [ ! -L "/data" ]; then
    print_warning "/data exists but is not a symlink. Please check manually."
fi

# Step 5: Start PostgreSQL if not running
if [ "$PG_ALREADY_RUNNING" = false ]; then
    CURRENT_STEP="Step 5: Starting PostgreSQL container"
    print_info "$CURRENT_STEP..."
    
    DOCKER_COMPOSE_FILE="$SCRIPT_DIR/pigeon/deployment/docker/middleware/postgresql/docker-compose.yml"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "Docker compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    # Change to docker-compose directory
    cd "$(dirname "$DOCKER_COMPOSE_FILE")"
    
    print_info "Starting PostgreSQL with docker-compose..."
    docker-compose up -d
    
    print_info "Waiting for PostgreSQL to start (60 seconds)..."
    sleep 60
    
    # Check if container is running
    if ! docker ps --format "table {{.Names}}" | grep -i "postgres" > /dev/null 2>&1; then
        print_error "Failed to start PostgreSQL container"
        exit 1
    fi
    
    print_success "PostgreSQL container started successfully"
else
    CURRENT_STEP="Step 5: PostgreSQL already running, dropping existing database"
    print_info "$CURRENT_STEP..."
    
    # Drop existing database
    print_info "Dropping database $DB_NAME if exists..."
    if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -v client_min_messages=error -q -c "DROP DATABASE IF EXISTS $DB_NAME;" >/dev/null; then
        print_error "Failed to drop database $DB_NAME"
        print_error "This usually means there are active connections to the database."
        print_error ""
        print_error "Solutions:"
        print_error "1. Stop your Flask application and frontend server first"
        print_error ""
        print_error "2. Or force disconnect all users by running this command:"
        print_error "----------------------------------------"
        echo "PGPASSWORD=\"$DB_PASS\" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c \"SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$DB_NAME' AND pid <> pg_backend_pid();\""
        print_error "----------------------------------------"
        print_error ""
        print_error "3. Then run this script again: ./restart_pigeon_web.sh"
        print_error ""
        exit 1
    fi
    
    print_success "Database dropped"
fi

# Wait a bit more to ensure PostgreSQL is ready (only if we just started it)
if [ "$PG_ALREADY_RUNNING" = false ]; then
    print_info "Waiting additional 10 seconds for PostgreSQL to be fully ready..."
    sleep 10
else
    print_info "PostgreSQL already running, skipping additional wait"
fi

# Step 6: Initialize database
CURRENT_STEP="Step 6: Initializing database"
print_info "$CURRENT_STEP..."

# Create database
CURRENT_STEP="Creating database $DB_NAME"
print_info "$CURRENT_STEP..."
if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -v client_min_messages=error -q -c "CREATE DATABASE $DB_NAME;" >/dev/null; then
    print_error "Failed to create database $DB_NAME"
    print_error "This could indicate a PostgreSQL connection or permission issue."
    exit 1
fi
print_success "Database $DB_NAME created successfully"

# Execute pigeon_web.sql first
CURRENT_STEP="Executing pigeon_web/sql/pigeon_web.sql"
print_info "$CURRENT_STEP..."
WEB_SQL="$PIGEON_WEB_DIR/sql/pigeon_web.sql"

if [ ! -f "$WEB_SQL" ]; then
    print_error "Web SQL file not found: $WEB_SQL"
    exit 1
fi

if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v client_min_messages=error -q -f "$WEB_SQL" >/dev/null; then
    print_error "Failed to execute pigeon_web.sql"
    print_error "Check the SQL file for syntax errors or database connection issues."
    exit 1
fi
print_success "pigeon_web.sql executed successfully"

# Execute init-db.sql second
CURRENT_STEP="Executing pigeon/deployment/sql/init-db.sql"
print_info "$CURRENT_STEP..."
INIT_SQL="$SCRIPT_DIR/pigeon/deployment/sql/init-db.sql"

if [ ! -f "$INIT_SQL" ]; then
    print_error "Init SQL file not found: $INIT_SQL"
    exit 1
fi

if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v client_min_messages=error -q -f "$INIT_SQL" >/dev/null; then
    print_error "Failed to execute init-db.sql"
    print_error "Check the SQL file for syntax errors or database connection issues."
    exit 1
fi
print_success "init-db.sql executed successfully"

# Step 7: Generate and insert mock data
CURRENT_STEP="Step 7: Generating and inserting mock data"
print_info "$CURRENT_STEP..."

# Create mock data SQL file
CURRENT_STEP="Creating and inserting mock data"
MOCK_DATA_FILE="/tmp/mock_data.sql"

cat > "$MOCK_DATA_FILE" << 'EOF'
-- Mock data for pigeon_web system
-- Copyright(c) 2025
-- Author: yukun.xing <xingyukun@gmail.com>

-- Insert mock enterprises
INSERT INTO enterprises (
    id, name, display_name, description, business_type, industry, company_size,
    registration_number, tax_id, legal_name, primary_email, secondary_email,
    phone, website, address, billing_address, status, tier, max_accounts,
    monthly_sms_limit, is_verified, verified_at, created_at, updated_at
) VALUES 
-- Enterprise 1: TechCorp Global
(
    uuid_generate_v4(),
    'TechCorp Global',
    '{"en": "TechCorp Global", "zh": "科技全球公司"}',
    '{"en": "Leading technology solutions provider", "zh": "领先的技术解决方案提供商"}',
    'technology',
    'software',
    'large',
    'TC2024001',
    'TAX001234567',
    'TechCorp Global Solutions Ltd.',
    'admin@techcorp.com',
    'billing@techcorp.com',
    '+1-555-0101',
    'https://www.techcorp.com',
    '{"street": "123 Tech Street", "city": "San Francisco", "state": "CA", "country": "USA", "zipcode": "94105"}',
    '{"street": "123 Tech Street", "city": "San Francisco", "state": "CA", "country": "USA", "zipcode": "94105"}',
    'active',
    'enterprise',
    50,
    1000000,
    true,
    NOW(),
    NOW(),
    NOW()
),
-- Enterprise 2: StartupInc
(
    uuid_generate_v4(),
    'StartupInc',
    '{"en": "StartupInc", "zh": "创业公司"}',
    '{"en": "Innovative startup company", "zh": "创新创业公司"}',
    'startup',
    'fintech',
    'small',
    'SI2024001',
    'TAX987654321',
    'StartupInc Financial Services',
    'contact@startupinc.com',
    'support@startupinc.com',
    '+1-555-0102',
    'https://www.startupinc.com',
    '{"street": "456 Innovation Blvd", "city": "Austin", "state": "TX", "country": "USA", "zipcode": "73301"}',
    '{"street": "456 Innovation Blvd", "city": "Austin", "state": "TX", "country": "USA", "zipcode": "73301"}',
    'active',
    'standard',
    10,
    100000,
    true,
    NOW(),
    NOW(),
    NOW()
),
-- Enterprise 3: RetailChain
(
    uuid_generate_v4(),
    'RetailChain',
    '{"en": "RetailChain", "zh": "零售连锁"}',
    '{"en": "National retail chain", "zh": "全国零售连锁"}',
    'retail',
    'commerce',
    'medium',
    'RC2024001',
    'TAX555666777',
    'RetailChain Commerce Corp.',
    'info@retailchain.com',
    'orders@retailchain.com',
    '+1-555-0103',
    'https://www.retailchain.com',
    '{"street": "789 Commerce Ave", "city": "Chicago", "state": "IL", "country": "USA", "zipcode": "60601"}',
    '{"street": "789 Commerce Ave", "city": "Chicago", "state": "IL", "country": "USA", "zipcode": "60601"}',
    'active',
    'premium',
    25,
    500000,
    true,
    NOW(),
    NOW(),
    NOW()
);

-- Get enterprise IDs for account creation
DO $$
DECLARE
    techcorp_id UUID;
    startup_id UUID;
    retail_id UUID;
BEGIN
    -- Get enterprise IDs
    SELECT id INTO techcorp_id FROM enterprises WHERE name = 'TechCorp Global' LIMIT 1;
    SELECT id INTO startup_id FROM enterprises WHERE name = 'StartupInc' LIMIT 1;
    SELECT id INTO retail_id FROM enterprises WHERE name = 'RetailChain' LIMIT 1;

    -- Insert mock accounts
    INSERT INTO accounts (
        account_id, unique_id, name, code, status, enabled, is_banned,
        protocol_type, account_type, password, sender_id, identity_code,
        extend_code, valid_ips, max_connection_count, max_deliver_resend_count,
        priority, enterprise_id, protocol_config, number_blacklist,
        signatures, whitelisted, censor_words, templates, balance_alert_threshold,
        description, notes, created_at, updated_at
    ) VALUES 
    -- Account 1: TechCorp SMPP Production
    (
        'TECH001',
        uuid_generate_v4(),
        'TechCorp SMPP Main',
        'TC_SMPP_01',
        'active',
        true,
        false,
        'smpp',
        'production',
        'hashed_password_123',
        'TECHCORP',
        'TC001',
        'EXT001',
        '192.168.1.100,10.0.0.50',
        5,
        3,
        100,
        techcorp_id,
        jsonb_build_object(
            'smpp', jsonb_build_object(
                'host', 'smpp.provider1.com',
                'port', 2775,
                'username', 'techcorp_user',
                'password', 'smpp_pass_123',
                'system_type', 'SMS',
                'interface_version', 52,
                'addr_ton', 0,
                'addr_npi', 0,
                'bind_type', 'transceiver'
            ),
            'connection', jsonb_build_object(
                'timeout', 30,
                'retry_count', 3,
                'retry_interval', 5,
                'keep_alive', true,
                'pool_size', 5
            ),
            'rate_limits', jsonb_build_object(
                'tps', 50,
                'daily_limit', 100000,
                'monthly_limit', 3000000,
                'enabled', true
            ),
            'advanced', jsonb_build_object(
                'routing_priority', 90,
                'auto_failover', true
            )
        ),
        '{}',
        '{}',
        true,
        '{}',
        '{}',
        1000.0000,
        'Main SMPP account for TechCorp production traffic',
        'High priority account with premium SLA',
        NOW(),
        NOW()
    ),
    -- Account 2: TechCorp HTTP Backup
    (
        'TECH002',
        uuid_generate_v4(),
        'TechCorp HTTP Backup',
        'TC_HTTP_01',
        'active',
        true,
        false,
        'http',
        'production',
        'hashed_password_456',
        'TCBACKUP',
        'TC002',
        'EXT002',
        '192.168.1.100,10.0.0.50',
        3,
        2,
        80,
        techcorp_id,
        jsonb_build_object(
            'http', jsonb_build_object(
                'url', 'https://api.provider2.com/sms/send',
                'method', 'POST',
                'auth_type', 'bearer',
                'api_key', 'tc_api_key_789',
                'headers', jsonb_build_object(
                    'Content-Type', 'application/json',
                    'X-Client', 'TechCorp'
                ),
                'timeout', 30
            ),
            'connection', jsonb_build_object(
                'timeout', 25,
                'retry_count', 2,
                'retry_interval', 3,
                'keep_alive', true,
                'pool_size', 3
            ),
            'rate_limits', jsonb_build_object(
                'tps', 30,
                'daily_limit', 50000,
                'monthly_limit', 1500000,
                'enabled', true
            ),
            'advanced', jsonb_build_object(
                'routing_priority', 70,
                'auto_failover', true
            )
        ),
        '{}',
        '{}',
        true,
        '{}',
        '{}',
        500.0000,
        'Backup HTTP account for TechCorp failover',
        'Backup channel with standard SLA',
        NOW(),
        NOW()
    ),
    -- Account 3: StartupInc SMPP
    (
        'START001',
        uuid_generate_v4(),
        'StartupInc SMPP',
        'SI_SMPP_01',
        'active',
        true,
        false,
        'smpp',
        'production',
        'hashed_password_789',
        'STARTUP',
        'SI001',
        'EXT003',
        '203.0.113.0/24',
        2,
        1,
        50,
        startup_id,
        jsonb_build_object(
            'smpp', jsonb_build_object(
                'host', 'smpp.budget-provider.com',
                'port', 2775,
                'username', 'startup_user',
                'password', 'startup_pass',
                'system_type', 'SMS',
                'interface_version', 52,
                'addr_ton', 0,
                'addr_npi', 0,
                'bind_type', 'transceiver'
            ),
            'connection', jsonb_build_object(
                'timeout', 20,
                'retry_count', 2,
                'retry_interval', 5,
                'keep_alive', true,
                'pool_size', 2
            ),
            'rate_limits', jsonb_build_object(
                'tps', 10,
                'daily_limit', 10000,
                'monthly_limit', 300000,
                'enabled', true
            ),
            'advanced', jsonb_build_object(
                'routing_priority', 50,
                'auto_failover', false
            )
        ),
        '{}',
        '{}',
        false,
        '{}',
        '{}',
        100.0000,
        'Primary SMPP account for StartupInc',
        'Budget tier account',
        NOW(),
        NOW()
    ),
    -- Account 4: RetailChain SMPP Primary
    (
        'RETAIL001',
        uuid_generate_v4(),
        'RetailChain SMPP Primary',
        'RC_SMPP_01',
        'active',
        true,
        false,
        'smpp',
        'production',
        'hashed_password_retail',
        'RETAIL',
        'RC001',
        'EXT004',
        '198.51.100.0/24',
        8,
        5,
        90,
        retail_id,
        jsonb_build_object(
            'smpp', jsonb_build_object(
                'host', 'smpp.premium-provider.com',
                'port', 2775,
                'username', 'retail_user',
                'password', 'retail_secure_pass',
                'system_type', 'RETAIL',
                'interface_version', 52,
                'addr_ton', 1,
                'addr_npi', 1,
                'bind_type', 'transceiver'
            ),
            'connection', jsonb_build_object(
                'timeout', 35,
                'retry_count', 4,
                'retry_interval', 3,
                'keep_alive', true,
                'pool_size', 8
            ),
            'rate_limits', jsonb_build_object(
                'tps', 100,
                'daily_limit', 200000,
                'monthly_limit', 6000000,
                'enabled', true
            ),
            'advanced', jsonb_build_object(
                'routing_priority', 95,
                'auto_failover', true,
                'signatures', array['RETAILCHAIN', 'RC-DEALS'],
                'blacklist_keywords', array['SPAM', 'FAKE']
            )
        ),
        '{"blocked_numbers": ["+15551234567", "+15559876543"]}',
        '{"primary": "RETAILCHAIN", "promo": "RC-DEALS", "support": "RC-HELP"}',
        true,
        '{"words": ["spam", "fake", "scam"]}',
        '{"welcome": "Welcome to RetailChain!", "order": "Your order #{order_id} has been confirmed"}',
        2000.0000,
        'Primary high-volume SMPP account for RetailChain',
        'Premium tier with advanced filtering and high throughput',
        NOW(),
        NOW()
    ),
    -- Account 5: RetailChain HTTP Secondary
    (
        'RETAIL002',
        uuid_generate_v4(),
        'RetailChain HTTP Secondary',
        'RC_HTTP_01',
        'active',
        true,
        false,
        'http',
        'production',
        'hashed_password_retail2',
        'RCHTTP',
        'RC002',
        'EXT005',
        '198.51.100.0/24',
        4,
        3,
        70,
        retail_id,
        jsonb_build_object(
            'http', jsonb_build_object(
                'url', 'https://api.retail-sms.com/v2/send',
                'method', 'POST',
                'auth_type', 'basic',
                'username', 'retail_api_user',
                'password', 'retail_api_pass',
                'headers', jsonb_build_object(
                    'Content-Type', 'application/json',
                    'X-Source', 'RetailChain'
                ),
                'timeout', 25
            ),
            'connection', jsonb_build_object(
                'timeout', 25,
                'retry_count', 3,
                'retry_interval', 4,
                'keep_alive', true,
                'pool_size', 4
            ),
            'rate_limits', jsonb_build_object(
                'tps', 60,
                'daily_limit', 100000,
                'monthly_limit', 3000000,
                'enabled', true
            ),
            'advanced', jsonb_build_object(
                'routing_priority', 75,
                'auto_failover', true
            )
        ),
        '{}',
        '{}',
        true,
        '{}',
        '{}',
        1500.0000,
        'Secondary HTTP account for RetailChain overflow traffic',
        'Secondary channel for high-availability setup',
        NOW(),
        NOW()
    ),
    -- Account 6: Test Account
    (
        'TEST001',
        uuid_generate_v4(),
        'Test Development Account',
        'TEST_DEV_01',
        'testing',
        true,
        false,
        'smpp',
        'test',
        'test_password',
        'TESTDEV',
        'TEST001',
        'EXTTEST',
        '127.0.0.1,localhost',
        1,
        1,
        10,
        startup_id,
        jsonb_build_object(
            'smpp', jsonb_build_object(
                'host', 'localhost',
                'port', 2775,
                'username', 'test_user',
                'password', 'test_pass',
                'system_type', 'TEST',
                'interface_version', 52,
                'addr_ton', 0,
                'addr_npi', 0,
                'bind_type', 'transceiver'
            ),
            'connection', jsonb_build_object(
                'timeout', 10,
                'retry_count', 1,
                'retry_interval', 2,
                'keep_alive', false,
                'pool_size', 1
            ),
            'rate_limits', jsonb_build_object(
                'tps', 1,
                'daily_limit', 100,
                'monthly_limit', 3000,
                'enabled', true
            )
        ),
        '{}',
        '{}',
        false,
        '{}',
        '{}',
        0.0000,
        'Development and testing account',
        'For development and testing purposes only',
        NOW(),
        NOW()
    );

END $$;

-- Update sequences and add some additional data
SELECT setval('admin_users_id_seq', COALESCE((SELECT MAX(id) FROM admin_users), 1));

-- Add some usage statistics (mock data)
-- This would typically be handled by the SMS service, but we'll add some sample data

COMMIT;
EOF

print_info "$CURRENT_STEP..."
if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v client_min_messages=error -q -f "$MOCK_DATA_FILE" >/dev/null; then
    print_error "Failed to insert mock data"
    print_error "Check the mock data SQL for syntax errors or constraint violations."
    # Clean up even on failure
    rm -f "$MOCK_DATA_FILE"
    exit 1
fi

# Clean up
rm -f "$MOCK_DATA_FILE"

print_success "Mock data inserted successfully!"

# Print statistics
print_info "Database setup completed! Statistics:"

# Check statistics with proper error handling
CURRENT_STEP="Querying database statistics"
if ! ENTERPRISES_COUNT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v client_min_messages=error -q -t -c "SELECT COUNT(*) FROM enterprises;" 2>/dev/null | xargs); then
    print_error "Failed to query enterprises count"
    exit 1
fi

if ! ACCOUNTS_COUNT=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -v client_min_messages=error -q -t -c "SELECT COUNT(*) FROM accounts;" 2>/dev/null | xargs); then
    print_error "Failed to query accounts count"
    exit 1
fi

print_success "  - Enterprises: $ENTERPRISES_COUNT"
print_success "  - Accounts: $ACCOUNTS_COUNT"

# Final instructions
# Final success message
CURRENT_STEP="Final validation and cleanup"
print_success "========================================"
print_success "✅ SCRIPT EXECUTION SUCCESSFUL!"
print_success "========================================"
print_success "🎉 Pigeon Web system database restart completed successfully!"
echo ""
print_info "Next steps:"
print_info "==================================================================="
print_warning "follow pigeon_web/README.md to restart BE and FE server"
print_info "==================================================================="
echo ""
print_info "Database connection details:"
print_info "  Host: $DB_HOST:$DB_PORT"
print_info "  Database: $DB_NAME"
print_info "  User: $DB_USER"
echo ""
print_info "Mock data includes:"
print_info "  - 3 enterprises (TechCorp Global, StartupInc, RetailChain)"
print_info "  - 6 accounts (various SMPP/HTTP configurations)"
print_info "  - Production-ready configurations with protocol_config"
echo ""
print_warning "Default admin login credentials:"
print_warning "  Username: admin"
print_warning "  Password: admin123"
print_warning "  ⚠️  Please change the default password after first login!"
echo ""
print_success "System is ready for development and testing! 🚀"

# Mark successful completion only if no errors occurred
if [ "$ERROR_OCCURRED" = false ]; then
    ERROR_OCCURRED=false
    print_success "=================================="
    print_success "✅ ALL STEPS COMPLETED SUCCESSFULLY"
    print_success "=================================="
    print_success "Script: $SCRIPT_NAME"
    print_success "Total execution time: $SECONDS seconds"
    print_success "No errors encountered during execution."
    echo ""
else
    print_error "=================================="
    print_error "❌ SCRIPT COMPLETED WITH ERRORS!"
    print_error "=================================="
    print_error "Script: $SCRIPT_NAME"
    print_error "Total execution time: $SECONDS seconds"
    print_error "Please check the output above for error details."
    echo ""
    exit 1
fi
