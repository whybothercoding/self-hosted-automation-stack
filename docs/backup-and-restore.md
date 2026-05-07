# Backup and Restore

## What Gets Backed Up

The `scripts/backup.sh` script backs up three Docker volumes. Volume names are prefixed with the Docker Compose project name, which defaults to the directory name the repo was cloned into.

To check your project name:

```bash
docker compose config | grep -m1 '^name:' | awk '{print $2}'
```

| Volume suffix          | Contains                                   |
|------------------------|--------------------------------------------|
| `<project>_n8n_data`      | n8n workflows, credentials, execution logs |
| `<project>_baserow_data`  | Baserow media files and uploads            |
| `<project>_postgres_data` | All database data for both n8n and Baserow |

Backing up `postgres_data` covers all structured data. The `baserow_data` volume stores file/image uploads only.

## Running a Backup

```bash
bash scripts/backup.sh
```

The script:
1. Creates `./backups/` if it doesn't exist
2. Detects the Compose project name automatically
3. Stops all containers gracefully with `docker compose stop`
4. Creates a timestamped `.tar.gz` for each volume using a temporary Alpine container
5. Restarts all containers with `docker compose start`
6. Prints the backup file paths

Example output (project name `self-hosted-automation-stack`):

```
[20260422_140000] Starting backup (project: self-hosted-automation-stack)...
Stopping containers gracefully...
Backing up volume: self-hosted-automation-stack_n8n_data → ./backups/self-hosted-automation-stack_n8n_data_20260422_140000.tar.gz
Backing up volume: self-hosted-automation-stack_baserow_data → ...
Backing up volume: self-hosted-automation-stack_postgres_data → ...
Restarting containers...

Backup complete. Files saved to: ./backups
```

## Automating Backups with Cron

To run backups daily at 2 AM:

```bash
crontab -e
```

Add (adjust the path to match your actual install location):

```
0 2 * * * /home/ubuntu/self-hosted-automation-stack/scripts/backup.sh >> /var/log/stack-backup.log 2>&1
```

For weekly backups (Sundays at 2 AM):

```
0 2 * * 0 /home/ubuntu/self-hosted-automation-stack/scripts/backup.sh >> /var/log/stack-backup.log 2>&1
```

## Restoring from a Backup

First, capture your project name into a variable — all volume operations below use it:

```bash
PROJ=$(docker compose config | grep -m1 '^name:' | awk '{print $2}')
```

### Step 1: Stop the Stack

```bash
docker compose down
```

### Step 2: Remove the Existing Volume

```bash
docker volume rm ${PROJ}_n8n_data
```

### Step 3: Recreate the Volume

```bash
docker volume create ${PROJ}_n8n_data
```

### Step 4: Restore the Data

```bash
docker run --rm \
  -v ${PROJ}_n8n_data:/data \
  -v $(pwd)/backups:/backup \
  alpine \
  tar xzf /backup/${PROJ}_n8n_data_20260422_140000.tar.gz -C /data
```

Repeat steps 2–4 for `baserow_data` and `postgres_data`, substituting the volume suffix and backup filename.

### Step 5: Start the Stack

```bash
docker compose up -d
```

### Step 6: Verify

Open your n8n and Baserow URLs and confirm workflows and databases are intact. Check logs for errors:

```bash
docker compose logs --tail=100
```

## Transferring Backups Off-Server

Keep at least one copy off the VPS to protect against server loss.

**rsync to another server:**

```bash
rsync -avz ./backups/ user@backup-server:/path/to/backups/
```

**SCP to your local machine:**

```bash
scp -r ubuntu@your-vps-ip:~/self-hosted-automation-stack/backups/ ./local-backups/
```

**AWS S3 (requires AWS CLI):**

```bash
aws s3 sync ./backups/ s3://your-bucket/stack-backups/
```

## Backup Retention

The backup script does not automatically delete old backups. To keep only the last 7 days:

```bash
find /home/ubuntu/self-hosted-automation-stack/backups/ -name "*.tar.gz" -mtime +7 -delete
```

Add this to your crontab alongside the backup command, or append it to `scripts/backup.sh`.
