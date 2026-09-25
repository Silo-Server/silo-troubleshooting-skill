# Silo troubleshooting skill

A skill for AI coding agents such as Claude Code and Codex. It helps them
diagnose and fix a self-hosted [Silo](https://github.com/Silo-Server/silo-server)
media server. It tells the agent where Silo keeps its logs, which settings
matter, what common errors mean, and which actions are off-limits. The agent
then works through the problem with you in your own terminal.

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

## What it helps with

- Silo will not start, keeps restarting, or shows as `unhealthy`
- Database, Redis, or S3 storage errors
- Media not showing up, wrong matches, missing artwork
- Search problems, including checking that the optional Meilisearch engine
  is connected and that its index builds
- Playback failures, buffering, hardware transcoding (Intel, AMD, NVIDIA)
- Reverse proxies, remote access, apps that cannot connect, Jellyfin clients
- Plugin errors
- Safe upgrades and rollbacks
- Problems that keep coming back, such as slowdowns, memory growth, or
  crashes. The agent can help you turn on Silo's optional
  [metrics](https://github.com/Silo-Server/silo-server/blob/main/docs/operations/monitoring.md)
  and [profiling](https://github.com/Silo-Server/silo-server/blob/main/docs/operations/profiling.md)
  endpoints, so the next occurrence leaves evidence
- Drafting bug reports and feature requests, after checking that no open
  issue or pull request already covers them

It supports Docker Compose (the standard install), Unraid, and plain Docker.
Kubernetes and other setups work too, but the agent has to adapt the commands.

## What you need

- A running or broken Silo install you administer.
- A terminal on the machine that runs Silo, or SSH access to it.
- One of:
  - [Claude Code](https://code.claude.com/docs)
  - [Codex CLI](https://developers.openai.com/codex)
  - Any agent that can read a Markdown skill file and run shell commands

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

## Install

### Claude Code: plugin (recommended)

Inside Claude Code:

```text
/plugin marketplace add Silo-Server/silo-troubleshooting-skill
/plugin install silo-troubleshooting@silo
```

Run `/reload-plugins` if Claude Code asks you to. `/plugin marketplace update
silo` pulls in later updates.

### Claude Code: manual

```sh
git clone https://github.com/Silo-Server/silo-troubleshooting-skill.git
mkdir -p ~/.claude/skills
ln -s "$PWD/silo-troubleshooting-skill/skills/silo-troubleshooting" ~/.claude/skills/silo-troubleshooting
```

To update later, run `git pull` in the clone.

### Codex CLI

```sh
git clone https://github.com/Silo-Server/silo-troubleshooting-skill.git
mkdir -p ~/.agents/skills
ln -s "$PWD/silo-troubleshooting-skill/skills/silo-troubleshooting" ~/.agents/skills/silo-troubleshooting
```

Restart Codex so it picks up the skill. To update later, run `git pull` in the
clone.

### Other agents

Point the agent at `skills/silo-troubleshooting/SKILL.md` and tell it to
follow that file. The other files it needs are in the same folder.

## Use it

1. Open a terminal on the machine that runs Silo. If Silo runs in Docker
   Compose, `cd` into the directory with its `docker-compose.yml`.
2. Start your agent there (`claude` or `codex`).
3. **Pick a permission mode.** Auto mode works well for this. A separate
   reviewer model checks each action, and the skill still asks you before
   every change and leaves destructive steps for you to run yourself.
   - Claude Code: auto mode (`claude --permission-mode auto`, or Shift+Tab
     during a session). It is already the default on Pro, Max, and Team plans.
   - Codex: automatic review (`codex --approve-for-me`).

   If you would rather approve every command yourself, use manual approval
   instead: `claude --permission-mode manual`, or Codex's default approval
   prompts. Avoid the modes that skip all checks (Claude Code's
   `--dangerously-skip-permissions`, Codex's
   `--dangerously-bypass-approvals-and-sandbox`).
4. Describe the problem in plain words. The skill loads automatically when
   you mention Silo. To call it explicitly, use
   `/silo-troubleshooting:silo-troubleshooting` (Claude Code plugin),
   `/silo-troubleshooting` (Claude Code manual install), or
   `$silo-troubleshooting` (Codex).

Example prompts:

- "My Silo server keeps restarting after I updated it. Help me figure out
  why."
- "Silo can't see my new movies folder."
- "Playback works at home but not away from home. I use Nginx Proxy Manager."
- "Hardware transcoding isn't being used on my Intel NUC."
- "Walk me through safely updating Silo to the latest build."

### What the agent will do

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
   If not, it drafts a bug report or feature request for you to paste wherever
   you choose.

### What it will not do

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
