# Отчет по практической работе №1

| Поле             | Значение               |
| ---------------- | ---------------------- |
| ФИО              | Косачев Егор Сергеевич |
| Вариант / Запрос | 1 / Q3                 |
| Масштаб          | sf10                   |

Масштаб `sf10` выбран так как на моем ноутбуке достаточно оперативной памяти и свободного места на диске, чтобы не беспокоситься о том, что таблицы не влезут. Большое количество данных для аггрегации позволит получить качественные резульататы на бенчмарках и при аналитике

## Поднятые сервисы

```mermaid
---
title: Поднятые сервисы и архитектура
---
flowchart LR;
    subgraph BI layer
        Superset
        PgSuperset[PostgreSQL\nSuperset metadata]
        Superset -- metadata --> PgSuperset
    end

    subgraph Query layer
        Trino
    end

    subgraph Catalog layer
        Lakekeeper[Lakekeeper\nIceberg REST Catalog]
        PgLakekeeper[PostgreSQL\nLakekeeper metadata]
        Lakekeeper -- metadata --> PgLakekeeper
    end

    subgraph Storage layer
        Silo[Silo\nS3-compatible storage]
    end

    Superset -- SQL --> Trino
    Trino -- Iceberg REST --> Lakekeeper
    Trino -- S3 API \n Parquet files --> Silo
```

| Сервис     | Роль в стеке                                                                           | Почему именно он                                                             |
| ---------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Silo       | S3-совместимое объектное хранилище (физически содержит паркетники)                     | Используется вместо MinIO, так как последний больше недоступен (ушел с quay) |
| PostgreSQL | БД для метаданных каталога                                                             | Привычная SQL база данных                                                    |
| Lakekeeper | REST каталог метаданных таблиц                                                         | Качественное open-source решение                                             |
| Trino      | Выполняет SQL-запросы на Iceberg-таблицах, используя Lakekeeper как каталог метаданных | Быстрое и простое приложение с открытыми исходниками                         |
| Superset   | Собирает BI-отчеты из данных Bronze                                                    | Можно быстро собрать несколько графиков без кода                             |

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
| -------- | ------------------------ | -------------------------------------------------------------------------------- | ---------------- | ------------------ | ------- | ------ | ----------------------- |
| Bronze   | `customer`               | Как в TPC-H                                                                      | 1500000          | 77.9               | PARQUET | ZSTD   | Нет                     |
|          | `lineitem`               | Как в TPC-H                                                                      | 59986052         | 1457.1             | PARQUET | ZSTD   | ARRAY[YEAR(shipdate)]   |
|          | `orders`                 | Как в TPC-H                                                                      | 15000000         | 369.4              | PARQUET | ZSTD   | Нет                     |
| Silver   | `order_lines`            | `orderkey`, `orderdate`, `shippriority`, `extendedprice`, `discount`, `shipdate` | 307299           | 2.6                | PARQUET | ZSTD   | Нет                     |
| Gold     | `most_profitable_orders` | `orderkey`, `orderdate`, `shippriority`, `shipdate`, `revenue`                   | 10               | 0.001              | PARQUET | ZSTD   | Нет                     |

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
    AND o.orderdate < DATE '1995-03-15';
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

| Сжатие на Bronze | Время запроса, с | Размер Bronze (`customer`, `orders`, `lineitem`), МБ |
| ---------------- | ---------------- | ---------------------------------------------------- |
| GZIP             | 17.72            | 76.7 + 356.2 + 1426.2 = 1859.1                       |
| Snappy           | 3.97             | 118.2 + 549.4 + 2025.9 = 2693.5                      |
| ZSTD             | 2.94             | 77.9 + 369.4 + 1455.9 = 1903.2                       |

