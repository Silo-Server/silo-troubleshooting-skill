# Reporting a bug to the Silo project

Use this when the evidence points at a Silo bug rather than configuration, or
when a fix would need a risky manual change. Draft the report for the user.
**Never submit it yourself.** The user reviews, edits, and files it.

## Where

- Bugs: <https://github.com/Silo-Server/silo-server/issues/new/choose>, using
  the **Bug report** form. Blank issues are disabled.
- Questions and "is this expected?": the Silo Discord, <https://discord.gg/siloserver>.
- Plugin bugs go to that plugin's own repository when it has one.

## What the bug form asks for

- **What happened**: what the user observed, in their words.
- **Steps to reproduce**: steps the user actually ran on their server.
- **Expected behavior**.
- **Silo version / commit**: from the admin sidebar footer or
  `GET /api/v2/admin/system/build`, or the image tag from
  `docker compose images silo`.
- **Deployment**: Docker Compose, Unraid, Kubernetes, or other; single server
  or with separate nodes; GPU type.
- **Clients affected**.
- **Relevant logs**: raw server log lines, with redactions marked.
- **Technical notes**: your analysis, kept separate from what was observed.
- **AI disclosure**: the Silo project requires the exact agent harness, tool,
  and model identifier, and the level of AI involvement. Fill these in
  honestly (for example harness "Claude Code", model the exact ID you are
  running as). A report that hides AI use gets closed.

## Rules that get reports accepted

- Only include what actually happened. Never invent log lines, steps, or
  results. The project blocks contributors for fabricated evidence, even on a
  first offence.
- Keep observations and guesses apart. Put your diagnosis under **Technical
  notes**, not in **What happened**.
- Quote log lines exactly. Redact by replacing the value and marking it, for
  example `[REDACTED-IP]`, and leave the rest of the line unchanged.

## Redact before anything leaves the machine

Remove or replace:

- `SECRET_KEY`, database passwords, `DATABASE_URL`, `REDIS_URL`, API keys,
  access tokens, cookies, and `Authorization` headers.
- Public hostnames, domain names, public IP addresses, and Tailscale names.
- Usernames and email addresses of household members.
- Media file names and paths, if the user considers them private.

Never paste the output of `docker compose config`, `docker inspect`, `env`,
`printenv`, or a `.env` file, even redacted. Describe the relevant setting
instead ("`DATABASE_URL` points at an external PostgreSQL 17 server").

## Client diagnostics

The Silo apps can send a diagnostics report to the user's own server. Admins
see these under **Admin > Diagnostics** and can download them. They stay on the
user's server unless the user chooses to share one.
