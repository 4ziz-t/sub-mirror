# Remnawave Subscription Mirror

Лёгкий reverse-proxy для подписок **Remnawave**.

Твой домен → прокси → оригинальная подписка.

---

## Установка одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/Aziz961/sub-mirror/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

Скрипт спросит:

1. **Домен** — например `mirror.example.com` или `201.24.63.89.nip.io`
2. **Ссылку на origin** — URL подписки Remnawave (без `/` в конце)

---

## Установка из клона

```bash
git clone https://github.com/Aziz961/sub-mirror.git
cd sub-mirror
sudo bash install.sh
```

---

## Команды после установки

```bash
cd /opt/sub-mirror

docker compose logs -f       # логи
docker compose ps            # статус
docker compose restart       # перезапуск
docker compose down          # остановить
docker compose up -d --build # обновить после git pull
```

---

## Как это работает

1. Клиент запрашивает `https://зеркало-домен/<uuid>`
2. Caddy принимает HTTPS и проксирует на FastAPI
3. FastAPI ходит на `ORIGIN_URL/<uuid>` и возвращает ответ как есть

---

## Переменные окружения (.env)

| Переменная   | Описание                          | По умолчанию |
|--------------|-----------------------------------|--------------|
| ORIGIN_URL   | URL оригинальной подписки         | — (обязательно) |
| TIMEOUT      | Таймаут запросов к origin (сек)   | 30           |
| LOG_LEVEL    | Уровень логов (DEBUG/INFO/WARN)   | INFO         |
