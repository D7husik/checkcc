# CI/CD: как устроено

Репозиторий — тестовая площадка для CI/CD проекта LaboratoryIntegration (CRM). Здесь та же схема, что будет в CRM: FastAPI + MySQL + Alembic, CI на своём runner'е, тестовый стенд на Docker, прод без Docker.

## 1. Схема

```
runner ci        → проверки на каждый PR и push
runner test-env  → стенд  ~/checkcc-test : docker compose, порт 8001
runner prod-env  → прод   ~/checkcc-prod : systemd checkcc.service, порт 8002

feature/* ─push/PR─► CI
merge в test ─► CI + деплой стенда + статус deploy/test на коммите
PR test → main (merge commit) ─► проверка релиза, «готов к деплою»
Actions → Deploy prod → Run workflow ─► деплой на прод
```

В этом репозитории все три runner'а стоят на одной машине, а «MySQL заказчика» изображает контейнер `checkcc-prod-mysql` на 127.0.0.1:3307. Скрипты ходят в него по TCP обычными `mysql`/`mysqldump`, как в настоящую установленную базу.

## 2. Ветки

| Ветка | Что происходит |
|---|---|
| рабочие (`feature/*` и любые другие) | CI |
| `test` | CI → деплой на стенд → статус `deploy/test` |
| `main` | проверка релиза. Деплоя нет, пока человек не нажмёт кнопку |

Прямых коммитов в `main` быть не должно. В приватном репозитории на тарифе Free нет защиты веток, поэтому правило проверяет `scripts/check_release.sh`. Без её успеха прод не деплоится:
- коммит в `main` должен быть merge-коммитом;
- его код должен совпадать с коммитом из `test` (второй родитель);
- у этого коммита должен быть статус `deploy/test = success`.

## 3. Что проверяет CI (`.github/workflows/ci.yml`)

| Job | Что делает |
|---|---|
| `source-branch` | PR в `main` принимается только из `test` |
| `lint` | `ruff check`, `ruff format --check`, синтаксис shell-скриптов |
| `tests` | `pytest` на настоящей MySQL 8 (service-контейнер на случайном порту) |
| `migrations` | `scripts/ci_migrations.sh`: одна голова, upgrade на пустой БД, `alembic check`, откат всей истории и повторный upgrade |
| `image` | сборка Docker-образа |

## 4. Деплой

**Стенд (`scripts/deploy.sh test <sha>`):** сборка образа на самом стенде → MySQL → проверка, что БД под управлением Alembic → бэкап → миграции новым образом → замена контейнера `app` → ожидание `/health/ready` → при провале возврат предыдущего образа.

**Прод (`scripts/host/deploy.sh prod <sha>`):**
1. Код коммита распаковывается в `releases/<время>_<sha>`, зависимости ставятся строго по `uv.lock`.
2. Проверка, что БД под управлением Alembic.
3. Бэкап `mysqldump`. Если он не удался, ничего не меняется.
4. `alembic upgrade head` из нового релиза. Старая версия в это время работает. Если миграция упала, переключения не будет.
5. Ссылка `current` атомарно переключается на новый релиз, сервис перезапускается.
6. Ожидание `/health/ready` до 90 секунд. При провале `current` возвращается на предыдущий релиз, сервис перезапускается.

Процесс всегда один: фоновые задачи живут внутри приложения, поэтому `--workers` нельзя. При перезапуске сервис недоступен несколько секунд.

`/health/ready`:
- `ok` (200) — база доступна, схема совпадает с кодом;
- `degraded` (200) — база новее кода, так бывает после отката приложения;
- `fail` (503) — база недоступна или отстала от кода. В таком состоянии приложение не стартует.

## 5. Кнопки

**Actions → Deploy prod → Run workflow** (ветка `main`): деплой на прод.

**Actions → Ops → Run workflow:** окружение (`test` или `prod`) и действие:
- `status` — что задеплоено и как отвечает `/health/ready`;
- `backup` — бэкап сейчас;
- `rollback` — вернуть предыдущую версию. База не меняется.

