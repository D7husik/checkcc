import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.db import get_db
from app.health import router as health_router
from app.models import Item
from app.schema_check import ensure_schema

Db = Annotated[Session, Depends(get_db)]


def setup_logging() -> None:
    # Relative on purpose, as in LaboratoryIntegration: every release links logs/ to one place.
    Path("logs").mkdir(exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[logging.StreamHandler(), logging.FileHandler("logs/app.log")],
    )


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    setup_logging()
    ensure_schema()
    yield


app = FastAPI(title="CI demo", version="0.2.0", lifespan=lifespan)
app.include_router(health_router)


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class ItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Hello from CI demo"}


@app.post("/items", status_code=status.HTTP_201_CREATED)
def create_item(item: ItemIn, db: Db) -> ItemOut:
    row = Item(name=item.name)
    db.add(row)
    db.commit()
    return ItemOut.model_validate(row)


@app.get("/items/{item_id}")
def get_item(item_id: int, db: Db) -> ItemOut:
    row = db.get(Item, item_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Item not found")
    return ItemOut.model_validate(row)
