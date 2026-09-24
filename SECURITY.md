# Security Policy

MysticJam is a local-only desktop app with no accounts, no server, and no
telemetry — most of what a security policy usually covers (account
takeover, server-side data exposure) doesn't apply here. This still covers
things like malicious file parsing, unsafe local IPC, or unsafe handling of
the one network call the app makes (the optional lyrics lookup).

## Supported versions

There isn't a versioned release yet — the `main` branch is the only
supported line. Security fixes land there.

## Reporting a vulnerability

Please open a [GitHub issue](https://github.com/MysticYewXd/MysticJam/issues)
or contact the maintainer directly rather than disclosing publicly first if
the issue is serious (e.g. something that could run arbitrary code or leak
local files). Include:

- What you found and why it's a security issue, not just a bug.
- Steps to reproduce it.
- The affected version/commit.

There's no bug bounty — this is a hobby project — but reports are taken
seriously and credited unless you'd rather stay anonymous.
