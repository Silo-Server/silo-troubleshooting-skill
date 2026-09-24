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
> make mistakes, misread output, and sometimes ignore instructions. You are
> the one approving commands on your own machine. Back up first, read every
> command before you approve it, and say no when you are not sure.
>
> [Back up in two minutes](#back-up-first) · Provided as is, with no warranty
> (see [License](#license)).

## What it helps with

- Silo will not start, keeps restarting, or shows as `unhealthy`
- Database, Redis, or S3 storage errors
- Media not showing up, wrong matches, missing artwork
- Playback failures, buffering, hardware transcoding (Intel, AMD, NVIDIA)
- Reverse proxies, remote access, apps that cannot connect, Jellyfin clients
- Plugin errors
- Safe upgrades, rollbacks, and backups
- Drafting a good bug report when the problem is in Silo itself

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

Run these from the directory that holds Silo's `docker-compose.yml`:

```sh
# Which build is running (write it down; you need it to roll back)
docker image inspect --format '{{join .RepoDigests " "}}' \
  "$(docker inspect --format '{{.Image}}' "$(docker compose ps -q silo)")"

# Dump the database and check the dump is readable
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' > silo-$(date +%F).dump
docker compose exec -T postgres pg_restore --list < silo-$(date +%F).dump > /dev/null && echo "backup is readable"

# Keep a copy of your settings file
cp .env silo-env-$(date +%F).backup && chmod 600 silo-env-$(date +%F).backup
```

The build number also appears in Silo's admin sidebar.

Unraid, using the official template names:

```sh
mkdir -p /mnt/user/backups
docker exec Silo-PostgreSQL sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' > /mnt/user/backups/silo-$(date +%F).dump
```

Then copy your `SECRET_KEY` somewhere safe. On Unraid it is a variable in the
Silo container settings. **Without the same `SECRET_KEY`, Silo refuses to start on a
restored database.** Keep the key separate from
the dump.

The skill's [backup guide](skills/silo-troubleshooting/references/backups-and-upgrades.md)
covers restores and what else is worth keeping.

## Install

### Claude Code: plugin (recommended)

Inside Claude Code:

```text
/plugin marketplace add Silo-Server/silo-troubleshooting-skill
/plugin install silo-troubleshooting@silo
```

Run `/reload-plugins` if Claude Code asks you to. `/plugin marketplace update
silo` pulls in later updates.

> [!NOTE]
> This repository is private for now, so only accounts with access to it can
> install it. Claude Code uses your own git credentials. `owner/repo`
> shorthand clones over SSH. If you sign in to GitHub over HTTPS with the `gh`
> CLI instead, run `gh auth setup-git` once and start Claude Code with
> `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1`.

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
3. **Keep approvals on.** Do not start the agent in a mode that skips
   permission prompts (Claude Code's `--dangerously-skip-permissions` or bypass
   mode, or Codex's `--yolo` or full-auto modes). You want to see and approve
   every command.
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
   reachability, mounts, GPU devices, disk space, and recent errors. It masks
   passwords and tokens in log lines.
3. Read the part of the guide that matches your problem and check the
   evidence.
4. Explain what it found, citing the log lines or output.
5. For each fix, show the exact command or setting, explain the risk and how
   to undo it, and wait for your yes. Before the first change it asks whether
   you have a backup.
6. Leave the destructive steps (restoring a database, deleting or moving
   data, running or rolling back migrations, SQL that writes) for you to run
   yourself, even if you approve them.
7. If the problem looks like a Silo bug, draft a bug report for you to review
   and file.

### What it will not do

- Show your `SECRET_KEY`, passwords, or tokens in the conversation, or ask
  you to paste them.
- Generate a new `SECRET_KEY` for an existing install, hand-edit the
  database, or delete migration files.
- File issues or post anywhere on your behalf.
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

[GNU Affero General Public License v3.0](LICENSE), the same license as Silo.
As the license says, this software comes with no warranty. You are
responsible for what you allow an AI agent to run on your systems.
