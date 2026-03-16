# Slack Setup

Notibar can show unread message counts and mention counts from Slack workspaces.

## 1. Create a Slack App

1. Go to [Slack API — Your Apps](https://api.slack.com/apps)
2. Click **Create New App** → **From scratch**
3. Enter:
   - **App Name**: `Notibar`
   - **Workspace**: Select your workspace
4. Click **Create App**

## 2. Configure Bot Token Scopes

1. In the left sidebar, click **OAuth & Permissions**
2. Scroll to **Scopes → Bot Token Scopes** and add:
   - `channels:read` — view basic channel info
   - `groups:read` — view basic private channel info
   - `im:read` — view basic DM info
   - `mpim:read` — view basic group DM info
   - `users:read` — view user info

> **Note:** To count unread messages, the app needs read access to conversations you're a member of.

## 3. Install the App

1. Scroll to the top of **OAuth & Permissions**
2. Click **Install to Workspace**
3. Review the permissions and click **Allow**
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

### Alternative: User Token

If you need access to your personal unread counts across all channels (not just those the bot is in), use a **User Token** instead:

1. Under **User Token Scopes**, add the same scopes listed above
2. After installing, copy the **User OAuth Token** (starts with `xoxp-`)

## 4. Configure in Notibar

1. Open Notibar settings (⚙ → Settings)
2. Go to the **Accounts** tab → **Add Account**
3. Select **Slack** as the service type
4. Enter:
   - **Name**: A display name (e.g., "Slack Work")
   - **API Key**: Your Bot or User OAuth token
5. Save the account

## 5. Add Notification Options

Available metrics for Slack:

| Metric       | What it shows                              |
| ------------ | ------------------------------------------ |
| **Unread**   | Total unread messages across all channels  |
| **Mentions** | Messages where you were @mentioned or DMed |

## Troubleshooting

| Problem           | Solution                                                                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **invalid_auth**  | Token is invalid or expired. Reinstall the app and get a new token.                                                                                  |
| **missing_scope** | The token doesn't have the required scopes. Add them in the app settings and reinstall.                                                              |
| **0 counts**      | If using a bot token, the bot only sees channels it's been invited to. Use a user token for full visibility, or invite the bot to relevant channels. |
| **Can't see DMs** | DM counts require `im:read` scope and a user token.                                                                                                  |

## API Endpoints Used

| Endpoint                       | Purpose                                   |
| ------------------------------ | ----------------------------------------- |
| `GET /api/conversations.list`  | List channels the user/bot is a member of |
| `GET /api/conversations.info`  | Get unread count for a specific channel   |
| `GET /api/users.conversations` | List user's conversations                 |
