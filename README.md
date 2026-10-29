# CI demo: FastAPI + GitHub Actions

Тестовый проект, на котором показан CI-пайплайн. Потом эту схему переносим на основной проект.

## Что делает CI

Пайплайн запускается при push в `main`, при любом pull request и вручную (Actions → CI → Run workflow).

```
┌──────────────┐     ┌──────────────────────────────┐
│     lint     │ ──▶ │  docker build & smoke check  │
└──────────────┘     └──────────────────────────────┘
```

1. **lint**. Ставит Python 3.12 и ruff, затем проверяет:
   - `ruff check .`: ошибки в коде, неиспользуемые импорты, порядок импортов;
   - `ruff format --check .`: что код отформатирован.
2. **docker** запускается, только если lint прошёл:
   - собирает Docker-образ (слои кэшируются, повторная сборка идёт быстро);
   - запускает контейнер и в течение 30 секунд ждёт, пока `GET /health` ответит `{"status": "ok"}`;
   - если что-то упало, выводит логи контейнера.

Тестов пока нет. Когда появятся, они станут отдельным job'ом между `lint` и `docker`.

## Запуск локально

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt

uvicorn app.main:app --reload
# http://localhost:8000/docs (Swagger)
```

Те же проверки, что делает CI:

```bash
ruff check .
ruff format --check .        # чтобы автоматически отформатировать: ruff format .

docker build -t cicdcrm:ci .
docker run -d --name app -p 8000:8000 cicdcrm:ci
curl localhost:8000/health
docker rm -f app
```

## Первый push на GitHub

1. Создать пустой репозиторий на GitHub, без README и .gitignore.
2. Выполнить:

```bash
git add .
git commit -m "CI demo: FastAPI + GitHub Actions"
git remote add origin git@github.com:<user>/<repo>.git
git push -u origin main
```

3. Открыть вкладку **Actions**: там появится запуск workflow **CI**.

## Сценарий демо для тимлида

1. **Зелёный пайплайн.** Сделать push. Оба job'а, `lint` и `docker`, становятся зелёными.
2. **Сломать линт.** Создать ветку, добавить в `app/main.py` неиспользуемый импорт (например `import os`) и открыть PR.
   Job `lint` падает и подсвечивает строку прямо в PR, а `docker` не запускается.
3. **Починить.** Удалить импорт и сделать push в ту же ветку. Пайплайн снова зелёный, PR можно мержить.
4. *(дополнительно)* **Сломать запуск.** Поменять в `Dockerfile` `app.main:app` на `app.main:wrong`.
   Линт пройдёт, но smoke check упадёт, и в логах будет видна причина.

Чтобы запретить мерж с красным CI: Settings → Branches (или Rules) → правило для `main` →
Require status checks to pass → выбрать `Lint (ruff)` и `Docker build & smoke check`.

## Перенос на основной проект

Скопировать:
- `.github/workflows/ci.yml`
- `pyproject.toml` (секцию `[tool.ruff]`)
- `requirements-dev.txt`
- `Dockerfile` и `.dockerignore`, если в проекте их ещё нет

Проверить и поменять под проект:
- [ ] версию Python (`python-version` в `ci.yml` и `FROM` в `Dockerfile`);
- [ ] путь к приложению (`app.main:app` в `CMD` Dockerfile);
- [ ] порт (`8000` в `Dockerfile` и в шагах `docker run` и `curl`);
- [ ] эндпоинт health-check. Если его нет, добавить простой `GET /health`;
- [ ] переменные окружения и сервисы, без которых приложение не стартует (БД, Redis и т.п.).
  Их нужно передать в `docker run -e ...` или поднять через `services:` в job'е;
- [ ] первый запуск `ruff check .` на большом проекте может выдать много ошибок.
  Сначала прогнать `ruff check --fix .` и `ruff format .` отдельным коммитом.
