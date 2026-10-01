-- =====================================================================
-- Analysen: Fragen, die sich eine Bäckerei-Leitung wirklich stellt.
-- Ausführen:  psql -f sql/analysen.sql
-- Jede Abfrage steht für sich und kann einzeln kopiert werden.
-- =====================================================================

SET search_path TO bakery;

-- ---------------------------------------------------------------------
-- A) Umsatz
-- ---------------------------------------------------------------------

-- A1: Umsatz je Filiale und Monat
SELECT b.name                               AS filiale,
       TO_CHAR(r.sold_at, 'YYYY-MM')        AS monat,
       COUNT(DISTINCT r.receipt_id)         AS bons,
       SUM(ri.quantity * ri.unit_price)     AS umsatz_eur
FROM receipt r
JOIN receipt_item ri ON ri.receipt_id = r.receipt_id
JOIN branch b        ON b.branch_id   = r.branch_id
GROUP BY b.name, TO_CHAR(r.sold_at, 'YYYY-MM')
ORDER BY b.name, monat;

-- A2: Top 10 Produkte nach Umsatz, mit Anteil am Gesamtumsatz
SELECT p.name                                         AS produkt,
       SUM(ri.quantity)                               AS stueck,
       SUM(ri.quantity * ri.unit_price)               AS umsatz_eur,
       ROUND(100.0 * SUM(ri.quantity * ri.unit_price)
             / SUM(SUM(ri.quantity * ri.unit_price)) OVER (), 1) AS anteil_prozent
FROM receipt_item ri
JOIN product p ON p.product_id = ri.product_id
GROUP BY p.name
ORDER BY umsatz_eur DESC
LIMIT 10;

-- A3: Durchschnittlicher Bonwert je Kundentyp
SELECT ct.name                     AS kundentyp,
       COUNT(*)                    AS bons,
       ROUND(AVG(bon.summe), 2)    AS avg_bonwert_eur
FROM (SELECT r.receipt_id, r.customer_type_id, SUM(ri.quantity * ri.unit_price) AS summe
      FROM receipt r
      JOIN receipt_item ri ON ri.receipt_id = r.receipt_id
      GROUP BY r.receipt_id, r.customer_type_id) bon
JOIN customer_type ct ON ct.customer_type_id = bon.customer_type_id
GROUP BY ct.name
ORDER BY avg_bonwert_eur DESC;

-- A4: Effekt der Preiserhöhung bei Brötchen (01.03.2026):
--     Durchschnittspreis und verkaufte Stück pro Tag vorher/nachher
SELECT CASE WHEN r.sold_at < '2026-03-01' THEN '1: vorher' ELSE '2: nachher' END AS zeitraum,
       ROUND(AVG(ri.unit_price), 2)                                        AS avg_preis_eur,
       ROUND(SUM(ri.quantity)::numeric / COUNT(DISTINCT r.sold_at::date), 0) AS stueck_pro_tag
FROM receipt r
JOIN receipt_item ri ON ri.receipt_id = r.receipt_id
JOIN product p       ON p.product_id  = ri.product_id
WHERE p.category_id = (SELECT category_id FROM category WHERE name = 'Brötchen')
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- B) Kundenströme und Personalplanung
-- ---------------------------------------------------------------------

-- B1: Durchschnittliche Kundenzahl pro Stunde und Filiale (an Werktagen)
--     -> wann braucht man mehr Personal an der Theke?
SELECT b.name                                       AS filiale,
       v.sale_hour                                  AS stunde,
       ROUND(COUNT(*)::numeric / COUNT(DISTINCT v.sale_date), 1) AS kunden_pro_tag
FROM v_receipt_shift v
JOIN branch b ON b.branch_id = v.branch_id
WHERE v.iso_weekday BETWEEN 1 AND 5
GROUP BY b.name, v.sale_hour
ORDER BY b.name, v.sale_hour;

-- B2: Umsatz nach Wochentag und Schicht
SELECT v.iso_weekday                        AS wochentag,   -- 1 = Montag
       v.shift_name                         AS schicht,
       SUM(ri.quantity * ri.unit_price)     AS umsatz_eur
FROM v_receipt_shift v
JOIN receipt_item ri ON ri.receipt_id = v.receipt_id
GROUP BY v.iso_weekday, v.shift_name
ORDER BY v.iso_weekday, v.shift_name;

-- B3: Welche Produkte werden oft zusammen gekauft? (Warenkorbanalyse, Self-Join)
SELECT p1.name AS produkt_a,
       p2.name AS produkt_b,
       COUNT(*) AS gemeinsame_bons
FROM receipt_item a
JOIN receipt_item b ON b.receipt_id = a.receipt_id
                   AND b.product_id > a.product_id      -- jedes Paar nur einmal
JOIN product p1 ON p1.product_id = a.product_id
JOIN product p2 ON p2.product_id = b.product_id
GROUP BY p1.name, p2.name
ORDER BY gemeinsame_bons DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- C) Abfall und Überproduktion (Kernfrage des Projekts)
-- ---------------------------------------------------------------------

-- C1: Abfallquote je Produkt über alle Filialen
SELECT p.name                                                   AS produkt,
       SUM(db.quantity_baked)                                   AS produziert,
       SUM(db.quantity_wasted)                                  AS abgeschrieben,
       ROUND(100.0 * SUM(db.quantity_wasted) / SUM(db.quantity_baked), 1) AS abfallquote_prozent
FROM v_daily_balance db
JOIN product p ON p.product_id = db.product_id
GROUP BY p.name
HAVING SUM(db.quantity_baked) > 0
ORDER BY abfallquote_prozent DESC;

