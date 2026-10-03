SECRET_KEY = "todo-change-for-prod-please"
SQLALCHEMY_DATABASE_URI = (
    "postgresql+psycopg2://superset:superset@de-hw-1-superset-db:5432/superset"
)
SQLALCHEMY_TRACK_MODIFICATIONS = False
SUPERSET_LOAD_EXAMPLES = False
FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
}
