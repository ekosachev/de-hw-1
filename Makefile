TRINO_CONTAINER := de-hw-1-trino
TRINO := docker exec -i $(TRINO_CONTAINER) trino

.PHONY: up down bronze

up:
	docker compose up -d

down:
	docker compose down

bronze:
	$(TRINO) < ./sql/bronze/init.sql
	$(TRINO) < ./sql/bronze/customer.sql
	$(TRINO) < ./sql/bronze/orders.sql
	$(TRINO) < ./sql/bronze/lineitem.sql

drop-bronze:
	$(TRINO) < ./sql/bronze/drop.sql
