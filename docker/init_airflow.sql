-- ============================================================================
-- Airflow metadata database + role.
-- ----------------------------------------------------------------------------
-- Airflow shares the platform Postgres instance but keeps its metadata in a
-- dedicated `airflow` database/role (matching AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
-- in docker-compose.yml). Mounted as the FIRST entrypoint init script so the role
-- and database exist before Airflow runs `airflow db migrate`.
--
-- Runs only on a fresh data volume (docker-entrypoint-initdb.d). On an existing
-- volume, create these manually:
--   CREATE ROLE airflow LOGIN PASSWORD 'airflow';
--   CREATE DATABASE airflow OWNER airflow;
-- ============================================================================

CREATE ROLE airflow LOGIN PASSWORD 'airflow';
CREATE DATABASE airflow OWNER airflow;
