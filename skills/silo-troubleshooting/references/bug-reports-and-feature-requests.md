# Drafting bug reports and feature requests

Use this when the evidence points at a bug in Silo rather than the user's
setup, when a fix would need a risky manual change, or when the user wants
something Silo does not do yet.

Silo asks people to contribute through issues rather than pull requests, and
maintainers work directly from what a report says. An accurate, complete
report gets acted on; a report with a wrong version, tidied-up logs, or a guess
presented as fact sends the work in the wrong direction. The Silo project
blocks reporters for fabricated evidence, even on a first offence.

Your job is to **draft** the report, have independent reviewers try to break
it, and hand the result to the user. The user reviews it and posts it. Never
file, post, comment, or react on the user's behalf.

## Step 1: Decide which kind it is

- **Bug**: Silo does something wrong, crashes, or does not do what its own
  settings, UI, or documentation say. The user can make it happen again.
- **Feature request**: Silo works as designed, but the user wants it to do
  something it does not do today.
- **Comment on an existing issue**: Step 2 finds a matching open issue and
  the user has information it lacks.
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

## Step 3: Reproduce and record the evidence

Everything in a report must come from the user's own server and the user's own
actions. Keep a working folder for the report, outside the Compose directory:

```sh
report_dir=$(mktemp -d "${TMPDIR:-/tmp}/silo-report.XXXXXX"); echo "$report_dir"
```

It holds two files: `evidence.md` and, later, `draft.md`. Tell the user where
the folder is. It contains unredacted output, so it stays on their machine.

Write each fact into `evidence.md` as you collect it: what it shows, the exact
command or admin page it came from, and the raw output, pasted unedited. Do not
summarise output there. The reviewers in Step 7 check the draft against this
file, so a fact that is not in it cannot go in the draft.

