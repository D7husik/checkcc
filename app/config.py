import os
from pathlib import Path

from dotenv import load_dotenv

# Same order as LaboratoryIntegration: LAB_ENV_PATH, then ./.lab_env. Values already
# in the environment win, which is how Docker Compose and the tests override them.
env_path = os.getenv("LAB_ENV_PATH")
if env_path and Path(env_path).exists():
    load_dotenv(env_path)
elif Path(".lab_env").exists():
    load_dotenv(".lab_env")

DATABASE_URL = os.getenv("DATABASE_URL", "")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set: put it in .lab_env or the environment")
