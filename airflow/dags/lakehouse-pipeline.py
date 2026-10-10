from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.common.sql.operators.sql import (
    SQLExecuteQueryOperator,
)

with DAG(
    dag_id="lakehouse_pipeline",
    description="Bronze -> Silver -> Gold. Assumes that bronze is alreay created",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args={
        "owner": "data-engeneering",
        "retries": 1,
        "retry_delay": timedelta(minutes=2),
    },
    template_searchpath=["/opt/airflow/sql"],
    tags=["lakehouse", "trino"],
) as dag:
    create_silver = SQLExecuteQueryOperator(
        task_id="create_silver", conn_id="trino", sql="silver/init.sql"
    )
    build_silver = SQLExecuteQueryOperator(
        task_id="build_silver", conn_id="trino", sql="silver/aggregate.sql"
    )

    create_gold = SQLExecuteQueryOperator(
        task_id="create_gold", conn_id="trino", sql="gold/init.sql"
    )
    build_gold = SQLExecuteQueryOperator(
        task_id="build_gold", conn_id="trino", sql="gold/finalize.sql"
    )

    create_silver >> build_silver >> create_gold >> build_gold
