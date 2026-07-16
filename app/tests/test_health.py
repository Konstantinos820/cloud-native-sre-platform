from fastapi.testclient import TestClient
from _pytest.monkeypatch import MonkeyPatch
from httpx import Response
import src.main as main_module


def test_health_live_does_not_touch_db(client: TestClient) -> None:
    response: Response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}


def test_health_ready_ok_when_db_reachable(client: TestClient, monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setattr("src.main.check_db_connection", lambda: True)
    response: Response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["database"] == "reachable"


def test_health_ready_returns_503_when_db_unreachable(client: TestClient, monkeypatch: MonkeyPatch) -> None:
    monkeypatch.setattr("src.main.check_db_connection", lambda: False)
    response: Response = client.get("/health/ready")
    assert response.status_code == 503
    assert response.json()["database"] == "unreachable"


def test_health_startup_reflects_app_state(client: TestClient, monkeypatch: MonkeyPatch) -> None:
    # 1. Έλεγχος όταν το startup έχει ολοκληρωθεί
    monkeypatch.setitem(main_module.app_state, "startup_complete", True)
    response_ok: Response = client.get("/health/startup")
    assert response_ok.status_code == 200

    # 2. Έλεγχος όταν το startup ΔΕΝ έχει ολοκληρωθεί
    monkeypatch.setitem(main_module.app_state, "startup_complete", False)
    response_fail: Response = client.get("/health/startup")
    assert response_fail.status_code == 503