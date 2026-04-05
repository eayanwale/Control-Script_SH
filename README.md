# Control-Script_SH

Bash utility for Oracle DBA operations — Data Pump export/import, local and cloud (AWS) database migrations, secure file transfers, disk monitoring, and automated backup cleanup. Menu-driven with full CLI support.

---

## Overview

A multi-purpose Bash utility for Oracle database administration. This script consolidates common DBA tasks into a single tool with a menu-driven interface and full command-line argument support. It handles secure file transfers, file/directory backups, disk monitoring, Oracle Data Pump exports and imports, local and cloud database migrations, and automated cleanup of old backups.

---

## Prerequisites

- Oracle Database with Data Pump (`expdp` / `impdp`) configured
- Oracle environment files at `/home/oracle/scripts/oracle_env_<DBNAME>.sh`
- An Oracle user with access to `v$instance` and `dba_users`
- Data Pump directory object configured in Oracle (e.g., `DATA_PUMP_DIR`)
- `/backup` mount point with sufficient space
- `mailx` configured for email alerts
- SSH key (`.pem`) for cloud server operations
- Bash 4+

---

## Environment Variables

The script references the following environment variables. These must be set or sourced before execution (e.g., via a `.oracle_creds` file):

| Variable | Description |
|----------|-------------|
| `DB_USER` | Oracle database username |
| `DB_PASS` | Oracle database password |
| `PEM_KEY` | Path to the `.pem` private key for cloud (AWS) SCP/SSH operations |
| `ALERT_EMAIL` | Email address for `mailx` alert notifications |

**Example `.oracle_creds` file:**

```bash
export DB_USER="your_oracle_user"
export DB_PASS="your_oracle_password"
export PEM_KEY="/path/to/your_key.pem"
export ALERT_EMAIL="your-email@example.com"
```

```bash
source ~/.oracle_creds
chmod 600 ~/.oracle_creds
```

> **Important:** Never commit `.oracle_creds` or any file containing credentials. This file is excluded via `.gitignore`.

---

## Functions

### SCP — Secure Copy

Transfers files or directories to a remote server. Automatically detects whether the destination is a cloud (AWS) or on-prem server and adjusts the SCP command accordingly. Cloud transfers use `${PEM_KEY}`; on-prem transfers use `ssh-rsa` host key negotiation. Sends email alerts to `${ALERT_EMAIL}` on failure or partial transfers.

**Usage:**
```bash
./script.sh scp <SOURCE> <DST_USER> <DST_SERVER> <DST_PATH> <RUNNER>
```

**Example:**
```bash
./script.sh scp /home/oracle/export.dmp oracle onprem.server.com /home/oracle/imports ENOCH
```

---

### BACKUP_F_D — File/Directory Backup

Creates a timestamped backup of a file or directory under `/backup`. Runs a disk utilization check before proceeding. Organizes backups into `backup_dir/` and `backup_file/` subdirectories and validates the copy afterward.

**Usage:**
```bash
./script.sh backup_f_d <THRESHOLD> <SOURCE> <RUNNER>
```

**Example:**
```bash
./script.sh backup_f_d 80 /home/oracle/scripts ENOCH
```

---

### DISK_UTILIZATION — Disk Space Monitor

Checks disk usage against a defined threshold. If utilization exceeds the threshold, it sends an email alert to `${ALERT_EMAIL}` and returns a non-zero exit code. Used internally by other functions before backup operations.

**Usage:**
```bash
./script.sh disk_util <DISKS> <THRESHOLD> <RUNNER>
```

**Example:**
```bash
./script.sh disk_util /backup 80 ENOCH
```

---

### DATABASE_BACKUP — Oracle Data Pump Export

Performs a full Oracle Data Pump export (`expdp`) for one or more schemas. Connects to Oracle using `${DB_USER}/${DB_PASS}`. The workflow includes disk utilization check, database instance and open status validation, dynamic schema list generation via SQL query, per-schema export with parameter files, tar/gzip archival of dump files, email notifications on success or failure, and cleanup of old backups based on retention policy.

**Usage:**
```bash
./script.sh database_backup <RUNNER> <THRESHOLD> <DB_NAME> <DIRECTORY> "<SQL_QUERY>"
```

**Example:**
```bash
./script.sh database_backup ENOCH 80 APEXDB DATA_PUMP_DIR "select username from dba_users where username like 'STACK%'"
```

---

### DATABASE_IMPORT — Oracle Data Pump Import

Imports a previously exported dump file into a destination database using `impdp`. Extracts the dump from a tar archive, validates the destination database status, and imports each schema with `remap_schema` to avoid overwriting the original. Verifies the imported schema exists in `dba_users` after completion.

**Usage:**
```bash
./script.sh database_import <SRC_DB> <DEST_DB> <RUNNER> <DIRECTORY> <TAR_FILE> <DUMP_FILE> "<SQL_QUERY>"
```

**Example:**
```bash
./script.sh database_import APEXDB DEVDB ENOCH DATA_PUMP_DIR expdp_STACK_TEMP_ENOCH.tar expdp_STACK_TEMP_ENOCH.dmp "select username from dba_users where username like 'STACK%'"
```

---

### LOCAL_MIGRATION — On-Prem Database Migration

Orchestrates a full local migration by chaining `DATABASE_BACKUP` and `DATABASE_IMPORT`. Exports schemas from a source database, then imports them into a destination database on the same server.

