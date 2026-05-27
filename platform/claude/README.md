# platform/claude

Claude Code skills, commands, and starter templates that ship with the
repo and get deployed to every operator's `~/.claude/` on bootstrap.

## What's here

```
platform/claude/
├── skills/                  # one dir per skill, each contains SKILL.md
├── commands/                # slash-commands (one .md per command)
├── CLAUDE.md.example        # sanitized global-preferences template
└── settings.json.example    # status line, plugins, defaults
```

The deployer that distributes these is `bootstrap/12-claude-skills.sh`.
It runs as part of `bootstrap.sh` (gated by `INSTALL_CLAUDE_SKILLS`,
defaults `true`) and is also invoked from `platform/authelia/add-user.sh`
when the new Authelia user happens to also have a Linux account.

## Deploy model

For every target user (`SERVER_ADMIN_USER` plus any Authelia user that
also exists as a Linux user with a home directory):

| What lands in `~/.claude/`            | How              | Behavior on re-run |
|---------------------------------------|------------------|--------------------|
| `skills/<name>` (per skill)           | **symlink** into the repo | `git pull` → updated instantly. Stale symlinks pointing elsewhere are replaced. |
| `commands/<name>.md` (per command)    | **symlink** into the repo | Same as above. |
| `CLAUDE.md`                           | **copy** from `CLAUDE.md.example` | Created only when absent. Never overwritten. |
| `settings.json`                       | **copy** from `settings.json.example` | Created only when absent. Never overwritten. |

The deployer is **idempotent** (safe to re-run on every `git pull`) and
**non-destructive** (a real file or user-modified directory in
`~/.claude/skills/<name>` is preserved with a WARN log — never clobbered).

## How operators customize a skill

You have two options:

**1. Edit the skill in the repo** — the change goes through PR review and
ships to every operator on the next deploy. This is the preferred path
for changes that should benefit everyone.

**2. Replace the symlink with a real directory** — local-only override.

```bash
cd ~/.claude/skills
rm code-review                       # remove the symlink
cp -R /opt/infra/platform/claude/skills/code-review .
$EDITOR code-review/SKILL.md
```

On the next deploy, the WARN log will note that your real directory is
being preserved. To go back to the shared version: `rm -rf code-review`
and re-run `sudo /opt/infra/bootstrap/12-claude-skills.sh`.

## How to add a new skill

1. `mkdir platform/claude/skills/<new-skill>` in the repo.
2. Write `SKILL.md` with the standard frontmatter (`name:`, `description:`).
3. Run the scanner: `./security/scan-claude-skills.sh`.
4. Open a PR. CI runs the scanner automatically.
5. After merge, `git pull` on each server picks it up; the next run of
   `12-claude-skills.sh` symlinks it for every user. (Or it just appears
   on next bootstrap — symlinks are created lazily on every run.)

## How to update `CLAUDE.md` for everyone vs. just yourself

- **Everyone**: edit `platform/claude/CLAUDE.md.example`. The change reaches
  *new* operators only — existing `~/.claude/CLAUDE.md` files are never
  overwritten, so existing operators stay on their personal version.
- **Just yourself**: edit `~/.claude/CLAUDE.md` directly. Nothing in the
  deploy path will touch it.

## What's not here (and why)

- **`overall-infra-architect`** — lives at `.claude/skills/` in the repo
  root, not under `platform/claude/skills/`. It governs work on *this*
  repo specifically (loaded automatically by Claude Code when you open
  the repo), not as a generic cross-project skill. Don't move it.
- **The operator's personal `CLAUDE.md`** — never committed. The
  publishable version is `CLAUDE.md.example`, with the personal "My
  context" section stubbed out for each operator to fill in locally.
- **Anything matched by `security/scan-claude-skills.sh`** — emails,
  API keys, public IPs, private keys, plus an operator's local deny
  patterns from `security/scan-claude-skills.deny` (gitignored).

## Source of truth

The repo is the source of truth on every machine where the deployer
runs. If you also keep a personal `~/.claude/skills/` on a non-server
machine (e.g. your laptop), you have two copies — re-sync intentionally,
or convert the laptop's `~/.claude/skills/<name>` entries to symlinks
pointing at your local clone of this repo.
