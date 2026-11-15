# Silo troubleshooting skill

Get help fixing your self-hosted [Silo](https://github.com/Silo-Server/silo-server)
media server from Claude Code or Codex. There is nothing to install: paste
this repository's link into the agent and describe what is wrong. The agent
reads this guide, checks your server's logs and settings, explains what it
finds, and asks before it changes anything.

> [!CAUTION]
> **Take a backup before you start. Don't blame us if Claude or Codex deletes
> your server.**
>
> This skill tells the agent to stay read-only until you approve each change,
> and to leave destructive commands for you to run yourself. AI agents still
> make mistakes, misread output, and sometimes ignore instructions. It is your
> machine and your data. Back up first, read what the agent proposes, and say
> no when you are not sure.
>
> Provided as is, with no warranty (see [License](#license)).

## How to use it

1. **Open Claude Code or Codex in a terminal on the machine that runs Silo.**
   If you usually reach that machine over SSH, SSH in first and start the
   agent there. If Silo runs in Docker Compose, `cd` into the folder with its
   `docker-compose.yml` first.
   - Claude Code: run `claude` ([install Claude Code](https://code.claude.com/docs))
   - Codex: run `codex` ([install Codex CLI](https://developers.openai.com/codex))
2. **Paste this link and say what is not working:**

   ```text
   https://github.com/Silo-Server/silo-troubleshooting-skill
   ```

3. **Answer its questions.** It may ask permission to download the guide
   from GitHub (say yes). Then it asks how Silo is installed and looks around
   your server. Before each change it shows you the exact command and waits
   for your yes.

> [!IMPORTANT]
> **Chat apps cannot do this.** The Claude and ChatGPT chat apps and websites
> cannot run commands on your server, so they cannot follow this guide.
> Claude Code on the web and Codex cloud tasks run on a remote computer and
> cannot reach your server either. Use Claude Code or Codex in a terminal on
> your Silo machine.

### Example prompts

Copy one, swap in your problem, and paste it into Claude Code or Codex:

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Use this to help me figure out why my Silo server keeps restarting since I updated it.
```

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Use this to help me figure out why Silo can't see my new movies folder.
```

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Playback works at home but not away from home. I use Nginx Proxy Manager. Help me figure out why.
```

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Silo isn't using hardware transcoding on my Intel NUC. Help me figure out why.
```

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Silo runs on Unraid and search stopped finding new shows. Help me figure out what's wrong.
```

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Walk me through safely updating Silo to the latest build.
```

```text
https://github.com/Silo-Server/silo-troubleshooting-skill
Help me write a bug report: subtitles don't show on my Apple TV for one file.
```

### Which permission mode to use

Auto mode works well. A separate reviewer model checks each action, and the
guide still has the agent ask you before every change and leave destructive
steps for you to run yourself.

- Claude Code: auto mode (`claude --permission-mode auto`, or Shift+Tab
  during a session). It is already the default on Pro, Max, and Team plans.
- Codex: automatic review (`codex --approve-for-me`).

If you would rather approve every command yourself, use
`claude --permission-mode manual` or Codex's default approval prompts. Avoid
the modes that skip all checks (Claude Code's
`--dangerously-skip-permissions`, Codex's
`--dangerously-bypass-approvals-and-sandbox`).

## For AI agents

If the user gave you this link, this repository is a skill for diagnosing
and fixing their Silo server. Load it like this:

1. If the skill is already installed (for example as the
   `silo-troubleshooting` plugin), use the installed copy and skip step 2.
2. Clone the repository into a new private temporary folder, asking for
   network access if your sandbox needs it:

   ```sh
   dir="$(mktemp -d)" && git clone --depth 1 https://github.com/Silo-Server/silo-troubleshooting-skill.git "$dir/silo-troubleshooting-skill" && echo "$dir/silo-troubleshooting-skill"
   ```

   Always make a fresh folder this way rather than reusing one that already
   exists. If you cannot clone, download the files under
   `https://raw.githubusercontent.com/Silo-Server/silo-troubleshooting-skill/main/skills/silo-troubleshooting/`
   into a folder made with `mktemp -d`: `SKILL.md` first, then each file it
   points you to, including `scripts/silo-snapshot.sh` before you run it.
3. Read `skills/silo-troubleshooting/SKILL.md` in full and follow it for the
   rest of the session. Its safety rules apply from your first command.
   `<skill-dir>` in that file means the `skills/silo-troubleshooting` folder
   of your copy.

## What it helps with

- Silo will not start, keeps restarting, or shows as `unhealthy`
- Database, Redis, or S3 storage errors
- Media not showing up, wrong matches, missing artwork
- Search problems, including checking that the optional Meilisearch engine
  is connected and that its index builds
- Playback failures, buffering, hardware transcoding (Intel, AMD, NVIDIA)
- Missing chapter preview images
- Reverse proxies, remote access, apps that cannot connect, Jellyfin clients
- Plugin errors
- Safe upgrades and rollbacks
- Problems that keep coming back, such as slowdowns, memory growth, or
  crashes. The agent can help you turn on Silo's optional
  [metrics](https://github.com/Silo-Server/silo-server/blob/main/docs/operations/monitoring.md)
  and [profiling](https://github.com/Silo-Server/silo-server/blob/main/docs/operations/profiling.md)
  endpoints, so the next occurrence leaves evidence
- Writing an accurate bug report or feature request for Silo. The agent
  checks that no open issue or pull request already covers it, collects the
  evidence from your server for a bug (or your use case for a feature
  request), and has the draft reviewed before you post it

It supports Docker Compose (the standard install), Unraid, and plain Docker.
Kubernetes and other setups work too, but the agent has to adapt the commands.

## Back up first

Back up your Silo server before you let an agent near it, using whatever
backup tools you already rely on. Silo runs on too many kinds of setups for us
to give one backup recipe, so this skill does not tell you how. Make sure
your backup includes:

- The PostgreSQL database.
- Your `SECRET_KEY`, stored separately from the database backup. **Without the
  same `SECRET_KEY`, Silo refuses to start on a restored database.**
- Your deployment configuration: Compose files and `.env`, container
  templates, or manifests.
- Local artwork, if you store artwork on disk rather than S3.

Then check that you can restore it. The agent asks about your backup before
it changes anything.

## What the agent will do

1. Ask how Silo is installed and what changed recently.
2. Run a read-only snapshot script that collects container status, the
   running build, Compose file errors, health checks, database and Redis
   reachability, Meilisearch health if you run it, mounts, GPU devices, disk
   space, and recent errors. It masks passwords and tokens in log lines.
3. Read the part of the guide that matches your problem and check the
   evidence.
4. Explain what it found, citing the log lines or output.
5. For each fix, show the exact command or setting, explain the risk and how
   to undo it, and wait for your yes. Before the first change it asks whether
   you have a backup.
6. Leave the destructive steps (restoring a database, deleting or moving
   data, running or rolling back migrations, SQL that writes) for you to run
   yourself, even if you approve them.
7. If the problem keeps coming back and the cause is still unclear, tell you
   about Silo's metrics and profiling endpoints. It offers to turn them on
   for you or gives you the steps. They cannot explain an incident that has
   already happened, but they record the next one.
8. If the problem looks like a Silo bug, or you want something Silo does not
   do yet, search Silo's open issues and pull requests first. If one exists,
   it gives you the link (and drafts a comment if you have something to add).
   If not, it drafts a bug report or feature request in the format of Silo's
   issue forms. For a bug it first asks you to reproduce the problem and
   records the evidence; for a feature request it records what you are trying
   to do.
9. Before showing you the draft, it has reviewers try to break it: separate
   subagents where the agent supports them, otherwise a self-review that the
   report discloses. For a bug, one checks every claim against the evidence,
   one checks that a maintainer could reproduce it, one looks for private
   details, and one searches for an existing issue. A feature request gets the
   evidence check, a problem-and-scope check, the privacy check, and the
   search. It fixes what they find, asks you for anything only you can supply,
   and tells you which repository to post it in. You post it yourself.

## What it will not do

- Show your `SECRET_KEY`, passwords, or tokens in the conversation, or ask
  you to paste them.
- Generate a new `SECRET_KEY` for an existing install, hand-edit the
  database, or delete migration files.
- File issues, comment, or post anywhere on your behalf.
- Help with Live TV, IPTV, DVR, or `.strm` remote streams. Silo does not
  support those.

## Privacy

Whatever the agent reads in your terminal goes to your AI provider, like any
other agent session. That includes log lines, file and folder names, and
hostnames. The snapshot script masks credentials in logs, but it cannot catch
everything. Don't use the agent on a server whose data you are not allowed to
share with your AI provider.

When you share output with other people (GitHub issues, Discord), check it for
hostnames, IP addresses, email addresses, and media names first.

## Install it permanently (optional)

You do not need this; pasting the link works every time. If you use Claude
Code often and want the skill to load on its own whenever you mention Silo,
install it as a plugin from inside Claude Code:

```text
/plugin marketplace add Silo-Server/silo-troubleshooting-skill
/plugin install silo-troubleshooting@silo
```

Run `/reload-plugins` if Claude Code asks you to. `/plugin marketplace update
silo` pulls in later updates.

## Repository layout

```text
.claude-plugin/                  Claude Code plugin and marketplace manifests
skills/silo-troubleshooting/
  SKILL.md                       Safety rules, workflow, and symptom routing
  references/                    Topic guides the agent loads as needed
  scripts/silo-snapshot.sh       Read-only diagnostics snapshot
```

You can run the snapshot script without an agent too:

```sh
bash skills/silo-troubleshooting/scripts/silo-snapshot.sh              # from your Compose directory
bash skills/silo-troubleshooting/scripts/silo-snapshot.sh --container Silo
```

## Contributing

The guides describe how Silo behaves today. If you find a step that is wrong
for the current Silo release, open an issue or pull request here with the
Silo version and what you saw. Keep the safety rules intact.

## License

[MIT](LICENSE).
As the license says, this software comes with no warranty. You are
responsible for what you allow an AI agent to run on your systems.
