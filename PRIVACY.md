# Privacy Policy

Last updated: 2026-10-12

This app is a [fwknop](https://www.cipherdyne.org/fwknop/) Single Packet
Authorization (SPA) client. It has no account system, no analytics, no crash
reporting, no advertising, and no server operated by the developer. Nothing is
sold or shared with data brokers.

## What is stored on your device

Server profiles you create — including the `KEY` and `HMAC_KEY` copied from
your `fwknopd` server's `access.conf` — are stored only on your device, in
encrypted platform storage:

- **Android:** Android Keystore-backed encrypted storage (AES-GCM).
- **iOS:** Keychain, marked non-migratable and not synchronized to iCloud
  Keychain.

These secrets are never transmitted to the developer or to any third party.
Cloud backup and device-to-device transfer of app data are disabled, so your
keys are not uploaded to a cloud backup. Uninstalling the app removes them.

Because the keys are device-bound, they cannot be recovered by the developer.
If you lose the device or uninstall the app, re-enter the keys from your
server's `access.conf`.

## What is sent over the network

The app makes two kinds of network request.

**1. Public IP resolution (third parties).** When "Auto-resolve source IP" is
enabled — the default for new profiles — the app queries a public IP echo
service to learn your current public IP address before sending a packet:

- `https://api.ipify.org`
- `https://icanhazip.com` (used only if the first request fails)

These services are operated by third parties and will see your IP address plus
ordinary HTTPS request metadata (timestamp, user agent) in their server logs.
The app's maintainer has no relationship with, and no access to, those logs.
Disable "Auto-resolve source IP" in a profile and enter a source IP manually to
avoid contacting these services entirely.

**2. The SPA packet (your server only).** The authorization packet is sent
directly, over UDP, to the server hostname and port you configured. It is
encrypted with your `KEY` and authenticated with your `HMAC_KEY`, and contains
your source IP, the access request (e.g. `tcp/22`), a timestamp, and — only if
you filled them in — a username, NAT access target, and firewall timeout. Your
server's `fwknopd` logs this event. No copy goes anywhere else.

The app also performs DNS resolution of the server hostname you entered, which
your configured DNS resolver will see.

## Permissions

The app requests only the `INTERNET` permission on Android. It does not request
contacts, location, storage, camera, or microphone access. Note that the source
IP placed in an SPA packet is by nature a network address; it is not collected,
stored on any server, or used for tracking.

## Children

The app is not directed at children and collects no personal data beyond what is
described above.

## Changes

If this policy changes, the "Last updated" date above will change and the app
will be updated accordingly.

## Contact

Questions about this policy should be raised on the project's issue tracker.
