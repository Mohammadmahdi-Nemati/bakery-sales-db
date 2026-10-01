-- =====================================================================
-- Indizes für die typischen Zugriffsmuster.
-- PostgreSQL legt für PRIMARY KEY und UNIQUE automatisch Indizes an,
-- für Fremdschlüssel aber NICHT. Die folgenden Indizes decken die
-- häufigsten Filter und Joins der Analysen ab.
-- Wirkung messbar mit sql/explain_demo.sql.
-- =====================================================================

SET search_path TO bakery;

-- Zeitraum-Abfragen pro Filiale ("Umsatz Filiale X im März")
CREATE INDEX idx_receipt_branch_sold_at ON receipt (branch_id, sold_at);

-- Zeitraum-Abfragen über alle Filialen
CREATE INDEX idx_receipt_sold_at ON receipt (sold_at);

-- Join Bonposition -> Produkt ("wie oft wurde Produkt X verkauft")
CREATE INDEX idx_receipt_item_product ON receipt_item (product_id);

ANALYZE;