По итогам тестирования, самое лучшее время показал кодек `ZSTD` (2.94 с), при этом он находится на втором месте по объему таблиц (1903.2 Мб). Кодек `GZIP` наиболее эффективно сжал данные (1859.1 Мб), но сильно отстает от других по скорости, что делает `ZSTD` наиболее предпочтительным вариантом в данной ситуации. `Snappy` оказался самым плохим кодеком в плане качества сжатия, так еще и не самым быстрым.

## Осмысление и работа с инструментами

### Зачем нужны большие данные и lakehouse?

Разделяют два подхода к хранению данных:
 - OLTP (OnLine *Transactional* Proceessing) – подход, используемый в "обычных" базах данных. Позволяет в реальном времени выполнять большое количество транзакций, направленных на чтение и изменение отдельных бизнес-сущностей;
 - OLAP (OnLine *Analytical* Processing) позволяет проводить многомерный анализ огромного объема данных с большой скоростью. Подходит для BI, ML и аналитики, но "не любит" большое количество мелких запросов. Именно этот подход используют инструменты для работы с большими данными.

OLTP-инструменты, такие как PostgreSQL или MySQL хорошо подходят для транзакционной нагрузки, но специализированные OLAP-решения позволяют отделить аналитическую нагрузку от OLTP, хранить большие объемы данных в дешевом объектном хранилице и масштабировать вычисления независимо от хранения.

### Пример Schema evolution на Silver-слое
В качестве примера я решил добавить колонку `order_year` в `silver.order_lines`. Делается это с помощью двух запросов:
```sql
ALTER TABLE lakekeeper.silver.order_lines
ADD COLUMN order_year INTEGER;

UPDATE lakekeeper.silver.order_lines
SET order_year = year(orderdate);
```

Первый запрос на самом деле ничего не делает с данными – trino не изменяет 300 тысяч строк просто чтобы добавить туда `NULL`. Информация о столбце просто добавляется в метаданные таблицы, отсутствие изменений в данных на этом этапе подтверждается таблицей `snapshots`.

Второй запрос приводит к изменению данных в объектом хранилище и создает новый снапшот таблицы.

Вот какой лог я получил, выполнив эти 2 запроса:

```
PS C:\Users\Egor\de-hw-1> make mutate
Pre-mutatuion state:
docker exec -i de-hw-1-trino trino < ./sql/silver/head.sql
Oct 04, 2026 9:03:29 PM org.jline.utils.Log logr
WARNING: Unable to create a system terminal, creating a dumb terminal (enable debug logging for more information)
"58430656", "1994-12-26", "0", "50044.43", "0.04", "1995-03-30"
"58430656", "1994-12-26", "0", "40052.34", "0.08", "1995-04-17"
"58431271", "1995-03-06", "0", "58431.23", "0.03", "1995-05-14"
"58431271", "1995-03-06", "0", "43966.99", "0.07", "1995-06-11"
"58431271", "1995-03-06", "0", "68662.75", "0.04", "1995-04-27"
Applying mutation ...
docker exec -i de-hw-1-trino trino < ./sql/silver/mutate.sql
Oct 04, 2026 9:03:30 PM org.jline.utils.Log logr
WARNING: Unable to create a system terminal, creating a dumb terminal (enable debug logging for more information)
ADD COLUMN
UPDATE: 307299 rows
Mutation applied.
Post-mutation state:
docker exec -i de-hw-1-trino trino < ./sql/silver/head.sql
Oct 04, 2026 9:03:35 PM org.jline.utils.Log logr
WARNING: Unable to create a system terminal, creating a dumb terminal (enable debug logging for more information)
"58430656", "1994-12-26", "0", "50044.43", "0.04", "1995-03-30", "1994"
"58430656", "1994-12-26", "0", "40052.34", "0.08", "1995-04-17", "1994"
"58431271", "1995-03-06", "0", "58431.23", "0.03", "1995-05-14", "1995"
"58431271", "1995-03-06", "0", "43966.99", "0.07", "1995-06-11", "1995"
"58431271", "1995-03-06", "0", "68662.75", "0.04", "1995-04-27", "1995"
PS C:Users\Egor\de-hw-1>
```

