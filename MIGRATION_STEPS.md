# Chatwoot Migration Guide: 3.16.x to 4.10.1

This guide provides step-by-step instructions for migrating a Docker-based Chatwoot installation from version 3.16.x to 4.10.1.

## Pre-Migration Checklist

- [ ] Schedule maintenance window
- [ ] Notify users of expected downtime
- [ ] Verify current version: `docker exec -it chatwoot-rails bundle exec rake version`
- [ ] Review disk space (recommended: 2x current database size for safety)

---

## Step 1: Backup Everything

### 1.1 Backup PostgreSQL Database

```bash
# Create backup directory
mkdir -p ~/chatwoot-backups/$(date +%Y%m%d)
cd ~/chatwoot-backups/$(date +%Y%m%d)

# Dump the database (adjust container name if needed)
docker exec chatwoot-postgres pg_dump -U postgres chatwoot_production > chatwoot_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify backup was created
ls -la chatwoot_backup_*.sql
```

### 1.2 Backup Redis Data (Optional but Recommended)

```bash
# If using persistent Redis
docker exec chatwoot-redis redis-cli -a YOUR_REDIS_PASSWORD BGSAVE
docker cp chatwoot-redis:/data/dump.rdb ./redis_backup_$(date +%Y%m%d_%H%M%S).rdb
```

### 1.3 Backup Environment Files

```bash
# Backup your .env file
cp /path/to/chatwoot/.env ./env_backup_$(date +%Y%m%d_%H%M%S)

# Backup docker-compose file
cp /path/to/chatwoot/docker-compose.yaml ./docker-compose_backup_$(date +%Y%m%d_%H%M%S).yaml
```

### 1.4 Backup Uploaded Files (if using local storage)

```bash
# If ACTIVE_STORAGE_SERVICE=local
docker cp chatwoot-rails:/app/storage ./storage_backup_$(date +%Y%m%d_%H%M%S)
```

---

## Step 2: Stop Chatwoot Services

```bash
cd /path/to/chatwoot

# Stop all services
docker-compose down

# Verify all containers are stopped
docker ps | grep chatwoot
```

---

## Step 3: Update PostgreSQL (if needed)

Version 4.10.1 uses `pgvector/pgvector:pg16`. If you're on an older PostgreSQL version:

### 3.1 Check Current PostgreSQL Version

```bash
docker exec chatwoot-postgres psql -U postgres -c "SELECT version();"
```

### 3.2 Upgrade PostgreSQL (if < 16)

If upgrading from PostgreSQL 12/13/14/15 to 16:

```bash
# Export data
docker exec chatwoot-postgres pg_dumpall -U postgres > chatwoot_full_dump.sql

# Update docker-compose.yaml to use new image
# image: pgvector/pgvector:pg16

# Remove old volume and recreate
docker volume rm chatwoot_postgres

# Start new PostgreSQL
docker-compose up -d postgres

# Wait for it to be ready
sleep 10

# Import data
docker exec -i chatwoot-postgres psql -U postgres < chatwoot_full_dump.sql
```

---

## Step 4: Update Environment Variables

### 4.1 Add New Required Variables for MFA/2FA (Optional but Recommended)

Generate encryption keys (run locally with Rails or use OpenSSL):

```bash
# Option 1: Generate using OpenSSL
echo "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(openssl rand -hex 16)"
echo "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(openssl rand -hex 16)"
echo "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(openssl rand -hex 16)"
```

Add to your `.env` file:

```bash
# Active Record Encryption keys (required for MFA/2FA functionality)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=your_generated_key_here
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=your_generated_key_here
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=your_generated_key_here
```

### 4.2 Review Other Environment Variables

Check `.env.example` in version 4.10.1 for any new variables you may need:

```bash
# Notable new/changed variables in 4.10.1:
# - HELPCENTER_URL (optional, for dedicated help center URL)
# - ENABLE_RACK_ATTACK_WIDGET_API (throttling for widget API)
# - RACK_ATTACK_ALLOWED_IPS (trusted IPs that bypass throttling)
```

---

## Step 5: Update Docker Images

### 5.1 Pull New Images

```bash
# Pull the official Chatwoot 4.10.1 image
docker pull chatwoot/chatwoot:v4.10.1

# Or if using latest
docker pull chatwoot/chatwoot:latest
```

### 5.2 Update docker-compose.yaml

Update image references in your `docker-compose.yaml`:

