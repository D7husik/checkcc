def test_create_and_read(client):
    created = client.post("/items", json={"name": "пробирка"})
    assert created.status_code == 201
    item = created.json()
    assert item["name"] == "пробирка"
    assert client.get(f"/items/{item['id']}").json() == item


def test_note_is_stored(client):
    created = client.post("/items", json={"name": "штатив", "note": "хрупкое"}).json()
    assert client.get(f"/items/{created['id']}").json()["note"] == "хрупкое"


def test_read_missing(client):
    assert client.get("/items/999999999").status_code == 404


def test_name_is_validated(client):
    assert client.post("/items", json={"name": ""}).status_code == 422
