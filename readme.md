# Отчет по практической работе №1

| Поле             | Значение               |
| ---------------- | ---------------------- |
| ФИО              | Косачев Егор Сергеевич |
| Вариант / Запрос | 1 / Q3                 |
| Масштаб          | sf10                   |

Масштаб `sf10` выбран так как на моем ноутбуке достаточно оперативной памяти и свободного места на диске, чтобы не беспокоситься о том, что таблицы не влезут. Большое количество данных для аггрегации позволит получить качественные резульататы на бенчмарках и при аналитике

## Поднятые сервисы

| Сервис     | Роль в стеке                                                         | Почему именно он                                                             |
| ---------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Silo       | S3-совместимое объектное хранилище (физически содержит паркетники)   | Используется вместо MinIO, так как последний больше недоступен (ушел с quay) |
| PostgreSQL | БД для метаданных каталога                                           | Привычная SQL база данных                                                    |
| Lakekeeper | REST каталог метаданных таблиц                                       | Качественное open-source решение                                             |
| Trino      | SQL-движок, позводяет обращаться к Lakeleeper как к обычной SQL-базе | Быстрое и простое приложение с открытыми исходниками                         |
| Superset   | Собирает BI-отчеты из данных Bronze                                  | Можно быстро собрать несколько графиков без кода                             |

### Как поднимал стек

Для удобства управления всеми контейнерами и быстрого запуска/остановки всей сети я создал `docker-compose` файл с оркестрацией сервисов.

Чтобы обеспечивать правильную последовательность запуска и исключить случаи, когда Lakekeeper пытается подключиться к Silo, который еще загружается, каждый контейнер снабжен healthcheck и зависимостями. К тому же, зависимости заставляют контейнеры останавливаться в правильном порядке: сначала Superset, потом Trino, Lakekeeper и хранилища.

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

    subgraph Superset
        superset-db
        superset-init[superset-init\nПрименяет миграции к БД\nСоздает учетку админа\nЗагружает готовый дэшборд]
        superset

        superset-db -. Healthy .-> superset-init
        superset-db -. Healthy .-> superset
        superset-init -. Completed .-> superset
    end

    Postgres -. Healthy .-> lakekeeper-migrate
    Postgres -. Healthy .-> lakekeeper

    lakekeeper -. Healthy .-> Trino
    lakekeeper-init -. Completed .-> Trino
    minio -. Healthy .-> Trino
    minio-init -. Completed .-> Trino

    Trino -. Healthy .-> superset-init
```

Теперь запустить весть стек можно одной командой
```pwsh
dokcer compose up -d
```
И остановить
```pwsh
docker compose down
```
Если необходимо очистить данные:
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
      - ./scripts/lakekeeper-init.sh:/lakekeeper-init.sh:ro

```
Ждет `lakekeeper`, подключается и выполняет `scripts/lakekeeper-init.sh` который создает warehouse, если он еще не существует

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

#### superset-db
```yml
  de-hw-1-superset-db:
    image: postgres:17
    container_name: de-hw-1-superset-db
    environment:
      POSTGRES_DB: superset
      POSTGRES_USER: superset
      POSTGRES_PASSWORD: superset
    volumes:
      - superset-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U superset -d superset"]
      interval: 5s
      timeout: 5s
      retries: 5

```
Отдельная база данных для Superset: хранит источники данных, датасеты, графики и дэшборды

#### superset-init

```yml
  de-hw-1-superset-init:
    build:
      context: ./superset
    container_name: de-hw-1-superset-init

    depends_on:
      de-hw-1-superset-db:
        condition: service_healthy
      de-hw-1-trino:
        condition: service_healthy

    environment:
      SUPERSET_CONFIG_PATH: /app/pythonpath/superset_config.py
      SQLALCHEMY_DATABASE_URI: postgresql+psycopg2://superset:superset@de-hw-1-superset-db:5432/superset

    volumes:
      - ./superset/superset_config.py:/app/pythonpath/superset_config.py:ro
      - ./superset/exports:/exports:ro
      - ./scripts/superset-init.sh:/superset-init.sh:ro

    entrypoint: ["/bin/sh", "/superset-init.sh"]
```

Настраивает Superset используя `superset/superset_config.py` для параметров и `scripts/superset-init.sh` чтобы создать учетку и загрузить дэшборд из `superset/exports`

#### superset
```yml
  de-hw-1-superset:
    build:
      context: ./superset
    container_name: de-hw-1-superset

    depends_on:
      de-hw-1-superset-init:
        condition: service_completed_successfully
      de-hw-1-trino:
        condition: service_healthy

    environment:
      SUPERSET_CONFIG_PATH: /app/pythonpath/superset_config.py
      SQLALCHEMY_DATABASE_URI: postgresql+psycopg2://superset:superset@de-hw-1-superset-db:5432/superset
    
    volumes:
      - ./superset/superset_config.py:/app/pythonpath/superset_config.py:ro

    ports:
      - "8088:8088"

    command:
      - /bin/sh
      - -c
      - |
        /usr/bin/run-server.sh
```
Запускает сервер superset

