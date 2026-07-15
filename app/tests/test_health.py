def test_health_live_does_not_touch_db(client):
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}


def test_health_ready_ok_when_db_reachable(client, monkeypatch):
    monkeypatch.setattr("src.main.check_db_connection", lambda: True)
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["database"] == "reachable"


def test_health_ready_returns_503_when_db_unreachable(client, monkeypatch):
    monkeypatch.setattr("src.main.check_db_connection", lambda: False)
    response = client.get("/health/ready")
    assert response.status_code == 503
    assert response.json()["database"] == "unreachable"


def test_health_startup_reflects_app_state(client, monkeypatch):
    import src.main as main_module

    monkeypatch.setitem(main_module.app_state, "startup_complete", True)
    response = client.get("/health/startup")
    assert response.status_code == 200

    monkeypatch.setitem(main_module.app_state, "startup_complete", False)
    response = client.get("/health/startup")
    assert response.status_code == 503