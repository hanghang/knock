# Prompt source

## Request (2026)
> Build this app (per AGENTS.md)

## Requirements (from AGENTS.md + conversation)
Build a Flutter cross-platform **fwknop Single Packet Authorization (SPA) client**:

1. Sends an encrypted SPA packet (UDP, default port 62201) to a fwknop server
   to open firewall access (e.g. `tcp/22` for the client's source IP).
2. Implements the libfko protocol natively in Dart (no unmaintained FFI):
   - Encoded message: `rand16 : b64(username) : timestamp : version(3.0.0) :
     msg_type : b64(access_msg) [: b64(nat_access)] [: client_timeout]`
   - `access_msg` = `source_ip,proto/port`
   - Digest (SHA256, base64 w/o `=`) appended, then AES-256-CBC encrypted
     OpenSSL-compatible (EVP_BytesToKey/MD5, random salt, "Salted__" prefix,
     PKCS7, base64 w/o padding).
   - Optional HMAC-SHA256 over the ciphertext (encrypt-then-MAC), appended.
3. UI: manage server profiles (host, port, key, HMAC key, access request,
   source IP auto-resolve or manual, NAT access, timeout), persisted locally;
   one tap to send the SPA packet.
4. Reference: https://www.cipherdyne.org/fwknop/docs/fwknop-tutorial.html,
   protocol source of truth: github.com/mrash/fwknop (lib/).
