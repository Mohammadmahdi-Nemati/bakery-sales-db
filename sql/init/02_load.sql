-- =====================================================================
-- Lädt die vom Generator erzeugten CSV-Dateien.
-- Pfad: im Docker-Container liegen die Daten unter /data
-- (lokal ohne Docker:  psql -v datadir="$PWD/data" -f sql/init/02_load.sql)
-- =====================================================================

\if :{?datadir}
\else
  \set datadir /data
\endif

SET search_path TO bakery;
\cd :datadir

\copy category FROM 'category.csv' WITH (FORMAT csv, HEADER true)
\copy product FROM 'product.csv' WITH (FORMAT csv, HEADER true)
\copy branch FROM 'branch.csv' WITH (FORMAT csv, HEADER true)
\copy customer_type FROM 'customer_type.csv' WITH (FORMAT csv, HEADER true)
\copy shift FROM 'shift.csv' WITH (FORMAT csv, HEADER true)
\copy public_holiday FROM 'public_holiday.csv' WITH (FORMAT csv, HEADER true)
\copy receipt FROM 'receipt.csv' WITH (FORMAT csv, HEADER true)
\copy receipt_item FROM 'receipt_item.csv' WITH (FORMAT csv, HEADER true)
\copy daily_production FROM 'daily_production.csv' WITH (FORMAT csv, HEADER true)
\copy waste FROM 'waste.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;
