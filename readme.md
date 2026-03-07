# Google Drive Sync Tool (`gdrive`)

An interactive, systemd-based Linux tool to seamlessly sync multiple local server folders directly to your personal Google Drive using `rclone`.

---

## 🚀 Key Features
* **No 0-Byte Limits:** Bypasses the strict Google Drive Service Account storage quota by authenticating directly with your personal/workspace Google Account via Web OAuth.
* **Root Permissions:** Runs as `root` in the background, ensuring it has permission to sync heavily restricted folders (like `/etc/letsencrypt/archive` or `/var/lib/docker`).
* **Error Interception:** Extracts and logs exact files that failed to sync natively to a readable dashboard log.
* **Interactive CLI (`gdrive`)**: A beautiful, menu-driven interface to add folders, check status, and watch live upload streams.

---

## 🛠️ How to Install & Authenticate

Because Google strictly blocks headless servers from generating copy-paste OAuth tokens locally, you must use your personal computer (Windows/Mac) to generate the token, and then paste it into your server.

### Step 1: Generate the Token (On your Personal Computer)
1. Download `rclone` to your local computer: [rclone.org/downloads](https://rclone.org/downloads/)
2. Extract the file, open a Command Prompt / Terminal inside the extracted folder.
3. Run this exact command:
   ```bash
   rclone authorize "drive"
   ```
4. Your web browser will open. Log into the Google Account holding the destination Google Drive.
5. Your terminal will print out a massive secret code block shaped like JSON:
   ```json
   {"access_token":"ya29.a0AWY7C...","token_type":"Bearer", ...}
   ```
6. **Copy that entire JSON block.**

### Step 2: Install on the Server
1. Clone this repository to your Linux server and navigate into the folder.
2. Run the interactive installer:
   ```bash
   sudo ./install.sh
   ```
3. When prompted, **paste the JSON block** you copied from your computer.
4. The script will automatically link to your Google Drive, fetch a list of your shared or root folders, and ask you to map your first local folder!

---

## 🕹️ The Management CLI (`gdrive`)

Once installed, you can manage your background Google Drive Sync daemon from anywhere on the server by running:
```bash
sudo gdrive
```

**Dashboard Features:**
* **[1-3] Service Controls:** Start, Stop, and Restart the `gdrive.service` system daemon.
* **[4] View Live Logs:** Tracks real-time `rclone` upload outputs and prints exact failure reasons if a file gets blocked.
* **[5] Add Sync Pair:** Maps a new local absolute path (e.g., `/var/www/html`) to a folder on your Google Drive.
* **[6] Remove Sync Pair:** Deletes an existing mapping.
* **[7] Run Manual Sync:** Bypasses the sleep timer and aggressively forces an immediate sync of all configured folders.

---

## ⚙️ Architecture under the hood

1. **`/etc/gdrive/rclone.conf`**: Holds your secure Web OAuth token.
2. **`/usr/local/bin/sync_to_gdrive.sh`**: The core sync engine that loops your mapped folders. Runs `rclone copy` (safe mode) or `rclone sync` (strict mirror mode) based on your installation preference.
3. **`gdrive.service`**: The strict Systemd daemon that boots on startup, runs as `root`, sets the working directory to `/var/www`, and executes the engine.
4. **`/var/log/gdrive/gdrive.log`**: Standard output and standard error target for all background sync operations.