**Reproduce it now.** Ask the user to make the problem happen again on their
current build, note the time, and capture the logs from that attempt. If it
cannot be reproduced on demand, say so in the draft ("seen 3 times since
12 March, not reproducible on demand") instead of presenting older logs as a
fresh reproduction. Silo's bug form asks the reporter to confirm they
reproduced it on a real deployment.

Collect for every bug:

- Silo build: the admin sidebar, or `GET /api/v2/admin/system/build`. Also
  the image tag or digest.
- How Silo is deployed (Docker Compose, Unraid, plain Docker, Kubernetes, bare
  metal), single server or with separate nodes, and the GPU if it matters.
- Scope: what fails and what still works (another client, another file,
  another account, LAN versus remote), how often (for example "3 of 3
  attempts"), since when, and what changed just before.
- The exact steps the user ran, in order, from a stated starting point.
- What the user expected, and why: Silo's documentation, a setting's
  description, or how an earlier build behaved.
- Raw log lines around the failure, including the lines just before the first
  error: **Admin > Logs** filtered by component or playback session, or
  `docker compose logs --since <time> silo`.

Playback problems also need:

- The file's streams: container, video codec and profile, HDR format, audio
  codec and channels, and subtitle format. **Media Info** in the title's menu
  in the web app shows these to admins; `ffprobe` (see
  `playback-and-transcoding.md`) gives the same, trimmed to those fields.
- How it was played: direct play, remux, direct stream, or transcode, with the
  source and delivered formats and the encoder, from the session in **Admin >
  Activity** (while it plays) or **Admin > Playback History**.
- The acceleration status from **Admin > Settings > Playback > Hardware
  acceleration** and **Admin > Nodes**, when it transcoded.

Problems in an app also need:

- The app version and build: **Settings > About > Version** on iPhone, iPad,
  Mac, and Android phones (shown like `1.0.0 (42)`), or **Settings > Server >
  About > App Version** on Apple TV and Android TV. For a Jellyfin-compatible
  app, its name and version from its own settings.
- Where it was installed from: TestFlight or a sideloaded IPA for the Apple
  apps; Google Play or an APK from GitHub Releases for Android.
- The device model and its OS version.
- For playback, the player's stats: on iPhone and iPad, the player's **…**
  button > **Stats** (or **Advanced** for route details); on Apple TV, **Info
  and options** > **Stats**; on Android phones, **Playback settings** >
  **Playback stats**; on Android TV, the **Stats** tab, with the **Audio** tab
  showing passthrough or PCM. Also the audio output (TV speakers, receiver)
  and the subtitle format, which are easy to forget and often decide the
  outcome.
- A diagnostics report reference, if the user sent one (see "Client
  diagnostics" below).

The apps do not show the server version; get it from the admin sidebar.

The snapshot script's output is already masked; copy the relevant parts into
`evidence.md` too.

## Step 4: Choose the repository

| Where the problem is | Repository |
|---|---|
| Server, web app, admin pages, install or upgrade, the Jellyfin-compatible API, the plugin host | [`silo-server`](https://github.com/Silo-Server/silo-server/issues/new/choose) |
| Only in the iOS, tvOS, or macOS app | [`silo-apple`](https://github.com/Silo-Server/silo-apple/issues/new/choose) |
| Only in the Android phone or TV app | [`silo-android`](https://github.com/Silo-Server/silo-android/issues/new/choose) |
| One plugin's provider behavior (TMDB, TVDB, Trakt, and so on) | That plugin's repository under [Silo-Server](https://github.com/Silo-Server) |

When the same failure shows up in the web app and in an app, the cause is
usually the server. Tell the user which repository fits and why, and which
issue form to choose there. Where and whether to post is their decision.

## Step 5: Draft

Write the draft to `$report_dir/draft.md`, matching the fields of the issue
form in the repository you chose, so the user can paste each part. The template
below follows the `silo-server` bug form. The `silo-apple` and `silo-android`
bug forms ask for the device, device model and OS version, app version and
build, install source, server version, playback details, and diagnostics
reference as separate fields; use the same facts under those headings.

### Bug report

```markdown
**Title:** [bug] <short, specific summary: what fails, where>

### What happened
<What the user observed, in plain words, including scope and frequency. Facts only.>

### Steps to reproduce
1. <starting point>
2. <step the user actually ran>

### Expected behavior
<What should have happened, and where that expectation comes from.>

### Silo version / commit
<build number and image tag or digest>

### Deployment
<Docker Compose | Unraid | Docker (other) | Kubernetes | Bare metal / systemd | Local dev build | Other>. <One line of detail: separate nodes, GPU.>

### Area
<Playback and transcoding | Libraries, scanning, and metadata | Search | Web app | Admin pages and settings | Accounts, profiles, and sign-in | Plugins | Jellyfin-compatible clients | Install, upgrade, and startup | Performance | Other>

### Clients affected
<Web UI / Android / iOS/tvOS/macOS / Jellyfin-compat client (name) / Other/not client-specific>

### Client app and device
<For an app: version and build, install source, device model, OS version. For the web UI: the browser. Otherwise leave empty.>

### Media and playback details
<For playback: the file's streams and how the session was played. Otherwise leave empty.>

### Diagnostics report reference
<SILO-… if the user sent one to Silo Diagnostics; otherwise leave empty.>

### Relevant logs
    <raw log lines, redactions marked like [REDACTED-IP], omissions marked like [... 40 lines omitted ...]; or "no logs available">

### Technical notes
<Your analysis: suspected cause, media details, related settings, what you ruled out. Label guesses as guesses.>

### AI disclosure
- AI harness: <exact harness, e.g. "Claude Code" or "Codex CLI">
- AI tool(s): <exact tool names, or "none">
- AI model(s): <the exact model identifier you are running as>
- AI involvement: <"AI-assisted" if the user reproduced and verified it; "Fully AI-generated, human verified" if you wrote all of it>
- Independent or adversarial review: <the summary from Step 7>
```

Rules:

- Keep **What happened** and **Steps to reproduce** to what the user saw and
  did. Put every inference under **Technical notes**.
- Every statement outside **Technical notes** must trace to an entry in
  `evidence.md`.
- State frequency and scope exactly as observed: "2 of 2 attempts on the web
  app", not "always".
- Never invent or tidy up log lines, steps, versions, or results. Trim logs
  only by cutting whole lines, and mark each cut.
- One problem per report. If you found two unrelated bugs, draft two.

### Feature request

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
- Independent or adversarial review: <the summary from Step 7>
```

Confirm with the user that the problem and proposed behavior match what they
want before the review.

## Step 6: Redact

Before the review, remove or replace these in the draft, and mark each change:

- `SECRET_KEY`, database passwords, `DATABASE_URL`, API keys, access tokens,
  cookies, and `Authorization` headers.
- Public hostnames, domain names, public IP addresses, and Tailscale names.
- Usernames and email addresses of household members.
- Media file names and paths, if the user considers them private.

Never paste output of `docker compose config`, `docker inspect`, `env`,
`printenv`, or a `.env` file into a draft, even redacted. Describe the
relevant setting instead ("`DATABASE_URL` points at an external PostgreSQL 17
server").

## Step 7: Adversarial review

Before the user sees the final draft, have independent reviewers try to break
it. You wrote the draft, so you believe its claims, know context the reader
lacks, and stop noticing your own mistakes. A reviewer that starts fresh does
not.

Run it with subagents:

- Use your harness's subagent feature, for example Claude Code's Agent tool.
  Start one reviewer per lens in the table below, in parallel, each in a fresh
  context.
- Give each reviewer only its brief, with the real `$report_dir` path filled
  in. Do not add your reasoning or a summary of the conversation; the point is
  that the reviewer does not share your assumptions.
- If your harness cannot start subagents, tell the user. Then do each lens
  yourself as a separate pass that reads only the two files, and write in the
  disclosure that the review was a self-review, not an independent one.

| Lens | Bug | Feature request | Comment |
|---|---|---|---|
| Evidence | yes | | yes |
| Reproducibility | yes | | |
| Problem and scope | | yes | |
| Privacy | yes | yes | yes |
| Duplicates | yes | yes | |

Every brief starts with this text:

```text
You are reviewing a draft GitHub issue for the Silo media server before its
author posts it. Your job is to find what is wrong with it, not to approve it.
Assume there are problems until you have checked every sentence your lens
covers.

Read <report_dir>/draft.md (the draft) and <report_dir>/evidence.md (the raw
evidence it was written from). Do not run commands against any server, edit
any file, or post anything.

Return a list of findings. For each one give: severity (blocker, should-fix,
or nit), the exact sentence or field from the draft, what is wrong, and the
evidence, or missing evidence, that shows it. End with a one-line verdict.
Say "no findings" only after checking everything your lens covers.
```

Then add the lens:

- **Evidence**: "Check every factual statement in the draft against
  evidence.md. Flag any statement with no supporting entry; any log line,
  version, command output, or step that differs from evidence.md other than a
  marked redaction or a marked omission; causes, inferences, or guesses outside
  Technical notes; guesses inside Technical notes that are not labelled as
  guesses; and frequency or scope ('always', 'every client') wider than the
  evidence shows."
- **Reproducibility**: "Read the draft as a Silo maintainer who has never seen
  this server and has only this text. Could you reproduce the problem? Flag a
  missing Silo build, deployment detail, client name and version, or device
  and OS version for an app problem; missing media details or play method for
  a playback problem; steps that start from an unstated state or skip a step;
  missing or unexplained expected behavior; more than one problem in one
  report; and a report aimed at the wrong repository (silo-server for the
  server and web app, silo-apple or silo-android for problems only in those
  apps, a plugin's own repository for provider behavior)."
- **Problem and scope**: "Flag a request that describes an implementation
  instead of the user's problem and the outcome they want; a missing concrete
  example; anything under Silo's permanent non-goals (Live TV, tuners, IPTV,
  EPG/XMLTV guides, DVR, .strm remote-stream files); more than one request in
  one issue; and claims about what Silo does today that evidence.md does not
  support."
- **Privacy**: "Find anything in the draft that should not be public:
  secrets, tokens, passwords, API keys, cookies, Authorization headers,
  connection strings, public hostnames and domains, public IP addresses,
  Tailscale names, email addresses, household members' usernames, and media
  titles or paths. Flag redactions that are not marked, and redactions that
  removed something a maintainer needs; suggest a safe placeholder instead."
- **Duplicates**: "Try to show this is already reported or already fixed.
  Search open and recently closed issues and pull requests across the
  Silo-Server organization, using terms the draft does not use: distinctive
  fragments of each error message, setting and feature names, and plain
  synonyms. Use `gh search issues --owner Silo-Server ...` and
  `gh search prs --owner Silo-Server ...`, or the GitHub search API. Run about
  a dozen searches at most; if search is rate-limited, list the terms you
  could not search instead of downloading whole repositories. Report each
  match with its link and why it matches, and any closed fix that is newer
  than the build in the draft."

Resolve the findings:

- Fix each finding in `draft.md`, or reject it with a reason that points to
  `evidence.md`. Do not argue a finding away without evidence.
- When a finding needs something only the user can supply (a fresh
  reproduction, a version, a missing log), ask the user. Never fill the gap
  with a guess.
- If the duplicate reviewer found a match, go back to Step 2.
- If any blocker was found, or the draft changed substantially, run a second
  round with new reviewers on the revised draft. Stop after two rounds and
  list whatever is still unresolved.
- Fill the draft's **Independent or adversarial review** field with a few
  sentences: how many reviewers, which lenses, what they found, and what
  changed. For example: "Four fresh subagents (evidence, reproducibility,
  privacy, duplicates) reviewed the draft against the raw evidence. They found
  an unmarked hostname in the logs, a frequency stated as 'always' after two
  attempts, and a missing app build; all three were fixed. The duplicate
  search found no matching issue."

## Step 8: Hand over

Show the user:

- The final draft.
- What the review changed, in a short list, and anything left unresolved.
- Which repository and issue form to use (Step 4).

Ask the user to confirm that they ran the steps themselves and that every fact
matches their server, then let them post it. Remind them that `$report_dir`
holds unredacted output and that they can delete it once the report is
posted.

## Client diagnostics

The Silo apps for iPhone, iPad, Apple TV, and Android can send a diagnostics
report: **Settings > Support > Diagnostics** on phones and tablets, **Settings
> Diagnostics** on TVs, then **Send Diagnostics Now**. Android also offers
**Start Diagnostic Capture**, which records while the user reproduces the
problem. The Mac app has no diagnostics. The user picks where the report goes:

- **Silo Diagnostics**: Silo's hosted service. The app shows a reference such
  as `SILO-MT2PPCKZ` (copy it from **Sent History**). Put the reference in the
  draft; maintainers can look the report up. The service omits account,
  profile, server address, and playback session IDs, and deletes reports
  within 30 days.
- **My Silo Server** (Android TV: **This Silo server**): the report stays on
  the user's server. Admins see it under **Admin > Diagnostics**, which needs
  **Client uploads** turned on there. Mention in the draft that one is
  available rather than attaching it.

Reports to Silo Diagnostics are never sent automatically; the user sends
each one.
