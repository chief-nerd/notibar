# GitHub Setup

Notibar uses the GitHub REST API to show notification counts — unread notifications, assigned issues, assigned PRs, and review requests.

## 1. Create a Personal Access Token

1. Go to [GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta)
2. Click **Generate new token**
3. Fill in:
   - **Token name**: `Notibar`
   - **Expiration**: Choose a duration (90 days or custom)
   - **Repository access**: Select **All repositories** (or specific repos if you only want notifications from some)
4. Under **Permissions**, grant:
   - **Notifications** — Read-only
   - **Issues** — Read-only
   - **Pull requests** — Read-only
5. Click **Generate token**
6. **Copy the token immediately** — you won't be able to see it again

### Classic Token Alternative

If you prefer a classic token:

1. Go to [Personal access tokens (classic)](https://github.com/settings/tokens)
2. Click **Generate new token (classic)**
3. Select scopes:
   - `notifications`
   - `repo` (needed for private repo issues/PRs)
4. Generate and copy the token

## 2. Configure in Notibar

1. Open Notibar settings (⚙ → Settings)
2. Go to the **Accounts** tab → **Add Account**
3. Select **GitHub** as the service type
4. Enter:
   - **Name**: A display name (e.g., "GitHub Work")
   - **API Key**: Paste your personal access token
   - **Endpoint** (optional): Leave blank for github.com, or enter your GitHub Enterprise URL (e.g., `https://github.example.com/api/v3`)
5. Save the account

## 3. Add Notification Options

Switch to the **Notifications** tab and add items for your GitHub account:

| Metric              | What it shows                           |
| ------------------- | --------------------------------------- |
| **Unread**          | Unread notification count               |
| **Mentions**        | Notifications where you were @mentioned |
| **Assigned Issues** | Open issues assigned to you             |
| **Assigned PRs**    | Open pull requests assigned to you      |
| **Review Requests** | PRs where your review is requested      |

## 4. GitHub Enterprise

For GitHub Enterprise Server:

1. Set the **Endpoint** to your instance's API base URL:
   ```
   https://github.yourcompany.com/api/v3
   ```
2. Create a token on your Enterprise instance (same steps as above)
3. Ensure the token has the same scopes

## Troubleshooting

| Problem                    | Solution                                                                            |
| -------------------------- | ----------------------------------------------------------------------------------- |
| **401 Unauthorized**       | Token expired or was revoked. Generate a new one.                                   |
| **0 counts everywhere**    | Check token scopes — `notifications` and `repo` are both needed for full visibility |
| **Enterprise not working** | Verify the endpoint URL ends with `/api/v3` and is reachable from your network      |
| **Rate limiting**          | GitHub allows 5,000 requests/hour. Increase the polling interval if you hit limits. |

## API Endpoints Used

| Endpoint                                            | Purpose                         |
| --------------------------------------------------- | ------------------------------- |
| `GET /notifications`                                | Fetch unread notification count |
| `GET /issues?assignee=@me`                          | Count assigned issues           |
| `GET /search/issues?q=type:pr+assignee:@me`         | Count assigned PRs              |
| `GET /search/issues?q=type:pr+review-requested:@me` | Count review requests           |
