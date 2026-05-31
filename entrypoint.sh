#!/bin/bash
set -e

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "======================================================"
log " claude-workstation inicializando"
log " Hostname : $(hostname)"
log " Data/hora: $(date '+%Y-%m-%d %H:%M:%S %Z')"
log "======================================================"

# ─── [1/3] machine-id ──────────────────────────────────────────────────────────
log ""
log "[1/3] machine-id — persistência de sessão OAuth"
MACHINE_ID_STORE="/home/claude/.claude/.machine-id"
if [ -f "$MACHINE_ID_STORE" ]; then
    PREV_ID="$(cat /etc/machine-id)"
    cp "$MACHINE_ID_STORE" /etc/machine-id
    chmod 444 /etc/machine-id
    RESTORED_ID="$(cat /etc/machine-id)"
    if [ "$PREV_ID" = "$RESTORED_ID" ]; then
        log "  OK  machine-id restaurado (sem alteração): $RESTORED_ID"
    else
        log "  OK  machine-id restaurado: $PREV_ID -> $RESTORED_ID"
    fi
elif [ -d "/home/claude/.claude" ]; then
    FIRST_ID="$(cat /etc/machine-id)"
    cp /etc/machine-id "$MACHINE_ID_STORE"
    chown claude:claude "$MACHINE_ID_STORE"
    log "  OK  primeiro boot — machine-id salvo: $FIRST_ID"
else
    log "  AVISO  diretório ~/.claude não encontrado — machine-id não persistido"
fi
# /var/lib/dbus/machine-id é um arquivo separado na imagem Debian e fica dessincronizado
# a cada container novo. Claude Code pode ler o device fingerprint via D-Bus, o que causaria
# reautenticação mesmo com /etc/machine-id correto. Forçamos um symlink para mantê-los em sincronia.
if [ -d "/var/lib/dbus" ]; then
    DBUS_ID_FILE="/var/lib/dbus/machine-id"
    DBUS_CURRENT="$(cat "$DBUS_ID_FILE" 2>/dev/null || echo '')"
    EXPECTED_ID="$(cat /etc/machine-id)"
    if [ "$DBUS_CURRENT" != "$EXPECTED_ID" ]; then
        ln -sf /etc/machine-id "$DBUS_ID_FILE"
        log "  OK  /var/lib/dbus/machine-id sincronizado: $DBUS_CURRENT -> $EXPECTED_ID"
    else
        log "  OK  /var/lib/dbus/machine-id já sincronizado: $EXPECTED_ID"
    fi
fi

# ─── [2/3] GSD bootstrap ───────────────────────────────────────────────────────
log ""
log "[2/3] GSD (get-shit-done-redux) — bootstrap de skills"
if [ ! -f "/home/claude/.claude/skills/gsd-help/SKILL.md" ] && \
   [ ! -f "/home/claude/.claude/commands/gsd-help.md" ]; then
    log "  GSD não detectado — executando bootstrap..."
    if su - claude -c \
        'export NVM_DIR=/home/claude/.nvm \
         && export CLAUDE_CONFIG_DIR=/home/claude/.claude \
         && . "$NVM_DIR/nvm.sh" \
         && get-shit-done-redux --claude --global --portable-hooks'; then
        log "  OK  GSD instalado com sucesso"
    else
        log "  AVISO  bootstrap do GSD falhou — container iniciará sem GSD"
    fi
else
    log "  OK  GSD já instalado — bootstrap ignorado"
fi

# ─── [3/3] gitconfig symlinks ──────────────────────────────────────────────────
#
# Symlinks são criados com dono claude:claude (-h opera no próprio symlink).
# Sem isso, git vê o symlink como pertencente ao root via lstat() e pode
# ignorar os blocos includeIf por razões de segurança (CVE-2022-24765).
#
log ""
log "[3/3] gitconfig — symlinks de perfis de usuário Git"
if [ -d "/mnt/gitconfig" ]; then
    linked=0
    for f in /mnt/gitconfig/.git*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        target="/home/claude/$name"
        ln -sf "$f" "$target"
        chown -h claude:claude "$target"
        log "  OK  $name -> $f"
        linked=$((linked + 1))
    done
    if [ "$linked" -eq 0 ]; then
        log "  AVISO  nenhum arquivo .git* encontrado em /mnt/gitconfig"
    else
        log "  Total: $linked symlink(s) configurado(s)"
    fi
else
    log "  INFO  /mnt/gitconfig não está montado — symlinks ignorados"
fi

# ─── handoff para sshd ─────────────────────────────────────────────────────────
log ""
log "======================================================"
log " Inicialização concluída — iniciando sshd"
log "======================================================"
exec /usr/sbin/sshd -D
