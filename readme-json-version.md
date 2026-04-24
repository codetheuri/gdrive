# Google Drive Sync Tool (Service Account JSON Method)

This is an alternative method to sync Linux servers to Google Drive using a Service Account JSON file.

### ⚠️ Critical Warning for JSON Service Accounts
By default, Google Service Accounts have **0 bytes of storage quota** on consumer Google Drive (`@gmail.com`). 
If you try to upload files directly into a folder shared with a Service Account, Google will immediately reject the upload with a `storageQuotaExceeded` error because the Service Account is technically the "owner" of the newly uploaded file.

### How to use the JSON method successfully:
To bypass the 0-byte restriction, you **MUST** have a paid **Google Workspace ($6/mo custom domain)** account.
You must use **Domain-Wide Delegation** to allow the Service Account to "impersonate" a real user (meaning you own the file, and your unlimited quota is used).

#### 1. Setup in Google Cloud & Google Workspace
1. Create a Service Account in Google Cloud and download the JSON key.
2. In Google Cloud, edit the Service Account, look under "Advanced Settings", and copy the **Client ID** string.
3. Go to your Google Workspace Admin Console (`admin.google.com`).
4. Navigate to **Security → API Controls → Manage Domain Wide Delegation**.
5. Click **Add New**. Paste your Service Account's Client ID.
6. Under OAuth Scopes, add: `https://www.googleapis.com/auth/drive`
7. Click Authorize.

#### 2. Configure Rclone on your Server
Because `install.sh` on this branch is optimized for Web OAuth, if you want to use the JSON method manually, you must configure `/etc/gdrive/rclone.conf` to look exactly like this:

```ini
[gdrive]
type = drive
scope = drive
service_account_file = /path/to/your/service-account.json
impersonate = admin@yourcompany.com
```

*The `impersonate` flag tells the bot to pretend to be you, bypassing its own 0-byte limit and successfully uploading files into your Google Workspace Drive.*
