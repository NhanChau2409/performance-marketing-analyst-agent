"""Tests for improvement 5: sqlglot-based SQL validation in query_data."""

import pytest
from marketing_agent.tools.query_data import _validate_sql


# --- valid queries return None ---


def test_simple_select_is_valid():
    assert _validate_sql("SELECT * FROM campaigns") is None


def test_select_with_aggregation_is_valid():
    assert _validate_sql(
        "SELECT platform, SUM(spend) AS total_spend FROM daily_metrics GROUP BY platform"
    ) is None


def test_select_with_where_and_limit_is_valid():
    assert _validate_sql(
        "SELECT id, name FROM campaigns WHERE active = true ORDER BY name LIMIT 10"
    ) is None


def test_cte_with_select_is_valid():
    assert _validate_sql(
        "WITH top AS (SELECT platform, SUM(spend) s FROM daily_metrics GROUP BY platform) "
        "SELECT * FROM top ORDER BY s DESC"
    ) is None


def test_union_is_valid():
    assert _validate_sql(
        "SELECT platform FROM daily_metrics UNION SELECT platform FROM campaigns"
    ) is None


def test_union_all_is_valid():
    assert _validate_sql(
        "SELECT id FROM campaigns UNION ALL SELECT id FROM campaigns"
    ) is None


def test_subquery_in_from_is_valid():
    assert _validate_sql(
        "SELECT * FROM (SELECT platform, COUNT(*) cnt FROM daily_metrics GROUP BY platform) sub"
    ) is None


# --- no false positives on write-like column or table names ---


def test_column_named_update_time_is_not_flagged():
    assert _validate_sql("SELECT update_time FROM campaigns") is None


def test_column_named_deleted_at_is_not_flagged():
    assert _validate_sql("SELECT deleted_at FROM users LIMIT 5") is None


def test_column_named_insert_count_is_not_flagged():
    assert _validate_sql("SELECT insert_count FROM audit_log") is None


def test_table_named_drop_log_is_not_flagged():
    assert _validate_sql("SELECT * FROM drop_log LIMIT 10") is None


# --- write operations are rejected ---


def test_rejects_insert():
    assert _validate_sql("INSERT INTO campaigns VALUES (1, 'test')") is not None


def test_rejects_update():
    assert _validate_sql("UPDATE campaigns SET active = false WHERE id = 1") is not None


def test_rejects_delete():
    assert _validate_sql("DELETE FROM campaigns WHERE id = 1") is not None


def test_rejects_drop_table():
    assert _validate_sql("DROP TABLE campaigns") is not None


def test_rejects_create_table():
    assert _validate_sql("CREATE TABLE tmp (id INT)") is not None


def test_rejects_truncate():
    assert _validate_sql("TRUNCATE TABLE campaigns") is not None


def test_rejects_alter_table():
    assert _validate_sql("ALTER TABLE campaigns ADD COLUMN x INT") is not None


# --- write operations hidden inside CTEs are rejected ---


def test_rejects_delete_inside_cte():
    # Old regex validator would miss this because the outer statement starts with WITH
    assert _validate_sql(
        "WITH deleted AS (DELETE FROM campaigns RETURNING id) SELECT * FROM deleted"
    ) is not None


def test_rejects_insert_inside_cte():
    assert _validate_sql(
        "WITH ins AS (INSERT INTO t VALUES (1) RETURNING id) SELECT * FROM ins"
    ) is not None


# --- error cases ---


def test_rejects_invalid_sql_syntax():
    result = _validate_sql("SELEC * FORM campaigns")
    assert result is not None
    assert "Invalid SQL" in result or result is not None  # any error message is fine


def test_rejects_multiple_statements():
    assert _validate_sql("SELECT 1; SELECT 2") is not None


def test_rejects_empty_input():
    result = _validate_sql("")
    assert result is not None


def test_error_message_is_a_string():
    result = _validate_sql("DELETE FROM t")
    assert isinstance(result, str)
    assert len(result) > 0
