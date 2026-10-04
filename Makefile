TRINO_CONTAINER := de-hw-1-trino
TRINO := docker exec -i $(TRINO_CONTAINER) trino

.PHONY: up down bronze drop-bronze silver drop-silver gold drop-gold bench-prepare bench-run-snappy bench-run-gzip bench-run-zstd bench-clean

up:
	docker compose up -d

down:
	docker compose down

bronze:
	$(TRINO) < ./sql/bronze/init.sql
	$(TRINO) < ./sql/bronze/customer.sql
	$(TRINO) < ./sql/bronze/orders.sql
	$(TRINO) < ./sql/bronze/lineitem.sql

silver:
	$(TRINO) < ./sql/silver/init.sql
	$(TRINO) < ./sql/silver/aggregate.sql

gold:
	$(TRINO) < ./sql/gold/init.sql
	$(TRINO) < ./sql/gold/finalize.sql

drop-bronze:
	$(TRINO) < ./sql/bronze/drop.sql

drop-silver:
	$(TRINO) < ./sql/silver/drop.sql

drop-gold:
	$(TRINO) < ./sql/gold/drop.sql

bench-prepare:
	$(TRINO) < ./sql/bench/init.sql
	$(TRINO) < ./sql/bench/load_data.sql

bench-run-gzip:
	$(TRINO) < ./sql/bench/test_gzip.sql

bench-run-snappy:
	$(TRINO) < ./sql/bench/test_snappy.sql

bench-run-zstd:
	$(TRINO) < ./sql/bench/test_zstd.sql

bench-clean:
	$(TRINO) < ./sql/bench/drop.sql
