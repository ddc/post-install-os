# DiscordBot Ansible Role

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How It Works](#how-it-works)
4. [Prerequisites](#prerequisites)
5. [Role Variables](#role-variables)
6. [Environment Variables](#environment-variables)
7. [Database Integration](#database-integration)
8. [Deployment Instructions](#deployment-instructions)
9. [Directory Structure](#directory-structure)
10. [Troubleshooting](#troubleshooting)

---

## Overview

The **discordbot** role deploys the [ddc/DiscordBot](https://github.com/ddc/DiscordBot)
project — a Python 3.14 / `discord.py` bot with OpenAI and Guild Wars 2 integrations — as
Docker containers on a DietPi host. It clones the repository, uploads the environment file,
ensures the bot's database exists in the shared `postgres` container, and starts the
containers using the project's own `utilities/` scripts.
The bot makes **outbound-only** connections to Discord and exposes no inbound ports, so the
role adds no firewall rules.

---

## Architecture

```
┌──────────────────────────────────────────────  ┐
│                  DietPi host                   │
│                                                │
│  ┌────────────────────┐   ┌────────────────┐   │
│  │ discordbot_alembic │──▶│   discordbot   │   │
│  │  (runs migrations) │   │   (the bot)    │   │
│  └─────────┬──────────┘   └───────┬────────┘   │
│            │   postgres_network    │           │
│            └──────────┬────────────┘           │
│                  ┌────▼─────┐                  │
│                  │ postgres │  (shared role)   │
│                  └──────────┘                  │
└────────────────────────────────────────────────┘
                       │ outbound
                       ▼
                  Discord / OpenAI / GW2 APIs
```

**Components:**

- **discordbot_alembic** — runs Alembic database migrations on startup, then idles; has a
  healthcheck the bot waits on.
- **discordbot** — the bot process (`uv run python -m src`); starts after migrations succeed.
- **postgres** — the shared PostgreSQL container (deployed by the `postgres` role) that owns
  the external `postgres_network`. The bot connects to it as host `postgres`.

---

## How It Works

1. **Stop & clean** — if a previous install exists, `utilities/stop.sh` stops its containers
   and the directory is removed for a fresh clone.
2. **Clone** — the repository is cloned over SSH (`git@github.com:ddc/DiscordBot.git`,
   branch `master`).
3. **Logs** — the repo's `logs/` directory is replaced with a symlink to
   `/var/log/discordbot`, matching the compose `./logs` volume mount.
4. **Configure** — `files/.env.<env_type>` is uploaded to `<project_location>/.env` (mode 0600).
5. **Database** — the role waits for the shared `postgres` container to be healthy. The bot's
   own Alembic migrations (`src/database/migrations/env.py`) connect as the `postgres`
   superuser and create the `discordbot` database (if missing) plus its schemas
   (`public`, `gw2`), so the role does not create the database itself.
6. **Start** — `utilities/start.sh` builds the image, runs the `discordbot_alembic` migration
   service, then starts the `discordbot` service.
7. **Verify** — the role waits for the `discordbot` container to appear in `docker ps` and
   fails if it does not.

---

## Prerequisites

- Target DietPi/Debian host reachable over SSH.
- Docker + docker compose plugin (installed by the `docker` role).
- The shared `postgres` role deployed and its container healthy (owns `postgres_network`).
- A GitHub SSH key on the host for the deploy user (`new_users[0].name`).
- A configured `files/.env.prod` (or `.env.dev`) with a valid `BOT_TOKEN`.

---

## Role Variables

Defined in `vars/main.yml`:

| Variable           | Default                                        | Description                                      |
|--------------------|------------------------------------------------|--------------------------------------------------|
| `project_name`     | `discordbot`                                   | Project name                                     |
| `project_location` | `{{ containers_remote_directory }}/discordbot` | Install directory (`/opt/containers/discordbot`) |
| `logs_location`    | `/var/log/discordbot`                          | Centralized log directory                        |
| `git_repo`         | `git@github.com:ddc/DiscordBot.git`            | Repository (SSH)                                 |
| `git_branch`       | `master`                                       | Branch to clone                                  |
| `env_type`         | `prod`                                         | Selects `files/.env.{{ env_type }}`              |

**Inherited** (from `group_vars/all.yml`): `containers_remote_directory`, `new_users`.

---

## Environment Variables

All bot configuration lives in `files/.env.dev` (local development) and `files/.env.prod`
(host deployment). These two files hold real secrets and are **git-ignored**; only the empty
`.env.dev.placeholder` / `.env.prod.placeholder` markers are committed.
Key deployment values (in `.env.prod`):

| Variable              | Value        | Description                                  |
|-----------------------|--------------|----------------------------------------------|
| `BOT_TOKEN`           | *(required)* | Discord bot token                            |
| `OPENAI_API_KEY`      | *(optional)* | OpenAI API key                               |
| `POSTGRESQL_HOST`     | `postgres`   | Shared postgres container hostname           |
| `POSTGRESQL_PORT`     | `5432`       | Database port                                |
| `POSTGRESQL_USER`     | `postgres`   | Database user                                |
| `POSTGRESQL_PASSWORD` | `postgres`   | Database password                            |
| `POSTGRESQL_DATABASE` | `discordbot` | Database name (created by this role)         |
| `POSTGRESQL_SCHEMA`   | `public,gw2` | Schemas used by the bot (created by Alembic) |
| `LOG_DIRECTORY`       | `/app/logs`  | In-container log path (mounted to host logs) |

> Note: `.env.dev` is configured for local development (`POSTGRESQL_HOST=127.0.0.1`, a local
> `LOG_DIRECTORY`), so host deployments must use `env_type: prod` (the default).

---

## Database Integration

The bot reuses the shared `postgres` container instead of running its own. The
`discordbot_alembic` service runs the bot's Alembic migrations, whose `env.py` connects as the
`postgres` superuser and itself creates the `discordbot` database (if missing) along with the
schemas (`public`, `gw2`) and tables. The role therefore does **not** create the database — it
only ensures the shared `postgres` container is healthy first. No dedicated database user is
created; the bot connects as the existing `postgres` superuser.

---

## Deployment Instructions

1. Ensure `files/.env.prod` has a valid `BOT_TOKEN` (and `OPENAI_API_KEY` if used).
2. Make sure the shared `postgres` container is running on the host.
3. Run the playbook, targeting the `discordbot` tag:

   ```bash
   cd dietpi/ansible
   ansible-playbook playbook.yml --tags discordbot
   ```

   The `docker` role runs automatically under the same tag. A full `ansible-playbook
   playbook.yml` run deploys `discordbot` after `postgres`.

4. Verify:

   ```bash
   docker ps | grep discordbot
   docker logs -f discordbot
   tail -f /var/log/discordbot/DiscordBot.log
   ```

---

## Directory Structure

```
/opt/containers/discordbot/
├── docker-compose.yml
├── Dockerfile
├── utilities/
│   ├── start.sh        # build + start containers
│   ├── stop.sh         # stop containers
│   └── update.sh       # update in place
├── logs/               # symlink -> /var/log/discordbot
├── .env                # uploaded from files/.env.<env_type>
└── [application files...]

/var/log/discordbot/
└── DiscordBot.log
```

---

## Troubleshooting

**Containers not starting**

```bash
docker logs discordbot
docker logs discordbot_alembic
cat /opt/containers/discordbot/.env        # confirm BOT_TOKEN and GPT api token are set
```

**Database connection / migration failures**

```bash
docker inspect --format='{{.State.Health.Status}}' postgres   # expect: healthy
docker exec -e PGPASSWORD=postgres postgres psql -U postgres -lqt | grep discordbot
docker logs discordbot_alembic
```

**Bot is up but offline in Discord**

```bash
# Almost always an invalid or revoked BOT_TOKEN.
grep BOT_TOKEN /opt/containers/discordbot/.env
docker logs discordbot | grep -i "login\|token\|unauthorized"
```

**Clone fails (SSH)**

```bash
# Run as the deploy user on the host:
ssh -T git@github.com         # should greet you by username
```
