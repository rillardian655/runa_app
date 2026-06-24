# Appwrite v1.9.0 Setup & Database Schema

## Task 1: Server Setup - Docker Installation

### VPS Details
- **IP Address**: `<SERVER_IP>`
- **Type**: NAT VPS (4GB RAM)
- **OS**: Ubuntu

### Docker Run Command for Appwrite v1.9.0

```bash
docker run -it --rm \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume "$(pwd)"/appwrite:/usr/src/code/appwrite:rw \
  --entrypoint="install" \
  appwrite/appwrite:1.9.0
```

### Port Configuration

Appwrite requires the following ports to be open on your VPS firewall:

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| **80** | HTTP | Nginx | Web console & API access (HTTP) |
| **443** | HTTPS | Nginx | Secure web console & API access (HTTPS) |
| **8080** | HTTP | Appwrite API | Direct API access (internal) |

> **Note for NAT VPS**: Since this is a NAT VPS, you may need to configure port forwarding from the host to your VPS. Ensure ports 80 and 443 are forwarded to your VPS internal IP. Contact your VPS provider's control panel to set up port forwarding if needed.

### Firewall Configuration (UFW)

```bash
# Allow SSH
sudo ufw allow 22/tcp

# Allow Appwrite web traffic
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable
```

### Post-Installation

After running the docker command, Appwrite will:
1. Create a `docker-compose.yml` file in the `appwrite` directory
2. Set up environment variables in `.env`
3. Start all required containers (Appwrite, MariaDB, Redis, etc.)

Access your Appwrite console at: `http://YOUR_VPS_IP`

---

## Task 2: Database Schema (TablesDB)

### Database Name: `runa_chat`

---

### Table 1: `users`

Stores user profiles and presence status.

| Column Name | Type | Size | Required | Default | Description |
|-------------|------|------|----------|---------|-------------|
| `user_id` | String | 255 | Yes | - | Appwrite Auth user ID (primary key) |
| `username` | String | 100 | Yes | - | Display name |
| `email` | Email | - | Yes | - | User email address |
| `avatar_url` | URL | - | No | null | Profile picture URL |
| `phone` | String | 20 | No | null | Phone number |
| `presence_status` | Enum | - | Yes | `offline` | Values: `online`, `offline`, `away`, `busy` |
| `last_seen` | DateTime | - | Yes | - | Last activity timestamp |
| `created_at` | DateTime | - | Yes | - | Account creation timestamp |
| `updated_at` | DateTime | - | Yes | - | Last profile update timestamp |

**Indexes:**
- `idx_presence_status` on `presence_status` (for filtering online users)
- `idx_last_seen` on `last_seen` (for sorting by activity)

---

### Table 2: `chats`

Tracks conversation participants (both 1:1 and group chats).

| Column Name | Type | Size | Required | Default | Description |
|-------------|------|------|----------|---------|-------------|
| `chat_id` | String | 255 | Yes | - | Unique chat identifier (primary key) |
| `chat_type` | Enum | - | Yes | - | Values: `direct`, `group` |
| `participants` | String (JSON Array) | 1000 | Yes | - | Array of user IDs: `["user1", "user2"]` |
| `group_name` | String | 100 | No | null | Group chat name (null for direct) |
| `group_avatar` | URL | - | No | null | Group avatar URL |
| `created_by` | String | 255 | Yes | - | User ID who created the chat |
| `last_message_at` | DateTime | - | No | null | Timestamp of most recent message |
| `created_at` | DateTime | - | Yes | - | Chat creation timestamp |
| `updated_at` | DateTime | - | Yes | - | Last update timestamp |

**Indexes:**
- `idx_participants` on `participants` (for finding user's chats)
- `idx_last_message_at` on `last_message_at` (for sorting chat list)

---

### Table 3: `messages`

Stores individual messages with Google Drive media references.

| Column Name | Type | Size | Required | Default | Description |
|-------------|------|------|----------|---------|-------------|
| `message_id` | String | 255 | Yes | - | Unique message identifier (primary key) |
| `chat_id` | String | 255 | Yes | - | Foreign key to `chats` table |
| `sender_id` | String | 255 | Yes | - | User ID of message sender |
| `content` | String | 5000 | No | null | Text content (null if media-only) |
| `message_type` | Enum | - | Yes | `text` | Values: `text`, `image`, `video`, `audio`, `file` |
| `media_drive_id` | String | 255 | No | null | **Google Drive File ID** for media assets |
| `media_url` | URL | - | No | null | Cached/thumbnail URL for quick display |
| `media_size` | Integer | - | No | null | File size in bytes |
| `media_duration` | Integer | - | No | null | Duration in seconds (audio/video) |
| `is_read` | Boolean | - | Yes | `false` | **Read receipt status** |
| `read_at` | DateTime | - | No | null | Timestamp when message was read |
| `created_at` | DateTime | - | Yes | - | Message sent timestamp |

**Indexes:**
- `idx_chat_id` on `chat_id` (for fetching chat messages)
- `idx_chat_created` on `chat_id`, `created_at` (for paginated message history)
- `idx_sender_id` on `sender_id` (for user message queries)
- `idx_is_read` on `is_read` (for unread message counts)

---

## Realtime Channels

Subscribe to these channels for real-time updates:

```dart
// Subscribe to new messages in a specific chat
client.subscribe(['databases.runa_chat.collections.messages.documents'], (event) {
  // Handle new message events
});

// Subscribe to presence updates
client.subscribe(['databases.runa_chat.collections.users.documents'], (event) {
  // Handle presence status changes
});
```

---

## Environment Variables

Add these to your Flutter app's configuration:

```dart
const String APPWRITE_ENDPOINT = 'http://YOUR_VPS_IP/v1';
const String APPWRITE_PROJECT_ID = 'your_project_id';
const String APPWRITE_DATABASE_ID = 'runa_chat';
const String USERS_COLLECTION_ID = 'users';
const String CHATS_COLLECTION_ID = 'chats';
const String MESSAGES_COLLECTION_ID = 'messages';
```
