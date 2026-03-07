# Google Drive Sync Tool (gdrive-sync)

An interactive, systemd-based tool to sync multiple local folders to Google Drive using `rclone`.

## 1. How `rclone` Works for Google Drive

Google Drive does not use traditional file paths; it uses unique IDs for every file and folder. If you try to upload a file named `backup.tar.gz` 5 times to the same folder, Google Drive will create 5 separate files with the exact same name.

**`rclone`** bridges this gap. It acts as a translator:
- It maintains a mapping of standard file paths (`/backups/db`) to Google Drive IDs.
- When running a sync (`rclone sync`), it computes hashes (MD5) and checks modification times.
- If a file exists with the same name and hash, it skips it.
- If a file is modified, it updates the existing Drive ID instead of creating a duplicate.
- It seamlessly handles rate-limiting and Google Drive API quotas.

## 2. Requirements

To make this work seamlessly on a headless Linux server, we need:
1. **The `rclone` binary**: Installed via `apt` or official install script.
2. **A Google Service Account JSON Key**: Just like the GCS tool, this provides non-interactive authentication.
3. **An Rclone Configuration File (`rclone.conf`)**: This defines the "remote" connection to Google Drive, mapping the JSON key to a drive alias (e.g., `gdrive:`).
4. **Google Drive Folder Sharing**: A Service Account has its own invisible Drive. To sync to your *personal* or *workspace* Drive, you must create a folder in your Drive (e.g., `Server Backups`), click "Share", and grant the Service Account's email address `Editor` access. The tool will then be configured to sync into this shared folder.

## 3. The Flow (How it will work)

### Phase A: Installation & Setup (`install.sh`)
1. **Install Dependencies**: Install `rclone` (and unzip/curl if missing).
2. **Authenticate**: Prompt the user to drop their Service Account `.json` key in the project root.
3. **Configure Rclone**: Automatically generate an `rclone.conf` file that points to Google Drive using the provided JSON key.
4. **Target Drive Folder**: Ask the user for the Google Drive Folder ID (or path) that was shared with the Service Account.
5. **Install Service & CLI**: Install the background `systemd` service and the interactive `gdrivesync` CLI tool.

### Phase B: The Sync Daemon (`systemd` + `sync_to_gdrive.sh`)
1. **The Service (`gdrivesync.service`)**: Runs in the background as the `www-data` user (to maintain web-server permission parity).
2. **The Script**: A lightweight bash script that reads the configured folder pairs (e.g., `/var/www/html/data` → `gdrive:/Server Backups/data`).
3. **The Execution**: Runs `rclone rsync --update` (or `sync` for exact mirroring) on a loop based on the configured interval. Logs output to `/var/log/gdrivesync/gdrivesync.log`.

### Phase C: The Management CLI (`gdrivesync`)
An interactive dashboard (just like `gcssync`) to:
- Add / Remove folder pairs
- Start, Stop, and Restart the daemon
- View live sync logs
- Trigger an immediate manual sync

## 4. Key Differences from GCS Sync
- Instead of using `gsutil`, we use `rclone`.
- GCS relies solely on the `export GOOGLE_APPLICATION_CREDENTIALS` environment variable. `rclone` requires an explicit `--config /etc/gdrive/rclone.conf` file.
- We must emphasize sharing a Google Drive folder with the Service Account email, otherwise the files will upload successfully but remain "invisible" to the human user!
