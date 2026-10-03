FROM apache/superset:6.0.0

USER root

RUN . /app/.venv/bin/activate && \
    uv pip install \
    psycopg2-binary \
    trino

COPY --chown=superset superset_config.py /app/pythonpath/superset_config.py

ENV SUPERSET_CONFIG_PATH=/app/pythonpath/superset_config.py

USER superset
