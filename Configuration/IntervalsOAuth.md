# Intervals.icu sign in configuration

End users tap **Connect Intervals.icu**, sign in on Intervals.icu's page, and approve activity access. The iOS app uses Apple's authentication browser and exchanges an authorization code with S256 PKCE. It does not collect a password or require an API key. No app server or client secret is needed for an approved public client.

The app owner completes registration once:

1. Apply at [Intervals.icu OAuth application registration](https://intervals.icu/oauth/apply) using the account that should own FTPunk.
2. Register the exact redirect URI `ftpunk://oauth/intervals`.
3. Mark the application as a **public client** and enable **Require PKCE**.
4. Request `ACTIVITY:WRITE` for completed activity uploads. This application does not request wellness, profile-setting, or calendar modification permissions.
5. Wait for Intervals.icu approval. Its documentation says pending applications cannot complete the OAuth flow.
6. Set the public client ID using the `INTERVALS_OAUTH_CLIENT_ID` Xcode build setting. For the locally packaged Mac app or standalone preview, set the `FTPUNK_INTERVALS_CLIENT_ID` environment variable before launch. The client ID is public configuration, not a user credential.

The current repository leaves the client ID empty deliberately. The primary connection button shows that registration is pending; it does not pretend to be connected or redirect to an unregistered application. No application has been submitted on the owner's behalf.

The app validates the callback route, a fresh random state value, single code/state parameters, the token type, and the granted upload permission. Tokens stay in Keychain; uploads use Bearer authorization. Disconnect clears local credentials and jobs and attempts online token revocation. Existing private API-key connections remain readable for migration, and API-key connection is also available to all users under Settings → Connect with an API key, independently of debug mode. Every new activity upload requires rider/destination confirmation.

The protocol and request construction have automated tests. Live authentication and upload need an approved application and an authorized account. See the [official OAuth documentation](https://forum.intervals.icu/t/intervals-icu-oauth-support/2759).
