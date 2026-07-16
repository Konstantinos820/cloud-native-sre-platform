from typing import Any
from fastapi.testclient import TestClient
from httpx import Response


def test_create_and_get_user(client: TestClient) -> None:
    response: Response = client.post(
        "/users", json={"email": "ada@example.com", "full_name": "Ada Lovelace"}
    )
    assert response.status_code == 201
    body: dict[str, Any] = response.json()
    assert body["email"] == "ada@example.com"
    assert "id" in body

    user_id: int = body["id"]
    response = client.get(f"/users/{user_id}")
    assert response.status_code == 200
    assert response.json()["email"] == "ada@example.com"


def test_duplicate_email_returns_409(client: TestClient) -> None:
    client.post("/users", json={"email": "dup@example.com"})
    response: Response = client.post("/users", json={"email": "dup@example.com"})
    assert response.status_code == 409


def test_get_missing_user_returns_404(client: TestClient) -> None:
    response: Response = client.get("/users/999999")
    assert response.status_code == 404


def test_user_registration_increments_business_metric(client: TestClient) -> None:
    metrics_before: str = client.get("/metrics").text
    client.post("/users", json={"email": "metric-check@example.com"})
    metrics_after: str = client.get("/metrics").text

    assert "user_registrations_total" in metrics_after
    assert metrics_after != metrics_before