## Какие данные нужны для отчета

По заданию нужно выделить 10 самых прибыльных заказов. Для этого я использую данные из tpch-таблиц `orders`, `customer` и `lineitem`

| Таблица TPC-H | Нужные колонки  | Что с ними делаем                                                  |
| ------------- | --------------- | ------------------------------------------------------------------ |
| `orders`      | `orderkey`      | JOIN с `lineitem.orderkey`, чтобы понять, какие товары в заказе    |
|               | `orderdate`     | Фильтр по дате заказа                                              |
|               | `shippriority`  | Приоритет доставки для итогового отчета                            |
| `lineitem`    | `extendedprice` | Цена без скидки для расчета прибыли                                |
|               | `discount`      | Размер скидки                                                      |
|               | `shipdate`      | Фильтр по дате поставки                                            |
| `customer`    | `custkey`       | JOIN с `order.custkey`, чтобы отфильтровать по сегменту `BUILDING` |

## Решения по медальонной архитектуре

| Медальон | Таблица                  | Колонки                                                                          | Количество строк | Место на диcке, МБ | Формат  | Сжатие | Партиционирование |
| -------- | ------------------------ | -------------------------------------------------------------------------------- | ---------------- | ------------------ | ------- | ------ | ----------------- |
| Bronze   | `customer`               | Как в TPC-H                                                                      | 1500000          | 77.9               | PARQUET | ZSTD   | Нет               |
|          | `lineitem`               | Как в TPC-H                                                                      | 59986052         | 1457.1             | PARQUET | ZSTD   | YEAR(orderdate)   |
|          | `orders`                 | Как в TPC-H                                                                      | 15000000         | 369.4              | PARQUET | ZSTD   | Нет               |
| Silver   | `order_lines`            | `orderkey`, `orderdate`, `shippriority`, `extendedprice`, `discount`, `shipdate` | 307299           | 2.6                | PARQUET | ZSTD   | Нет               |
| Gold     | `most_profitable_orders` | `orderkey`, `orderdate`, `shippriority`, `shipdate`, `revenue`                   | 10               | 0.001              | PARQUET | ZSTD   | Нет               |

В Bronze-слой попадают "сырые" данны из источников (в данном случае – TPC-H). Задача этого слоя – сохранить данные по-максимуму, поэтому колонки не отбрасываются. Партиционирование применено только к `lineitem` по году доставки, так как именно по этому полю данные будут фильтроваться в дальнейшем. Можно было бы партиционировать по `customer.mktsegment`, но там всего несколько разных значений, поэтому объемы для чтения не особенно снизятся.

В Silver-слой попадают только те данные, которые нам "интересны" – информация по доставке и стоимости товаров, которые нужно доставить после 1995-03-15 с нужным `customer.mktsegment`. Партиционирование на этом слое также не применятся из-за малого количества строк.

Запрос для Silver-слоя:
```sql
SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.silver.order_lines
WITH (
    format = 'PARQUET'
)
AS
SELECT
    o.orderkey,
    o.orderdate,
    o.shippriority,
    l.extendedprice,
    l.discount,
    l.shipdate
FROM lakekeeper.bronze.customer AS c
JOIN lakekeeper.bronze.orders AS o
    ON c.custkey = o.custkey
JOIN lakekeeper.bronze.lineitem AS l
    ON o.orderkey = l.orderkey
WHERE c.mktsegment = 'BUILDING'
    AND l.shipdate > DATE '1995-03-15'
    AND o.orderdate <= DATE '1995-03-15';
```

В Gold-слой попадает то что мы изначально хотели – 10 самых прибыльных заказов по убыванию `revenue`.
Запрос для Gold-слоя:
```sql
SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.gold.most_profitable_orders
WITH (
    format = 'PARQUET'
)
AS
SELECT
    ol.orderkey,
    ol.orderdate,
    ol.shippriority,
    ol.shipdate,
    SUM(ol.extendedprice * (1 - ol.discount)) as revenue
FROM lakekeeper.silver.order_lines AS ol
GROUP BY ol.orderkey, ol.orderdate, ol.shipdate, ol.shippriority
ORDER BY revenue DESC
LIMIT 10;
```

На всех слоях применяется кодек сжатия ZStandard, так как он сжимает данные лучше, чем Snappy и менее требователен к CPU чем GZIP.

## Тесты производительности

Для тестирования производительности кластера использовался запрос Silver-слоя, так как он достаточно сильно нагружает хост, испольуя JOIN больших таблиц и фильтры.


