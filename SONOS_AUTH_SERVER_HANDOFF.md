# Sonos Auth Server Handoff

This app uses the hosted OAuth broker at `https://sonos-auth.alania-bonn.de`.
The macOS app does not store a Sonos client secret and does not expect the user
to copy tokens manually.

## Current Client Flow

1. The app calls `GET /health`.
2. The app calls `POST /oauth/start`.
3. The server returns:

```json
{
    "login_id": "opaque-session-id",
    "authorization_url": "https://api.sonos.com/login/v3/oauth/authorize?...",
    "expires_in": 600
}
```

4. The app opens `authorization_url` in the system browser.
5. The app polls `GET /oauth/status/{login_id}` until the server reports a
   terminal state.
6. When status is `complete`, the app calls `POST /token` with:

```json
{
    "login_id": "opaque-session-id"
}
```

7. The app stores the returned Sonos access token and broker session id in
   macOS Keychain.

## Required Server Behavior

### `GET /health`

Return HTTP 200 when the broker is reachable.

```json
{
    "status": "ok",
    "oauth_configured": true
}
```

### `POST /oauth/start`

Create a short-lived login session and return a Sonos authorization URL.

The authorization URL must include a Sonos OAuth `state` value that lets the
server map the callback back to this `login_id`.

### `GET /oauth/status/{login_id}`

Return one of these statuses:

```json
{
    "status": "pending",
    "created_at": "2026-08-19T17:42:00Z",
    "completed_at": null,
    "error": null
}
```

```json
{
    "status": "complete",
    "created_at": "2026-08-19T17:42:00Z",
    "completed_at": "2026-08-19T17:42:21Z",
    "error": null
}
```

```json
{
    "status": "failed",
    "created_at": "2026-08-19T17:42:00Z",
    "completed_at": "2026-08-19T17:42:21Z",
    "error": "human readable error"
}
```

### `GET /oauth/callback`

Sonos redirects the browser here after the user allows access.

The server must:

1. Validate `state`.
2. Exchange the Sonos authorization `code` for tokens server-side.
3. Persist token/session data for the matching `login_id`.
4. Mark the login session as `complete`.
5. Return a final browser response immediately.

A minimal final response is enough:

```html
<!doctype html>
<meta charset="utf-8">
<title>Sonos verbunden</title>
<p>Sonos ist verbunden. Dieses Fenster kann geschlossen werden.</p>
```

Do not leave the browser request waiting while the app polls. If the browser
keeps showing the Sonos loading spinner after approval, the problem is usually
that `/oauth/callback` is not returning a final HTML response or redirect after
the token exchange.

### `POST /token`

Accept the app request:

```json
{
    "login_id": "opaque-session-id"
}
```

Return:

```json
{
    "access_token": "sonos-access-token",
    "expires_in": 3600,
    "token_type": "Bearer",
    "broker_session_id": "optional-stable-session-id"
}
```

The app accepts `expires_in` in seconds or `expires_at` as a Unix timestamp.
If the response includes a `broker_session_id`, the app saves it and sends
it as `login_id` for subsequent requests. Otherwise it uses the original ID.

Keep the authorized session and its Sonos refresh token available after the
browser login window expires and across server restarts. When the access token
expires, use the stored refresh token and persist any replacement returned by
Sonos. Return `401`, `404`, or `410` when the session is invalid or gone.
Use `429` with `Retry-After` for throttling and a `5xx` response for temporary
service failures so the app can retry with the stored session.

## Manual Checks

```bash
curl -i https://sonos-auth.alania-bonn.de/health
curl -i -X POST https://sonos-auth.alania-bonn.de/oauth/start
curl -i https://sonos-auth.alania-bonn.de/oauth/status/<login_id>
```

For callback debugging, inspect server logs around:

- missing or mismatched `state`
- Sonos token exchange failures
- callback handler waiting instead of responding
- session not being marked `complete`

## App-Side Notes

- The app no longer uses SwiftUI `.onOpenURL`; URL callbacks are handled via
  `NSAppleEventManager`.
- The app expects normal OAuth completion through polling, not direct custom URL
  scheme handoff.
- Users should only need to click "Mit Sonos verbinden", log in once, and return
  to the menu bar app.
