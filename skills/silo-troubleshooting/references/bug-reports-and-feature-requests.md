# Drafting bug reports and feature requests

Use this when the evidence points at a bug in Silo rather than the user's
setup, when a fix would need a risky manual change, or when the user wants
something Silo does not do yet.

Your job is to **draft** the text. The user reviews it, edits it, and posts it
wherever they choose. Never file, post, comment, or react on the user's
behalf, and do not push them toward a particular place to post.

## Step 1: Decide which kind it is

- **Bug**: Silo does something wrong, crashes, or does not do what its own
  settings, UI, or documentation say. The user can make it happen again.
- **Feature request**: Silo works as designed, but the user wants it to do
  something it does not do today.
- **Neither**: a configuration problem you already fixed, or a question. No
  report needed; say so.

Check the feature against Silo's permanent non-goals before drafting. Silo will
not accept Live TV, OTA/DVB tuners, IPTV (M3U/Xtream), EPG/XMLTV guides, DVR,
or `.strm` remote-stream files, as core features or plugins. Tell the user
plainly and do not draft a request for these. The reasoning is in the Silo
repository's `docs/non-goals.md`. Silo's documentation suggests running
Jellyfin, Plex, or a dedicated tuner backend alongside Silo for live TV.

Audiobooks, ebooks, podcasts, and Audiobookshelf compatibility are beta. Bugs
there are still worth drafting; say in the draft that it concerns a beta
feature.

## Step 2: Check it is not already reported or being worked on

Always search before drafting. Search **open issues and open pull requests**
across every Silo repository, because the problem may belong to the server,
the Apple or Android app, or a plugin. Also glance at recently closed issues:
a fix may already exist in a newer build.

Search several ways: the exact error message (a distinctive fragment in
quotes), the feature or setting name, and plain-language synonyms ("GPU",
"hardware acceleration", "VAAPI", "QSV").

With the GitHub CLI (`gh`) installed:

```sh
gh search issues --owner Silo-Server --state open --limit 20 "hardware acceleration"
gh search prs    --owner Silo-Server --state open --limit 20 "hardware acceleration"
gh search issues --owner Silo-Server --state closed --sort updated --limit 10 "hardware acceleration"
```

Without it, the public search API covers issues and pull requests together
(unauthenticated searches are limited to a few per minute):

```sh
curl -s -G https://api.github.com/search/issues \
  --data-urlencode 'q=org:Silo-Server is:open "hardware acceleration"' \
  --data-urlencode per_page=20 \
  | python3 -c 'import json,sys; [print(("PR   " if "pull_request" in i else "Issue"), i["html_url"], "-", i["title"]) for i in json.load(sys.stdin).get("items", [])]'
```

Open the likely matches and read them before deciding. Then tell the user
what you found:

- **An open issue already describes it**: do not draft a new one. Give the
  user the link. If they have information the issue lacks (a different
  version, new log lines, a reliable way to reproduce it), draft a short
  comment they can add. Otherwise suggest they subscribe to it.
- **An open pull request addresses it**: give the user the link and explain
  that the fix is in progress and will ship in a later build. Draft nothing
  unless the PR clearly misses their case.
- **A closed issue says it was fixed**: compare the fix date or build with the
  user's build. If theirs is older, upgrading is the answer (see
  `upgrades-and-rollback.md`). If theirs is newer and the problem is back,
  draft a new report that links the old issue.
- **Closed as won't fix or not planned**: explain the stated reason. Do not
  draft the same request again.
- **Nothing relevant**: draft a new report and mention that you searched,
  with the search terms you used.

## Step 3: Gather facts (bugs)

Everything in a bug report must come from the user's own server. Collect:

- Silo build: the admin sidebar, or `GET /api/v2/admin/system/build`. Also
  the image tag or digest.
- How Silo is deployed (Docker Compose, Unraid, plain Docker, Kubernetes, bare
  metal), single server or with separate nodes, and the GPU if it matters.