```yaml
services:
  rails:
    image: chatwoot/chatwoot:v4.10.1
    # ... rest of config

  sidekiq:
    image: chatwoot/chatwoot:v4.10.1
    # ... rest of config

  postgres:
    image: pgvector/pgvector:pg16
    # ... rest of config
```

---

## Step 6: Run Database Migrations

### 6.1 Start Database Services Only

```bash
docker-compose up -d postgres redis
sleep 10  # Wait for services to be ready
```

### 6.2 Run Migrations

```bash
# Run database migrations
docker-compose run --rm rails bundle exec rails db:migrate

# If you encounter issues, check migration status
docker-compose run --rm rails bundle exec rails db:migrate:status
```

### 6.3 Clear Cache (Recommended)

```bash
docker-compose run --rm rails bundle exec rails cache:clear
```

---

## Step 7: Start Chatwoot Services

```bash
# Start all services
docker-compose up -d

# Check logs for errors
docker-compose logs -f rails
docker-compose logs -f sidekiq
```

---

## Step 8: Post-Migration Verification

### 8.1 Health Check

```bash
# Check if the application is running
curl -I http://localhost:3000/api

# Expected: HTTP/1.1 200 OK
```

### 8.2 Verify Version

```bash
docker exec chatwoot-rails cat /app/config/app.yml | grep version
# Should show: version: '4.10.1'
```

### 8.3 Check Sidekiq

```bash
# Verify background jobs are processing
docker exec chatwoot-rails bundle exec rails runner "puts Sidekiq::Stats.new.processed"
```

### 8.4 Test Key Features

1. Log into the dashboard
2. Verify existing conversations are visible
3. Send a test message
4. Check webhook integrations
5. Verify email notifications work

---

## Rollback Procedure (If Needed)

If you encounter critical issues:

### Rollback Steps

```bash
# 1. Stop services
docker-compose down

# 2. Restore original docker-compose.yaml
cp ~/chatwoot-backups/YYYYMMDD/docker-compose_backup_*.yaml ./docker-compose.yaml

# 3. Restore .env
cp ~/chatwoot-backups/YYYYMMDD/env_backup_* ./.env

# 4. Revert to old image
docker-compose pull

# 5. Restore database
docker-compose up -d postgres
sleep 10
docker exec -i chatwoot-postgres psql -U postgres chatwoot_production < ~/chatwoot-backups/YYYYMMDD/chatwoot_backup_*.sql

# 6. Start services
docker-compose up -d
```

---

## Breaking Changes & Notes

### Key Changes from 3.16.x to 4.10.1

1. **Ruby Version**: Upgraded to Ruby 3.4.4
2. **Rails Version**: Now using Rails 7.1
3. **PostgreSQL**: Recommended version is PostgreSQL 16 with pgvector extension
4. **MFA/2FA**: New feature requiring Active Record Encryption keys
5. **Vite**: Frontend build now uses Vite instead of Webpacker
6. **Captain AI**: New AI assistant features (requires OpenAI API key if used)

### Deprecated Features

- CSML bots have been converted to webhook bots
- Telegram bots table removed (migration: `20250826000000_drop_telegram_bots`)
- Robin tables removed in favor of Captain

### New Features in 4.10.1

- Custom roles support
- Companies/Organizations for contacts
- Improved SLA management
- Two-factor authentication (2FA/MFA)
- TikTok channel integration
- Instagram channel improvements
- Voice channel support

---

## Troubleshooting

### Migration Fails

```bash
# Check pending migrations
docker-compose run --rm rails bundle exec rails db:migrate:status

# Run specific migration
docker-compose run --rm rails bundle exec rails db:migrate:up VERSION=20250104200055
```

### Asset Compilation Issues

```bash
# Recompile assets
docker-compose run --rm rails bundle exec rails assets:precompile
```

### Redis Connection Issues

```bash
# Test Redis connection
docker exec chatwoot-rails bundle exec rails runner "puts Redis.new.ping"
```

### Sidekiq Not Processing Jobs

```bash
# Clear stuck jobs
docker exec chatwoot-rails bundle exec rails runner "Sidekiq::Queue.all.each(&:clear)"

# Restart Sidekiq
docker-compose restart sidekiq
```

---

## Support

- Documentation: https://www.chatwoot.com/docs/self-hosted
- GitHub Issues: https://github.com/chatwoot/chatwoot/issues
- Community: https://discord.gg/cJXdrwS
