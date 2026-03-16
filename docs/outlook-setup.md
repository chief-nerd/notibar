# Outlook (Office 365) Setup

Notibar connects to Microsoft Graph API to fetch your Outlook mail counts. Authentication uses OAuth 2.0 with PKCE — no client secret is needed.

## 1. Register an Azure App

1. Go to the [Azure App Registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) page and sign in
2. Click **New registration**
3. Fill in the form:
   - **Name**: `Notibar` (or any name you prefer)
   - **Supported account types**: Choose based on your needs:
     - *Single tenant* — only your organization
     - *Multitenant* — any Azure AD directory
     - *Personal Microsoft accounts* — Outlook.com, Hotmail, etc.
   - **Redirect URI**: Select **Public client/native (mobile & desktop)** and enter `http://localhost` (the port is assigned dynamically at runtime)
4. Click **Register**

## 2. Note Your IDs

After registration, you'll land on the app's **Overview** page. Copy these two values:

| Field                       | Where to find it                                                      |
| --------------------------- | --------------------------------------------------------------------- |
| **Application (client) ID** | Overview page, top section                                            |
| **Directory (tenant) ID**   | Overview page, top section. Use `common` if you selected multitenant. |

## 3. Configure API Permissions

1. In the left sidebar, click **API permissions**
2. Click **Add a permission** → **Microsoft Graph** → **Delegated permissions**
3. Add the following permissions:
   - `Mail.Read` — read your mailbox
   - `openid` — sign in
   - `profile` — read your basic profile
   - `offline_access` — maintain access (refresh tokens)
4. Click **Add permissions**
5. If you see a banner about admin consent, click **Grant admin consent** (requires admin rights; if you're using a personal account this step is automatic)

## 4. Configure in Notibar

1. Open Notibar settings (click ⚙ in the menu bar → Settings)
2. Go to the **Accounts** tab and click **Add Account**
3. Select **Outlook** as the service type
4. Enter:
   - **Name**: A display name (e.g., "Work Email")
   - **Client ID**: The Application (client) ID from step 2
   - **Tenant ID**: The Directory (tenant) ID from step 2, or `common`
5. Click **Sign In** — your browser will open the Microsoft login page
6. After signing in, the token is saved automatically

## 5. Add Notification Options

Once the account is added:

1. Switch to the **Notifications** tab
2. Click **Add** and select your Outlook account
3. Choose a metric:
   - **Unread** — count of unread emails
   - **Flagged** — count of flagged emails
4. The new item appears in the menu bar immediately

## Troubleshooting

| Problem                          | Solution                                                                                                                                |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Login page doesn't open**      | Check that your default browser is set and working                                                                                      |
| **"AADSTS700054" error**         | The redirect URI doesn't match. Ensure `http://localhost` is listed under **Authentication → Mobile and desktop applications** in Azure |
| **401 after token expires**      | Click the account in Settings and sign in again. Future versions will support refresh tokens automatically                              |
| **0 counts despite having mail** | Verify `Mail.Read` permission is granted and admin consent was given                                                                    |

## Scopes Used

| Scope            | Purpose                       |
| ---------------- | ----------------------------- |
| `openid`         | Required for OIDC sign-in     |
| `profile`        | Read basic user profile       |
| `offline_access` | Obtain refresh tokens         |
| `Mail.Read`      | Read mail messages and counts |