- Which clients are affected: web, Android, iOS/tvOS/macOS, a
  Jellyfin-compatible app (which one), or none.
- Exact steps that make it happen, which the user has run themselves.
- Raw log lines around the failure, copied exactly, with only redactions
  changed (see "Redact" below).

If the user has not reproduced it themselves, ask them to before posting.
Silo's bug form requires the reporter to confirm they reproduced it on a real
deployment.

## Bug report draft

Match the fields of Silo's bug form so the user can paste each part. Present
it as one Markdown block:

```markdown
**Title:** [bug] <short, specific summary: what fails, where>

### What happened
<What the user observed, in plain words. Facts only.>

### Steps to reproduce
1. <step the user actually ran>
2. <...>

### Expected behavior
<What should have happened.>

### Silo version / commit
<build number and image tag or digest>

### Deployment
<Docker | Bare metal / systemd | Local dev build | Other>. <One line of detail: Compose or Unraid, separate nodes, GPU.>

### Clients affected
<Web UI / Android / iOS/tvOS/macOS / Jellyfin-compat client (name) / Other/not client-specific>

### Relevant logs
    <raw log lines, redactions marked like [REDACTED-IP]; or "no logs available">

### Technical notes
<Your analysis: suspected cause, related settings, what you ruled out. Label guesses as guesses.>

### AI disclosure
- AI harness: <exact harness, e.g. "Claude Code" or "Codex CLI">
- AI tool(s): <exact tool names, or "none">
- AI model(s): <the exact model identifier you are running as>
- AI involvement: <"AI-assisted" if the user reproduced and verified it; "Fully AI-generated, human verified" if you wrote all of it>
- Independent or adversarial review: n/a
```

Rules:

- Keep **What happened** and **Steps to reproduce** to what the user saw and
  did. Put every inference under **Technical notes**.
- Never invent or tidy up log lines, steps, versions, or results. The Silo
  project blocks contributors for fabricated evidence, even on a first
  offence.
- Fill in the AI disclosure honestly. Silo requires it on every issue.
- One problem per report. If you found two unrelated bugs, draft two.

## Feature request draft

Silo is pre-1.0 and focused on correctness and polish, so a request is most
useful when it explains the problem rather than prescribing a solution.

```markdown
**Title:** <short description of the capability, in user terms>

### Problem
<What the user is trying to do, and what stops them today. Concrete example.>

### Who it affects
<The kind of user or setup: household size, library type, client, deployment.>

### Current workaround
<What they do instead, or "none".>

### Proposed behavior
<What they would like Silo to do. Describe the outcome, not an implementation.>

### Alternatives considered
<Other approaches, including plugins or companion apps, and why they fall short.>

### Existing issues and PRs checked
<Search terms used and any related links, or "none found".>

### AI disclosure
- AI harness: <exact harness>
- AI tool(s): <exact tool names, or "none">
- AI model(s): <exact model identifier>
- AI involvement: <level>
```

Confirm with the user that the problem and proposed behavior match what they
want before handing over the draft.

## Redact

Before handing over any draft, remove or replace, and mark each change:

- `SECRET_KEY`, database passwords, `DATABASE_URL`, API keys, access tokens,
  cookies, and `Authorization` headers.
- Public hostnames, domain names, public IP addresses, and Tailscale names.
- Usernames and email addresses of household members.
- Media file names and paths, if the user considers them private.

Never paste output of `docker compose config`, `docker inspect`, `env`,
`printenv`, or a `.env` file into a draft, even redacted. Describe the
relevant setting instead ("`DATABASE_URL` points at an external PostgreSQL 17
server").

## Client diagnostics

The Silo apps can send a diagnostics report to the user's own server. Admins
see these under **Admin > Diagnostics** and can download them. They stay on the
user's server unless the user chooses to share one. Mention in a draft that
one is available rather than attaching it.