**Usage:**
```bash
./script.sh local_migration <SRC_DB> <DEST_DB> <RUNNER> <DIRECTORY> "<SQL_QUERY>"
```

**Example:**
```bash
./script.sh local_migration APEXDB DEVDB ENOCH DATA_PUMP_DIR "select username from dba_users where username like 'STACK%'"
```

---

### CLOUD_MIGRATION — Cloud Database Migration

End-to-end migration from an on-prem Oracle database to a cloud (AWS) instance. Runs a local Data Pump export, transfers tar archives to the cloud server via SCP using `${PEM_KEY}`, dynamically generates a remote import script, pushes and executes it on the cloud server via SSH.

**Usage:**
```bash
./script.sh CLOUD_MIGRATION <SRC_DB> <DEST_DB> <DEST_SERVER> <RUNNER> <DIRECTORY> "<SQL_QUERY>"
```

**Example:**
```bash
./script.sh CLOUD_MIGRATION APEXDB CLOUDDB ec2-xx-xx-xx-xx.compute.amazonaws.com ENOCH DATA_PUMP_DIR "select username from dba_users where username like 'STACK%'"
```

---

### CLEANUP — Old Backup Removal

Deletes files matching a pattern older than a specified number of days. Uses `find -mtime` for retention-based cleanup. Reports file counts before and after deletion and sends email alerts to `${ALERT_EMAIL}` on failure.

**Usage:**
```bash
./script.sh cleanup <MTIME> <FILE_PATH> <FILE_PATTERN> <RUNNER>
```

**Example:**
```bash
./script.sh cleanup +7 /backup/AWSJAN26/DATAPUMP/APEXDB ENOCH ENOCH
```

---

## Interactive Mode

If no arguments are provided, the script presents a menu:

```
Function list:
1) scp
2) backup_f_d
3) disk_util
4) database_backup
5) database_import
6) local_migration
7) cleanup
8) quit
Select a function:
```

Each function then prompts for the required inputs interactively.

---

## Email Alerts

All critical operations send email notifications to `${ALERT_EMAIL}` for the following events: SCP failures or partial transfers, backup/import successes and failures, disk utilization threshold breaches, archive (tar) failures, and cleanup failures or cancellations.

---

## Git Workflow

### Development Workflow

All changes follow a promotion pipeline: **feature branch → dev → qa → uat → main**.

1. Create a feature branch off `dev`:
   ```bash
   git checkout dev
   git checkout -b my-feature
   ```

2. Make changes, then use `git_push.sh` to commit and promote through each environment:
   ```bash
   ./scripts/git_push.sh dev     # merge into dev
   ./scripts/git_push.sh qa      # promote to QA after testing
   ./scripts/git_push.sh uat     # promote to UAT after QA approval
   ./scripts/git_push.sh main    # promote to production (password required)
   ./scripts/git_push.sh skip    # skip straight to prod — merges into all environments (password required)
   ```

### git_push.sh — Automated Push and Merge

Located at `scripts/git_push.sh`. Automates staging, committing, pushing, and merging the current branch into a target environment. Pushing to `main` requires password authentication as a safeguard against accidental production deployments.

**Usage:**
```bash
./scripts/git_push.sh <environment>
```

**Environments:** `dev`, `qa`, `uat`, `main`, `skip`

**What it does:**
1. Prompts for a commit message
2. Stages all changes and commits to the current branch
3. Pushes the current branch to origin
4. Checks out the target environment branch
5. Merges the current branch into it
6. Pushes the target branch to origin
7. Returns to the original branch

**Production protection:** Merging into `main` requires a password prompt. Unauthorized users are blocked from pushing to production.

**Skip mode:** The `skip` option bypasses the normal promotion pipeline and merges the current branch sequentially into all environments (`dev` → `qa` → `uat` → `main`) in a single run. This is intended for hotfixes or urgent changes that need to reach production immediately. Requires the same password authentication as a direct `main` push.

---

## Repository Structure

```
Control-Script_SH/
├── README.md
├── .gitignore
├── control_exec/
│   ├── CONTROL_SCRIPT_SHELL_v1.0.sh
│   ├── CONTROL_SCRIPT_SHELL_v1.1.sh
│   ├── ...
│   └── CONTROL_SCRIPT_SHELL_v1.19.sh
├── scripts/
│   └── git_push.sh
├── lists/
├── logs/
└── misc/
```

---

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Current production code (v1.19) |
| `dev` | Development environment |
| `qa` | Quality assurance environment |
| `uat` | User acceptance testing environment |
| `v1.0` — `v1.19` | Version snapshots |

---

## Security

The following items are excluded from version control via `.gitignore`:

```
*.pem
*.key
*.dmp
*.log
*.tar
*.par
*.lst
*.env
wallet/
tnsnames.ora
sqlnet.ora
```

**Never commit credentials or private keys.** All sensitive values are externalized into environment variables (`DB_USER`, `DB_PASS`, `PEM_KEY`, `ALERT_EMAIL`) sourced from a local credentials file that is not tracked by Git.

---

## Version History

| Version | Description |
|---------|-------------|
| v1.0 | Initial release — basic backup function |
| v1.8 | Added database backup with Data Pump export |
| v1.10 | Added disk utilization monitoring |
| v1.12 | Added SCP with cloud/on-prem detection |
| v1.13 | Added database import and local migration |
| v1.18 | Added cloud migration with remote script generation |
| v1.19 | Current production — full CLI support, menu-driven interface, email alerting |

---

## License

Internal use only.

