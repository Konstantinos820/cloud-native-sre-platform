import importlib
import sys
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


def test_init_db_with_otel_enabled(monkeypatch: pytest.MonkeyPatch) -> None:
    import src.config
    import src.database
    import src.tracing

    monkeypatch.setattr(src.config.settings, "OTEL_TRACES_ENABLED", True)

    mock_inst_instance = MagicMock()
    mock_sql_cls = MagicMock(return_value=mock_inst_instance)

    with patch(
        "opentelemetry.instrumentation.sqlalchemy.SQLAlchemyInstrumentor",
        mock_sql_cls,
    ):
        src.tracing.setup_tracing()
        importlib.reload(src.database)
        mock_inst_instance.instrument.assert_called_once()

    # Revert
    monkeypatch.setattr(src.config.settings, "OTEL_TRACES_ENABLED", False)
    src.tracing.setup_tracing()
    importlib.reload(src.database)


def test_main_with_otel_enabled(monkeypatch: pytest.MonkeyPatch) -> None:
    import src.config
    import src.database
    import src.tracing

    monkeypatch.setattr(src.config.settings, "OTEL_TRACES_ENABLED", True)

    mock_instrument_app = MagicMock()
    mock_fastapi_cls = MagicMock()
    mock_fastapi_cls.instrument_app = mock_instrument_app
    mock_fastapi_cls.return_value.instrument_app = mock_instrument_app

    mock_sql_cls = MagicMock()

    with (
        patch(
            "opentelemetry.instrumentation.fastapi.FastAPIInstrumentor",
            mock_fastapi_cls,
        ),
        patch(
            "opentelemetry.instrumentation.sqlalchemy.SQLAlchemyInstrumentor",
            mock_sql_cls,
        ),
        patch("src.database.init_db"),
    ):
        src.tracing.setup_tracing()
        importlib.reload(src.database)

        main_mod: Any = sys.modules.get("src.main")
        if main_mod is not None:
            importlib.reload(main_mod)
        else:
            importlib.import_module("src.main")

        assert mock_instrument_app.call_count >= 1

    # Revert
    monkeypatch.setattr(src.config.settings, "OTEL_TRACES_ENABLED", False)
    src.tracing.setup_tracing()
    importlib.reload(src.database)

    main_mod_revert: Any = sys.modules.get("src.main")
    if main_mod_revert is not None:
        importlib.reload(main_mod_revert)


def test_main_endpoints_edge_cases(client: TestClient) -> None:
    # Cover line 201 (list users)
    res_list = client.get("/users")
    assert res_list.status_code == 200

    # Cover line 214 (404 on get user)
    res_user = client.get("/users/999999999")
    assert res_user.status_code == 404
    assert res_user.json()["detail"] == "User not found"


def test_lifespan_handles_init_db_failure() -> None:
    import asyncio

    import src.main as main

    async def run_lifespan() -> None:
        main.app_state["startup_complete"] = False

        with patch("src.main.init_db", side_effect=Exception("DB unavailable")):
            async with main.lifespan(main.app):
                assert main.app_state["startup_complete"] is False

    asyncio.run(run_lifespan())


def test_lifespan_success() -> None:
    import src.main as main

    main.app_state["startup_complete"] = False

    with patch("src.main.init_db") as mock_init_db:
        with TestClient(main.app):
            pass

    mock_init_db.assert_called_once()
    assert main.app_state["startup_complete"] is True


def test_root_endpoint(client: TestClient) -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json()["service"] == "sre-platform-api"
    assert response.json()["version"] == "0.1.0"
