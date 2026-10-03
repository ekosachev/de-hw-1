# Отчет по практической работе №1

| Поле | Значение |
| ---- | -------- |
| ФИО | Косачев Егор Сергеевич |
| Вариант / Запрос | 1 / Q3 |
| Масштаб | sf10 |

Масштаб `sf10` выбран так как на моем ноутбуке достаточно оперативной памяти и свободного места на диске, чтобы не беспокоситься о том, что таблицы не влезут. Большое количество данных для аггрегации позволит получить качественные резульататы на бенчмарках и при аналитике

## Поднятые сервисы
```mermaid
---
title: Схема взаимодействия контейнеров
---
flowchart LR;

    subgraph Silo
        Bronze --> Silver
        Silver --> Gold
    end

    PostgreSQL
    Lakekeeper
    Trino
    Superset

    Gold --> Superset
    Lakekeeper --> PostgreSQL
    Lakekeeper --> Trino
    Trino --> Silo
```

| Сервис | Роль в стеке | Почему именно он |
| ------ | ------------ | ---------------- |
| Silo | S3-совместимое объектное хранилище (физически содержит паркетники) | Используется вместо MinIO, так как последний больше недоступен (ушел с quay) |
| PostgreSQL | БД для метаданных каталога | Привычная SQL база данных |
| Lakekeeper | REST каталог метаданных таблиц | Качественное open-source решение |
| Trino | SQL-движок, прослойка между Lakekeeper и Silo | Быстрое и простое приложение с открытыми исходниками |
| Superset | Собирает BI-отчеты из данных Gold | Можно быстро собрать несколько графиков без кода |

### Как поднимал стек

Для удобства управления всеми контейнерами и быстрого запуска/остановки всей сети я создал `docker-compose` файл с оркестрацией сервисов.

Чтобы обеспечивать правильную последовательность запуска и исключить случаи, когда Lakekeeper пытается подключиться к Silo, который еще загружается, каждый контейнер снабжен healthcheck и зависимостями.

```mermaid
---
title: Зависимости между сервисами в docker compose
---
flowchart LR;

    subgraph Minio
        minio
        minio-init[minio-init\nСоздает бакет]

        minio -. Healthy .-> minio-init
    end

    Postgres

    subgraph Lakekeeper
        lakekeeper-migrate[lakekeeper-migrate\nПрименяет миграции к pgsql]
        lakekeeper
        lakekeeper-init[lakekeeper-init\nПринимает ToU и создает warehouse]

        lakekeeper-migrate -. Completed .-> lakekeeper
        lakekeeper -. Healthy .-> lakekeeper-init
    end

    Trino

    Postgres -. Healthy .-> lakekeeper-migrate
    Postgres -. Healthy .-> lakekeeper

    lakekeeper -. Healthy .-> Trino
    lakekeeper-init -. Completed .-> Trino
    minio -. Healthy .-> Trino
    minio-init -. Completed .-> Trino
```

Теперь запустить весть стек можно одной командой
```pwsh
dokcer compose up -d
```
И остановить
```pwsh
docker compose down
```
Если необходимо очистить данные в minio и pgsql:
```pwsh
docker compose down -v
```

### Разбор `docker-compose.yml`
#### minio

```yml
  de-hw-1-minio:
    image: pgsty/silo:latest
    container_name: de-hw-1-minio

    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin

    ports:
      - "9000:9000"
      - "9001:9001"

    volumes:
      - minio-data:/data

    command:
      - server
      - /data
      - --console-address
      - ":9001"

    healthcheck:
      test: ["CMD", "silo", "healthcheck", "ready"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

```
Создает сервер MinIO (Silo) с учеткой администратора minioadmin/minioadmin, открывает в сеть хоста порты `9000` и `9001`, чтобы смотреть админку и класть данные.

