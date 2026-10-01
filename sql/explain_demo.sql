-- =====================================================================
-- Demo: Wirkung eines Index messen
-- Frage: Wie viele Kunden kamen in der ersten Märzwoche pro Stunde in die Filiale Medienhafen?
-- Ausführen:  psql -f sql/explain_demo.sql
-- =====================================================================

SET search_path TO bakery;
\timing on

-- 1) OHNE Index: PostgreSQL muss alle ~174.000 Bons lesen (Seq Scan)
DROP INDEX IF EXISTS idx_receipt_branch_sold_at;
DROP INDEX IF EXISTS idx_receipt_sold_at;

EXPLAIN ANALYZE
SELECT EXTRACT(HOUR FROM sold_at) AS stunde, COUNT(*) AS bons
FROM receipt
WHERE branch_id = 2
  AND sold_at >= '2026-03-02'
  AND sold_at <  '2026-03-09'
GROUP BY 1
ORDER BY 1;

-- 2) MIT Index auf (branch_id, sold_at): nur die passenden Bons werden gelesen
CREATE INDEX idx_receipt_branch_sold_at ON receipt (branch_id, sold_at);
CREATE INDEX idx_receipt_sold_at ON receipt (sold_at);
ANALYZE receipt;

EXPLAIN ANALYZE
SELECT EXTRACT(HOUR FROM sold_at) AS stunde, COUNT(*) AS bons
FROM receipt
WHERE branch_id = 2
  AND sold_at >= '2026-03-02'
  AND sold_at <  '2026-03-09'
GROUP BY 1
ORDER BY 1;
