# checkcc: тестовая площадка CI/CD

Небольшое приложение FastAPI + MySQL + Alembic, на котором отлаживается CI/CD для проекта LaboratoryIntegration: CI на своём runner'е, тестовый стенд на Docker, прод без Docker (systemd), запуск деплоя кнопкой.

- Как всё устроено: [docs/CI_CD.md](docs/CI_CD.md)
- Сценарий показа: [DEMO.md](DEMO.md)

## Запуск локально

```bash
cp .lab_env.example .lab_env   # заполнить пароли
docker compose up --build      # app на :8000, mysql
# http://localhost:8000/docs
```

Без Docker: `uv sync`, нужна MySQL и `DATABASE_URL` в `.lab_env`, затем `uv run alembic upgrade head` и `uv run uvicorn app.main:app --reload`.

## Проверки, как в CI

```bash
uv sync
uv run ruff check .
uv run ruff format --check .
TEST_DATABASE_URL=mysql+pymysql://user:pass@127.0.0.1:3306/checkcc_test uv run pytest
```

Новая миграция: `uv run alembic revision --autogenerate -m "описание"`, файл кладётся в `alembic/versions/`.