#### minio-init
```yml
  de-hw-1-minio-init:
    image: pgsty/mc:latest
    container_name: de-hw-1-minio-init
    depends_on:
      de-hw-1-minio:
        condition: service_healthy

    entrypoint: /bin/sh
    command:
      - -c
      - |
        mc alias set m http://de-hw-1-minio:9000 minioadmin minioadmin
        mc mb --ignore-existing m/warehouse
```
Ждет пока `minio` встанет, подключается и создает там бакет `warehouse`

#### pg (postgresql)

```yml
  de-hw-1-pg:
    image: postgres:17
    container_name: de-hw-1-pg

    environment:
      POSTGRES_PASSWORD: postgres

    ports:
      - "5432:5432"

    volumes:
      - pg-data:/var/lib/postgresql/data

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
```
Запускает сервер PostgreSQL и открывает порт `5432`

#### lakekeeper-migrate
```yml
  de-hw-1-lakekeeper-migrate:
    image: quay.io/lakekeeper/catalog:latest-main
    container_name: de-hw-1-lakekeeper-migrate

    environment:
      LAKEKEEPER__PG_ENCRYPTION_KEY: "This-is-NOT-Secure!"
      LAKEKEEPER__PG_DATABASE_URL_READ: "postgresql://postgres:postgres@de-hw-1-pg:5432/postgres"
      LAKEKEEPER__PG_DATABASE_URL_WRITE: "postgresql://postgres:postgres@de-hw-1-pg:5432/postgres"

    command: migrate

    depends_on:
      de-hw-1-pg:
        condition: service_healthy
```
Ждет пока `pg` будет готов, подключается и мигрирует туда таблицы для `lakekeeper`

#### lakekeeper
```yml
  de-hw-1-lakekeeper:
    image: quay.io/lakekeeper/catalog:latest-main
    container_name: de-hw-1-lakekeeper

    environment:
      LAKEKEEPER__PG_ENCRYPTION_KEY: "This-is-NOT-Secure!"
      LAKEKEEPER__PG_DATABASE_URL_READ: "postgresql://postgres:postgres@de-hw-1-pg:5432/postgres"
      LAKEKEEPER__PG_DATABASE_URL_WRITE: "postgresql://postgres:postgres@de-hw-1-pg:5432/postgres"

    ports:
      - "8181:8181"

    command: serve

    depends_on:
      de-hw-1-pg:
        condition: service_healthy
      de-hw-1-lakekeeper-migrate:
        condition: service_completed_successfully
```
Ждет `pg` и миграции, поднимает сервак Lakekeeper и открывает его порт

#### lakekeeper-init
```yml
  de-hw-1-lakekeeper-init:
    image: curlimages/curl:latest
    container_name: de-hw-1-lakekeeper-init

    depends_on:
      de-hw-1-lakekeeper:
        condition: service_healthy

    volumes:
      - ./create-warehouse.json:/create-warehouse.json:ro

    command:
      - /bin/sh
      - -c
      - |
        set -e

        echo "Accepting Terms of Use..."
        curl -f -X POST \
          http://de-hw-1-lakekeeper:8181/management/v1/bootstrap \
          -H "Content-Type: application/json" \
          -d '{"accept-terms-of-use":true}'

        echo "Creating warehouse..."
        curl -f -X POST \
          http://de-hw-1-lakekeeper:8181/management/v1/warehouse \
          -H "Content-Type: application/json" \
          -d @/create-warehouse.json
```
Ждет `lakekeeper`, подключается, принимает условия использования и создает в нем warehouse по конфигу из `./create-warehouse.json`

#### trino
```yml
  de-hw-1-trino:
    image: trinodb/trino:476
    container_name: de-hw-1-trino

    ports:
      - "8080:8080"

    volumes:
      - ./catalog:/etc/trino/catalog

    depends_on:
      de-hw-1-lakekeeper:
        condition: service_healthy
      de-hw-1-lakekeeper-init:
        condition: service_completed_successfully
      de-hw-1-minio:
        condition: service_healthy
      de-hw-1-minio-init:
        condition: service_completed_successfully

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/info"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
```
Ждет `lakekeeper`, `minio` и их `-init`-контейнеры, запускает сервер Trino и открывает его порт.