Восстановление базы из бэкапа — только вручную на машине, с подтверждением:
```bash
scripts/host/restore_db.sh prod ~/checkcc-prod/backups/prod/<файл>.sql.gz
scripts/host/rollback.sh prod --to <релиз со схемой этого бэкапа>
```

## 6. Где что лежит

| Что | Где |
|---|---|
| Настройки приложения, пароли | `$APP_DIR/.lab_env` (600), только на машине |
| Доступ `mysql`/`mysqldump` на проде | `$APP_DIR/.my.cnf` (600) |
| Telegram и локальные переопределения | `$APP_DIR/.deploy.env` (600) |
| Настройки окружения без секретов | `deploy/test.env`, `deploy/prod.env` |
| Что задеплоено | `$APP_DIR/.deployed` |
| Бэкапы | `$APP_DIR/backups/<env>/` |
| Релизы (прод) | `$APP_DIR/releases/`, активный — `$APP_DIR/current` |

GitHub Secrets не используются. GitHub знает только код и временный `GITHUB_TOKEN` на каждый запуск.

## 7. Настройка с нуля

**Runner'ы.** Settings → Actions → Runners → New self-hosted runner → скопировать токен (живёт час):
```bash
deploy/runner/install.sh ci       ci       <токен>
deploy/runner/install.sh test-env test-env <токен>
deploy/runner/install.sh prod-env prod-env <токен>
sudo loginctl enable-linger "$USER"   # чтобы работали без открытой сессии
```

**Стенд.** Создать `~/checkcc-test/.lab_env` по образцу `.lab_env.example` и `.deploy.env` по образцу `deploy/deploy.env.example`, права 600.

**Прод.** Создать в `~/checkcc-prod` файлы `.lab_env` (`DATABASE_URL`), `.my.cnf` (секция `[client]`: host, port, user, password), `.deploy.env`. Нужны `uv`, `mysql` и `mysqldump`. Затем:
```bash
scripts/host/setup.sh prod
```

**Безопасность.** Runner выполняет код из репозитория, поэтому репозиторий должен быть приватным, а job'ы `prod-env` запускаться только из `main`.

## 8. Типичные ситуации

| Ситуация | Что делать |
|---|---|
| Job висит в Queued | runner выключен: Settings → Actions → Runners, `systemctl --user status github-runner-<имя>` |
| `check`: «is not a merge» или «differs from test» | в `main` попало что-то мимо `test`. Влить `main` в `test`, дождаться `deploy-test`, снова PR `test → main` (merge commit) |
| `check`: «has not been deployed» | деплой на стенд не прошёл или ещё идёт |
| Миграция упала | сервис не переключался. DDL в MySQL не откатывается, поэтому смотрим схему, при необходимости восстанавливаем из бэкапа из сообщения |
| Статус `degraded` | приложение откатили, а миграция осталась. Новая версия или `alembic downgrade` это исправят |

## 9. Перенос в CRM

| Здесь | В CRM |
|---|---|
| `deploy/prod.env`: `~/checkcc-prod`, порт 8002, `SERVICE_MANAGER=user` | `/opt/laboratoryintegration`, порт 8000, `SERVICE_MANAGER=system` + `deploy/sudoers.example`, пользователь `deployer` |
| runner'ы как user-сервисы на одной машине | `prod-env` на машине заказчика через `svc.sh install deployer`, `ci` и `test-env` у нас |
| MySQL заказчика = контейнер | настоящая установленная MySQL, проверить права пользователя на `mysqldump` и DDL |
| образ собирается на стенде | то же: GHCR в CRM больше не нужен, `ghcr-cleanup` и вход в GHCR убираем |
| `check_release.sh` вместо защиты веток | то же, если репозиторий приватный на Free. Если есть Pro/Team, дополнительно включить rulesets |
| нет legacy-схемы | добавить `scripts/host/align_schema.sh`, `stamp_baseline.sh` и список legacy-ревизий из CRM |

До переноса CRM-ветку нужно синхронизировать с `main`: там 12 новых коммитов и миграция `f2a7c9d41e83` в старой цепочке.
