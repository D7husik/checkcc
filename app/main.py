from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="CI demo", version="0.1.0")


class Item(BaseModel):
    id: int
    name: str


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "Hello from CI demo"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/items/{item_id}")
def get_item(item_id: int) -> Item:
    return Item(id=item_id, name=f"item-{item_id}")
import os