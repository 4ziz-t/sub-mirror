#!/usr/bin/env bash
set -euo pipefail


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo
echo -e "${BOLD}${CYAN}════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Remnawave Subscription Mirror — Installer${NC}"
echo -e "${BOLD}${CYAN}════════════════════════════════════════════${NC}"
echo


if [[ $EUID -ne 0 ]]; then
    error "Запусти от root:\n  sudo bash install.sh\n  или\n  curl -fsSL ... | sudo bash"
fi


if ! command -v docker >/dev/null 2>&1; then
    warn "Docker не найден — устанавливаю..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker 2>/dev/null || true
    ok "Docker установлен"
else
    ok "Docker уже установлен"
fi

if ! docker compose version >/dev/null 2>&1; then
    warn "Плагин docker compose не найден — пробую установить..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
    fi
    if ! docker compose version >/dev/null 2>&1; then
        error "Не удалось установить docker compose. Установи вручную и запусти снова."
    fi
fi
ok "Docker Compose готов"


INSTALL_DIR="${INSTALL_DIR:-/opt/sub-mirror}"

echo
info "Директория установки: ${BOLD}${INSTALL_DIR}${NC}"
read -rp "Оставить? [Y/n]: " confirm_dir
confirm_dir=${confirm_dir:-Y}
if [[ ! "$confirm_dir" =~ ^[Yy]$ ]]; then
    read -rp "Введи путь: " INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR%/}"
fi

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"


SCRIPT_SOURCE=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$CANDIDATE/docker-compose.yml" && -d "$CANDIDATE/app" ]]; then
        SCRIPT_SOURCE="$CANDIDATE"
    fi
fi

if [[ -n "$SCRIPT_SOURCE" ]]; then
    info "Копирую файлы из локального репозитория..."
    rsync -a --exclude='.env' --exclude='Caddyfile' --exclude='.git' "$SCRIPT_SOURCE"/ "$INSTALL_DIR"/ 2>/dev/null \
        || cp -a "$SCRIPT_SOURCE"/. "$INSTALL_DIR"/
    ok "Файлы скопированы"
else
    REPO_URL="${REPO_URL:-}"
    if [[ -z "$REPO_URL" ]]; then
        echo
        warn "Скрипт запущен не из репозитория."
        echo "Укажи URL репозитория на GitHub (HTTPS), например:"
        echo "  https://github.com/Aziz961/sub-mirror.git"
        read -rp "REPO_URL: " REPO_URL
        REPO_URL=$(echo "$REPO_URL" | tr -d '[:space:]')
        [[ -n "$REPO_URL" ]] || error "REPO_URL обязателен"
    fi

    if [[ -d .git ]]; then
        info "Обновляю существующий репозиторий..."
        git pull --ff-only || warn "git pull не удался, продолжаю с текущими файлами"
    else
        # Если в папке уже что-то есть — клонируем во временную и переносим
        if [[ -n "$(ls -A . 2>/dev/null)" ]]; then
            TMP_DIR=$(mktemp -d)
            info "Клонирую $REPO_URL ..."
            git clone --depth 1 "$REPO_URL" "$TMP_DIR"
            rsync -a --exclude='.env' --exclude='Caddyfile' "$TMP_DIR"/ "$INSTALL_DIR"/
            rm -rf "$TMP_DIR"
        else
            info "Клонирую $REPO_URL ..."
            git clone --depth 1 "$REPO_URL" .
        fi
    fi
    ok "Репозиторий готов"
fi

[[ -f docker-compose.yml ]] || error "Не найден docker-compose.yml — что-то пошло не так"
[[ -d app ]] || error "Не найдена папка app/"


echo
echo -e "${CYAN}────────────────────────────────────────${NC}"
echo -e "  Настройка"
echo -e "${CYAN}────────────────────────────────────────${NC}"
echo

# Домен
while true; do
    read -rp "Домен (mirror.example.com): " DOMAIN
    DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')
    if [[ -n "$DOMAIN" ]]; then
        break
    fi
    warn "Домен не может быть пустым"
done

# ORIGIN_URL
while true; do
    read -rp "Ссылка на origin (подписка Remnawave, без / в конце): " ORIGIN_URL
    ORIGIN_URL=$(echo "$ORIGIN_URL" | sed 's|/*$||' | tr -d '[:space:]')
    if [[ "$ORIGIN_URL" =~ ^https?://.+ ]]; then
        break
    fi
    warn "Нужна ссылка вида https://sub.example.com"
done

TIMEOUT="${TIMEOUT:-30}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"


info "Создаю .env ..."
cat > .env << EOF
ORIGIN_URL=${ORIGIN_URL}
TIMEOUT=${TIMEOUT}
LOG_LEVEL=${LOG_LEVEL}
EOF
ok ".env создан"

info "Генерирую Caddyfile (домен: ${DOMAIN}) ..."
if [[ -f Caddyfile.template ]]; then
    sed "s|\${DOMAIN}|${DOMAIN}|g" Caddyfile.template > Caddyfile
else
    cat > Caddyfile << EOF
${DOMAIN} {
    encode gzip zstd

    reverse_proxy fastapi:8000 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up Host {host}
    }

    log {
        output stdout
        format console
    }
}
EOF
fi
ok "Caddyfile готов"


info "Останавливаю старые контейнеры (если есть)..."
docker compose down 2>/dev/null || true

info "Собираю образы и запускаю..."
docker compose up -d --build

echo
ok "Установка завершена!"
echo
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "  Mirror:   ${BOLD}https://${DOMAIN}${NC}"
echo -e "  Origin:   ${CYAN}${ORIGIN_URL}${NC}"
echo -e "  Папка:    ${CYAN}${INSTALL_DIR}${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo
echo "Команды:"
echo "  cd ${INSTALL_DIR}"
echo "  docker compose logs -f          # логи"
echo "  docker compose ps               # статус"
echo "  docker compose restart          # перезапуск"
echo "  docker compose down             # остановить"
echo
info "DNS: A-запись ${DOMAIN} → IP этого сервера"
info "Caddy сам получит SSL (Let's Encrypt). Порты 80 и 443 должны быть открыты."
echo
