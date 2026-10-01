-- =====================================================================
-- Views: wiederverwendbare Grundlage für die Analysen.
-- =====================================================================

SET search_path TO bakery;

-- Jeder Bon mit Datum, Wochentag, Stunde und zugehöriger Schicht
CREATE VIEW v_receipt_shift AS
SELECT r.receipt_id,
       r.branch_id,
       r.customer_type_id,
       r.sold_at,
       r.sold_at::date                   AS sale_date,
       EXTRACT(ISODOW FROM r.sold_at)::int AS iso_weekday,   -- 1 = Montag
       EXTRACT(HOUR FROM r.sold_at)::int   AS sale_hour,
       s.name                            AS shift_name
FROM receipt r
JOIN shift s
  ON r.sold_at::time >= s.start_time
 AND r.sold_at::time <  s.end_time;

-- Verkaufte Menge und Umsatz je Filiale, Produkt und Tag
CREATE VIEW v_daily_sales AS
SELECT r.branch_id,
       ri.product_id,
       r.sold_at::date                  AS sale_date,
       SUM(ri.quantity)                 AS quantity_sold,
       SUM(ri.quantity * ri.unit_price) AS revenue
FROM receipt r
JOIN receipt_item ri ON ri.receipt_id = r.receipt_id
GROUP BY r.branch_id, ri.product_id, r.sold_at::date;

-- Tagesbilanz je Filiale und Produkt: produziert, verkauft, abgeschrieben
CREATE VIEW v_daily_balance AS
SELECT dp.branch_id,
       dp.product_id,
       dp.prod_date,
       dp.quantity_baked,
       COALESCE(ds.quantity_sold, 0)                    AS quantity_sold,
       COALESCE(w.quantity_wasted, 0)                   AS quantity_wasted
FROM daily_production dp
LEFT JOIN v_daily_sales ds
       ON ds.branch_id  = dp.branch_id
      AND ds.product_id = dp.product_id
      AND ds.sale_date  = dp.prod_date
LEFT JOIN (SELECT branch_id, product_id, waste_date, SUM(quantity_wasted) AS quantity_wasted
           FROM waste
           GROUP BY branch_id, product_id, waste_date) w
       ON w.branch_id  = dp.branch_id
      AND w.product_id = dp.product_id
      AND w.waste_date = dp.prod_date;
