# Jira Setup

Notibar connects to Jira Cloud or Jira Server/Data Center to show counts of issues assigned to you.

## 1. Generate an API Token

### Jira Cloud

1. Go to [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click **Create API token**
3. Give it a label (e.g., `Notibar`)
4. Click **Create** and **copy the token**

### Jira Server / Data Center

1. Click your profile avatar → **Personal Access Tokens**
2. Click **Create token**
3. Enter a name and optionally set an expiry
4. Click **Create** and copy the token

## 2. Configure in Notibar

1. Open Notibar settings (⚙ → Settings)
2. Go to the **Accounts** tab → **Add Account**
3. Select **Jira** as the service type
4. Enter:
   - **Name**: A display name (e.g., "Jira Work")
   - **Endpoint**: Your Jira instance URL
     - Cloud: `https://yourcompany.atlassian.net`
     - Server: `https://jira.yourcompany.com`
   - **API Key**: Your API token
5. For **Jira Cloud**, also add your email in the account config:
   - Key: `email`
   - Value: Your Atlassian account email (used for Basic auth)

## 3. Add Notification Options

Available metrics for Jira:

| Metric              | What it shows                               |
| ------------------- | ------------------------------------------- |
| **Assigned Issues** | Open issues assigned to you                 |
| **Mentions**        | Issues where you were mentioned in comments |
| **Unread**          | Issues updated since your last visit        |
| **All**             | Total open issues in your assigned queue    |

## 4. Authentication Details

### Jira Cloud

Jira Cloud uses **Basic Authentication** with your email and API token:

```
Authorization: Basic base64(email:api_token)
```

Make sure the email in your account config matches your Atlassian account email.

### Jira Server / Data Center

Jira Server uses the **Personal Access Token** directly:

```
Authorization: Bearer <token>
```

No email config is needed for Server/Data Center.

## Troubleshooting

| Problem              | Solution                                                                                                                            |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **401 Unauthorized** | Check that your email and API token are correct. For Cloud, ensure the email matches your Atlassian account.                        |
| **403 Forbidden**    | Your account may lack permissions to access the Jira REST API. Contact your Jira admin.                                             |
| **Endpoint errors**  | Make sure the URL doesn't have a trailing slash. Use `https://yourcompany.atlassian.net`, not `https://yourcompany.atlassian.net/`. |
| **Token expired**    | Generate a new token and update the account in Settings.                                                                            |

## API Endpoints Used

| Endpoint                                                                      | Purpose                        |
| ----------------------------------------------------------------------------- | ------------------------------ |
| `GET /rest/api/2/search?jql=assignee=currentUser() AND resolution=Unresolved` | Count assigned open issues     |
| `GET /rest/api/2/search?jql=...`                                              | Various JQL queries per metric |
