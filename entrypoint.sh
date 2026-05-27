#!/bin/bash
set -e

# Persist machine-id across container recreations so the Claude Code OAuth session survives
# image upgrades. Each new container gets a fresh /etc/machine-id, which changes the device
# fingerprint and invalidates the stored refresh token. We save the first-seen ID into the
# .claude volume and restore it on every subsequent start.
MACHINE_ID_STORE="/home/claude/.claude/.machine-id"
if [ -f "$MACHINE_ID_STORE" ]; then
    cp "$MACHINE_ID_STORE" /etc/machine-id
    chmod 444 /etc/machine-id
elif [ -d "/home/claude/.claude" ]; then
    cp /etc/machine-id "$MACHINE_ID_STORE"
    chown claude:claude "$MACHINE_ID_STORE"
fi

# Bootstrap GSD into ~/.claude volume on first run (or if volume was recreated)
if [ ! -f "/home/claude/.claude/skills/gsd-help/SKILL.md" ] && [ ! -f "/home/claude/.claude/commands/gsd-help.md" ]; then
    su - claude -c 'export NVM_DIR=/home/claude/.nvm && export CLAUDE_CONFIG_DIR=/home/claude/.claude && . "$NVM_DIR/nvm.sh" && get-shit-done-redux --claude --global --portable-hooks' || echo "[entrypoint] GSD bootstrap failed — container will still start"
fi

exec /usr/sbin/sshd -D
