#!/usr/bin/env bash
# install_metasploit.sh
# Installs Metasploit Framework on Fedora 43 using a remote PostgreSQL DB.
# Fully unattended — no prompts.
# Usage: sudo bash install_metasploit.sh

set -euo pipefail

# ─── CONFIG ──────────────────────────────────────────────────────────────────
DB_HOST="192.168.1.100"
DB_PORT="5432"
DB_NAME="msf"
DB_USER="msf"
DB_PASS="msf"

PG_ADMIN_USER="postgres"
PG_ADMIN_PASS="postgres"

MSF_SYSTEM_CONF="/usr/share/metasploit-framework/config/database.yml"
REPO_FILE="/etc/yum.repos.d/metasploit.repo"

# Resolve the real user's home dir even when running under sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
MSF_USER_CONF="${REAL_HOME}/.msf4/database.yml"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[-]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}══${NC} $*"; }

# ── Helper: run psql as postgres admin ───────────────────────────────────────
psql_admin() {
    PGPASSWORD="${PG_ADMIN_PASS}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${PG_ADMIN_USER}" \
        -d postgres \
        "$@"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || error "Run this script as root (sudo)."
}

check_fedora() {
    grep -qi "fedora" /etc/os-release || warn "Not Fedora — proceeding anyway."
    local ver
    ver=$(grep -oP '(?<=^VERSION_ID=)\d+' /etc/os-release 2>/dev/null || echo "unknown")
    info "Detected Fedora ${ver}"
}

# ── Connectivity ──────────────────────────────────────────────────────────────
check_db_reachable() {
    step "Checking connectivity to ${DB_HOST}:${DB_PORT}"
    if command -v nc &>/dev/null; then
        nc -zw5 "${DB_HOST}" "${DB_PORT}" \
            || error "Cannot reach ${DB_HOST}:${DB_PORT}. Check firewall / DB server."
    else
        timeout 5 bash -c ">/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null \
            || error "Cannot reach ${DB_HOST}:${DB_PORT}. Check firewall / DB server."
    fi
    info "Remote DB is reachable."
}

# ── Install psql client if missing ───────────────────────────────────────────
ensure_psql_client() {
    step "Checking psql client"
    if ! command -v psql &>/dev/null; then
        info "psql not found — installing postgresql client ..."
        dnf install -y postgresql || error "Failed to install postgresql client."
    else
        info "psql client already available."
    fi
}

# ── Remote DB provisioning ───────────────────────────────────────────────────
setup_remote_db() {
    step "Provisioning remote database on ${DB_HOST}"

    info "Verifying admin connection as '${PG_ADMIN_USER}' ..."
    psql_admin -c '\conninfo' > /dev/null \
        || error "Could not connect to ${DB_HOST} as '${PG_ADMIN_USER}'. Check PG_ADMIN_PASS."

    local role_exists
    role_exists=$(psql_admin -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}';")

    if [[ "${role_exists}" == "1" ]]; then
        info "Role '${DB_USER}' already exists — updating password."
        psql_admin -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" > /dev/null
    else
        info "Creating role '${DB_USER}' ..."
        psql_admin -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" > /dev/null
    fi

    local db_exists
    db_exists=$(psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';")

    if [[ "${db_exists}" == "1" ]]; then
        info "Database '${DB_NAME}' already exists — skipping creation."
    else
        info "Creating database '${DB_NAME}' owned by '${DB_USER}' ..."
        psql_admin -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" > /dev/null
    fi

    psql_admin -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" > /dev/null
    info "Remote DB provisioning complete."
}

# ── Repo + Install ────────────────────────────────────────────────────────────
add_metasploit_repo() {
    step "Configuring Metasploit DNF repo"
    cat > "${REPO_FILE}" <<EOF
[metasploit]
name=Metasploit Framework
baseurl=https://rpm.metasploit.com/
enabled=1
gpgcheck=0
EOF
    info "Repo file written to ${REPO_FILE} (gpgcheck disabled — Rapid7 ships a detached .asc, not a keyring)."
}

install_metasploit() {
    step "Installing Metasploit Framework"
    if command -v msfconsole &>/dev/null; then
        info "Already installed — skipping dnf install."
        return
    fi
    dnf install -y metasploit-framework || error "DNF install failed."
    info "metasploit-framework installed."
}

# ── Database config ───────────────────────────────────────────────────────────
write_db_yml() {
    local path="$1"
    local owner="$2"
    local dir
    dir=$(dirname "${path}")

    mkdir -p "${dir}"
    chown "${owner}:${owner}" "${dir}"
    cat > "${path}" <<EOF
# Metasploit database config — managed by install_metasploit.sh
# Remote PostgreSQL: ${DB_HOST}:${DB_PORT}
# Local DB: none

production:
  adapter: postgresql
  database: ${DB_NAME}
  username: ${DB_USER}
  password: "${DB_PASS}"
  host: ${DB_HOST}
  port: ${DB_PORT}
  pool: 75
  timeout: 5
EOF
    chmod 600 "${path}"
    chown "${owner}:${owner}" "${path}"
    info "database.yml written (600) → ${path}"
}

write_database_yml() {
    step "Writing Metasploit database.yml"
    # System-wide — owned by root
    write_db_yml "${MSF_SYSTEM_CONF}" "root"
    # User-level — owned by the real user invoking sudo (MSF reads this at runtime)
    write_db_yml "${MSF_USER_CONF}" "${REAL_USER}"
    info "Config written for user '${REAL_USER}' (${MSF_USER_CONF})"
}

# ── Validation ────────────────────────────────────────────────────────────────
test_msf_db_connection() {
    step "Validating Metasploit DB connection"
    if PGPASSWORD="${DB_PASS}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -c '\conninfo' > /dev/null; then
        info "Connection as '${DB_USER}' to '${DB_NAME}' successful."
    else
        error "Could not connect as '${DB_USER}'. Check pg_hba.conf on ${DB_HOST}."
    fi
}

smoke_test() {
    step "msfconsole smoke test"
    if sudo -u "${REAL_USER}" msfconsole -q -x "db_status; exit" 2>/dev/null; then
        info "Smoke test passed."
    else
        warn "Smoke test had issues — verify manually: msfconsole -q -x 'db_status; exit'"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Metasploit Framework — Fedora 43 + Remote PostgreSQL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    check_root
    check_fedora
    check_db_reachable
    ensure_psql_client
    setup_remote_db
    add_metasploit_repo
    install_metasploit
    write_database_yml
    test_msf_db_connection
    smoke_test

    echo
    info "All done. Launch with: msfconsole"
    info "Inside msfconsole run 'db_status' to confirm the remote connection."
}

main "$@"
