from unittest.mock import MagicMock, patch

from sqlalchemy.exc import OperationalError
from src.database import check_db_connection, db_session_scope, get_db


def test_db_session_scope():
    with db_session_scope() as session:
        assert session is not None


def test_get_db():
    gen = get_db()
    session = next(gen)
    assert session is not None
    try:
        gen.send(None)
    except StopIteration:
        pass


def test_check_db_connection_success():
    with patch("src.database.engine.connect") as mock_connect:
        mock_conn = MagicMock()
        mock_connect.return_value.__enter__.return_value = mock_conn
        result = check_db_connection()
        assert result is True


def test_check_db_connection_failure():
    with patch("src.database.engine.connect") as mock_connect:
        mock_connect.side_effect = OperationalError(
            "statement", "params", Exception("DB connection error")
        )
        result = check_db_connection()
        assert result is False
