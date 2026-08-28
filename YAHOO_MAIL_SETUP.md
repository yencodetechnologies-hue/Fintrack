# Yahoo Mail Connect — Setup & Troubleshooting

Fintrack connects to Yahoo Mail using an **App Password + IMAP**, the same way it would work in any
third-party mail client. Yahoo no longer allows plain-password IMAP login for third-party apps, so a
one-time **App Password** has to be generated on the Yahoo account before connecting.

## How the connection works
- **Connect**: `POST /api/yahoo/connect-app-password` — verifies the email + app password against
  `imap.mail.yahoo.com:993` (real IMAP login), then stores the app password encrypted (AES-256-GCM via
  `backend/utils/tokenCrypto.js`, same helper used for Gmail's refresh token).
- **Sync**: `POST /api/yahoo/sync` — decrypts the stored app password, fetches inbox mail over IMAP
  (`backend/services/yahooImapService.js:fetchRealYahooInboxEmails`), and runs it through the same bank
  email parser Gmail sync uses.
- **Status / Disconnect**: `GET /api/yahoo/status`, `DELETE /api/yahoo/disconnect`.

In the app: **Profile → Connect Yahoo** opens a dialog asking for the Yahoo email + app password —
no browser, no OAuth redirect.

## How to generate a Yahoo App Password
1. Sign in at **account.yahoo.com** with the Yahoo account you want to connect.
2. Open **Account security** (account.yahoo.com/account/security).
3. Turn on **Two-step verification** if it isn't already on — Yahoo requires this before app passwords
   are offered.
4. Scroll to **App passwords** → **Generate app password** → name it (e.g. `Fintrack`).
5. Yahoo shows a 16-character password once — copy it immediately.
6. In Fintrack: Profile → Connect Yahoo → enter the Yahoo email + paste that app password (**not** the
   normal Yahoo login password) → Connect.

Each app password can be revoked independently from the same security page without touching the main
account password.

## Troubleshooting: "App passwords are not available for this account"
This is a Yahoo-side restriction, not a Fintrack bug. Common causes, roughly in order of likelihood:

1. **Two-step verification isn't actually turned on.** This is the most common cause — double-check the
   toggle is genuinely enabled, not just that the security menu is visible.
2. **Wrong account type.** App passwords only exist for plain personal Yahoo Mail accounts
   (`@yahoo.com`, `@ymail.com`, `@rocketmail.com`). They are **not** available for:
   - Yahoo Japan accounts (`@yahoo.co.jp`) — separate system entirely.
   - ISP-branded Yahoo-backed mail (`@att.net`, `@verizon.net`, `@sbcglobal.net`, etc.).
   - Yahoo Small Business / Yahoo Mail Plus accounts.
3. **Account has no Yahoo password set** — if the account only ever signs in via "Continue with
   Google/Apple/Facebook," there's no primary password for Yahoo to attach an app password to. A Yahoo
   password has to be set first.
4. **Very new account** — Yahoo sometimes blocks app-password generation for a short window on freshly
   created accounts as an anti-abuse measure.

### Suggested diagnosis order
1. Confirm two-step verification is genuinely on.
2. Check whether the account is one of the structurally-blocked types above (ISP domain / Yahoo Japan /
   Business).
3. If possible, test with a plain `@yahoo.com` account to confirm the Fintrack connect/sync flow itself
   works, independent of the account-specific restriction.

### If the account is structurally blocked
App Password + IMAP will never work for accounts in categories 2–3 above — there is no app password to
generate, ever. The only way to support those accounts would be to re-add a Yahoo OAuth connect flow
(previously implemented and removed from this project for being unreliable — browser callback issues,
double token exchange, missing mail scope, and a legacy Yahoo Mail REST API that isn't accessible to
third-party apps). That would need to be rebuilt properly (correct redirect domain, mail scope, IMAP+XOAUTH2
fetch instead of the old REST call) if this case turns out to matter for real users.