-- C2: Geldverlust durch Abfall (zu Herstellungskosten) je Kategorie und Filiale
SELECT b.name                                  AS filiale,
       c.name                                  AS kategorie,
       SUM(w.quantity_wasted)                  AS stueck,
       SUM(w.quantity_wasted * p.unit_cost)    AS verlust_eur
FROM waste w
JOIN product  p ON p.product_id  = w.product_id
JOIN category c ON c.category_id = p.category_id
JOIN branch   b ON b.branch_id   = w.branch_id
GROUP BY b.name, c.name
ORDER BY verlust_eur DESC;

-- C3: Ausverkauft vs. Überproduziert: an wie vielen Tagen war ein Produkt
--     komplett ausverkauft, und an wie vielen blieb mehr als 25 % übrig?
SELECT p.name AS produkt,
       COUNT(*) FILTER (WHERE db.quantity_sold = db.quantity_baked)            AS tage_ausverkauft,
       COUNT(*) FILTER (WHERE db.quantity_wasted > 0.25 * db.quantity_baked)   AS tage_ueber_25_prozent_rest,
       COUNT(*)                                                                AS tage_gesamt
FROM v_daily_balance db
JOIN product p ON p.product_id = db.product_id
WHERE db.quantity_baked > 0
GROUP BY p.name
ORDER BY tage_ueber_25_prozent_rest DESC;

-- C4: Feiertage vs. normale Tage: Die Planung orientiert sich am Wochentag,
--     Kunden verhalten sich an Feiertagen aber wie an einem Sonntag.
SELECT CASE WHEN ph.holiday_date IS NOT NULL THEN 'Feiertag'
            WHEN EXTRACT(ISODOW FROM db.prod_date) = 7 THEN 'Sonntag'
            ELSE 'Mo-Sa' END                                         AS tagesart,
       COUNT(DISTINCT db.prod_date)                                  AS tage,
       ROUND(100.0 * SUM(db.quantity_wasted) / SUM(db.quantity_baked), 1) AS abfallquote_prozent
FROM v_daily_balance db
LEFT JOIN public_holiday ph ON ph.holiday_date = db.prod_date
GROUP BY 1
ORDER BY abfallquote_prozent DESC;

-- ---------------------------------------------------------------------
-- D) Trends und Ranking (Window Functions)
-- ---------------------------------------------------------------------

-- D1: Weizenbrötchen in Bilk: Tagesabsatz und gleitender 7-Tage-Durchschnitt
SELECT ds.sale_date,
       ds.quantity_sold,
       ROUND(AVG(ds.quantity_sold) OVER (ORDER BY ds.sale_date
                                         ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS avg_7_tage
FROM v_daily_sales ds
WHERE ds.branch_id  = (SELECT branch_id  FROM branch  WHERE name = 'Filiale Bilk')
  AND ds.product_id = (SELECT product_id FROM product WHERE name = 'Weizenbrötchen')
ORDER BY ds.sale_date;

-- D2: Bestseller je Kategorie und Filiale (RANK pro Gruppe)
SELECT filiale, kategorie, produkt, stueck
FROM (SELECT b.name AS filiale,
             c.name AS kategorie,
             p.name AS produkt,
             SUM(ri.quantity) AS stueck,
             RANK() OVER (PARTITION BY b.name, c.name ORDER BY SUM(ri.quantity) DESC) AS rang
      FROM receipt r
      JOIN receipt_item ri ON ri.receipt_id = r.receipt_id
      JOIN product p       ON p.product_id  = ri.product_id
      JOIN category c      ON c.category_id = p.category_id
      JOIN branch b        ON b.branch_id   = r.branch_id
      GROUP BY b.name, c.name, p.name) t
WHERE rang = 1
ORDER BY filiale, kategorie;

-- ---------------------------------------------------------------------
-- E) Von der Analyse zur Entscheidung
-- ---------------------------------------------------------------------

-- E1: Produktionsempfehlung für Montag, 29.06.2026, Filiale Bilk:
--     Ø-Absatz der letzten 4 Montage, aufgerundet. Zum Vergleich: tatsächlich produziert.
--     (Achtung: Absatz ist durch Ausverkäufe nach oben begrenzt; eine echte Prognose
--      müsste das berücksichtigen. Das ist der Ausgangspunkt für Version 2 des Projekts.)
WITH letzte_montage AS (
    SELECT db.product_id, db.quantity_sold
    FROM v_daily_balance db
    WHERE db.branch_id = (SELECT branch_id FROM branch WHERE name = 'Filiale Bilk')
      AND db.prod_date IN (DATE '2026-06-01', DATE '2026-06-08', DATE '2026-06-15', DATE '2026-06-22')
)
SELECT p.name                                    AS produkt,
       CEIL(AVG(lm.quantity_sold))               AS empfehlung,
       dp.quantity_baked                         AS tatsaechlich_produziert,
       dp.quantity_baked - CEIL(AVG(lm.quantity_sold)) AS differenz
FROM letzte_montage lm
JOIN product p ON p.product_id = lm.product_id
JOIN daily_production dp
  ON dp.product_id = lm.product_id
 AND dp.branch_id  = (SELECT branch_id FROM branch WHERE name = 'Filiale Bilk')
 AND dp.prod_date  = DATE '2026-06-29'
GROUP BY p.name, dp.quantity_baked
ORDER BY differenz DESC;

-- ---------------------------------------------------------------------
-- F) Datenqualität
-- ---------------------------------------------------------------------

-- F1: Plausibilität: produziert = verkauft + abgeschrieben?
--     Erwartet: 0 Zeilen. Alles andere wäre Schwund oder ein Fehler im Datenfluss.
SELECT *
FROM v_daily_balance
WHERE quantity_baked <> quantity_sold + quantity_wasted;
