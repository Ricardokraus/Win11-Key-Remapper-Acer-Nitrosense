# Security policy

## Supported versions

Only the [latest release](https://github.com/Ricardokraus/Win11-Key-Remapper/releases/latest)
gets fixes. The app can update itself (Settings → General → *Check now*).

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them
privately through GitHub instead:
[**Report a vulnerability**](https://github.com/Ricardokraus/Win11-Key-Remapper/security/advisories/new)
(Security tab → *Report a vulnerability*).

Include what you found, how to reproduce it and which version you used. You'll
get an answer as soon as possible; once a fix is released, the report can be
published as a security advisory with credit to you, if you want.

## What this app does that matters for security

- It installs a low-level keyboard hook (`WH_KEYBOARD_LL`) to see key presses.
  Keys are only compared against your settings; nothing is logged, stored or
  sent anywhere.
- It runs without admin rights and never asks for elevation.
- Its only network access is the update check against GitHub's API, and, when
  you choose to install an update, downloading the release zip from GitHub. The
  download is verified against the release's `SHA256SUMS.txt` before the exe is
  replaced.