### Разрушительные изменения и восстановление данных из снапшота

Существующие снапшоты таблицы можно посмотреть с помощью запроса:
```sql
SELECT
    *
FROM lakekeeper.silver."order_lines$snapshots"
ORDER BY committed_at;
```

На текущий момент у таблицы 2 снапшота:
![Initial snapshots](./imgs/initial-snapshots.png)

Первый – от 03.10.26 – создание таблицы и заполнение данными (append)
Второй – от 04.10.26 – заполнение столбца `order_year` (overwrite)

При этом, если бы я добавил колонку, но не заполнил ее данными, второй снапшот не создался бы, так как физически данные в таблице не изменились.

Для тестирования механизма снапшотов, удалим все данные из таблицы `order_lines`, затем найдем нужный снапшот и восставновим в нужной версии.

Удаление делаем через обычный запрос: `DELETE FROM lakekeeper.silver.order_lines`, а потом смотрим снапшоты:

![Shapshots afted destructive change](./imgs/snapshots-after-destruct.png)

Появился новый снапшот от 05.10.26 с типом "delete". Теперь попробуем восстановить утерянные данные из снапшота от 04.10. Если бы это была реальная система, мы бы хотели сначала подтверить, что это точно тот снапшот, который нам нужен. Для этого можно использовать следующий запрос:
```SQL
SELECT 
    *
FROM lakekeeper.silver.order_lines
LIMIT 5
FOR VERSION AS OF 5456807769916039556;
```
Или, если достаточно количества строк:
```SQL
SELECT
    count(*)
FROM lakekeeper.silver.order_lines
FOR VERSION AS OF 5456807769916039556;
```

Так как я просто удалил данные, достаточно увидеть нужное количество строк:
![Count rows in snapshot](./imgs/count-from-snapshot.png)
Теперь можно восстановить состояние таблицы до нужного snapshot:
```SQL
CALL lakekeeper.system.rollback_to_snapshot(
    'silver', 'order_lines',
    5456807769916039556
);
```

![Rollback execution](./imgs/rollback-proc.png)

После выполнения этой процедуры данные снова содержатся в таблице:
![Data returned](./imgs/returned-data.png)

## Подключение стороннего инструмента к Lakehouse
В качестве стороннего инструмента я выбрал Apache Superset, так как он быстро настраиваеся и позволяет набросать несколько графиков без кода. Настройка и запуск платформы описаны выше.

Чтобы Superset мог получить данные из trino, я добавил его как Database в настройках:

![Database connection](./imgs/database-connector.png)

Затем создал три датасета, соответствующие трем таблицам в Bronze-слое:
![Datasets](./imgs/datasets.png)

И после этого уже можно создавать графики на основе данных:
![Created charts](./imgs/created-charts.png)

Удобный редактор Superset позволяет быстро перетащить нужные поля датасета в параметры графика, а где нужно – написать реальный SQL (например, чтобы вычислить реальную выручку с учетом скидки).

![Chart in editor](./imgs/chart-in-editor.png)

Вот как выглядит итоговый дэшборд:
![Dashboard](./imgs/dashboard.png)

## Выводы

Работа с такой системой как Lakehouse состоит из множества разных частей, каждая из которых по-своему сложна. Особенно много времени я потратил на то, чтобы из отдельных `docker run`-команд гайда собрать полноценный `docker-compose.yml`, но эти старания полностью окупились: система поднимается всего одной командой, а настройки сохранены в файлах. Также пришлось подумать над организацией медальонной архитектуры: с Bronze и Gold было все более-менее ясно, но не совсем понятно, что стоило класть в Silver, а что – оставить в "бронзе". После работы с медальенами я провел тесты алгоритмов сжатия и сравнил их по качеству и скорости работы, наиболее выгодным кодеком оказался `ZSTD`, так как он быстро и эффективно сжимает данные. В конце я поработал с schema evolution и снапшотами, собрал небольшой дэшборд на Superset.
