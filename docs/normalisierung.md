# Normalisierung und Designentscheidungen

Alle Relationen des Schemas sind in **Boyce-Codd-Normalform (BCNF)**.
Kriterium: Für jede nicht-triviale funktionale Abhängigkeit (FD) X → Y ist X ein Superschlüssel.

Unten stehen für jede Relation die fachlich gültigen FDs. Die linke Seite ist jeweils ein
Schlüsselkandidat, daher ist BCNF erfüllt (und damit auch 1NF, 2NF und 3NF).

## Funktionale Abhängigkeiten je Relation

| Relation | Schlüsselkandidat(en) | Nicht-triviale FDs |
|---|---|---|
| `category` | `category_id`, `name` | `category_id → name`, `name → category_id` |
| `product` | `product_id`, `name` | `product_id → name, category_id, price, unit_cost, shelf_life_hours`; `name → product_id` |
| `branch` | `branch_id`, `name` | `branch_id → name, district, location`; `name → branch_id` |
| `customer_type` | `customer_type_id`, `name` | `customer_type_id → name`; `name → customer_type_id` |
| `shift` | `shift_id`, `name` | `shift_id → name, start_time, end_time`; `name → shift_id` |
| `public_holiday` | `holiday_date` | `holiday_date → name` |
| `receipt` | `receipt_id` | `receipt_id → branch_id, customer_type_id, sold_at, payment_method` |
| `receipt_item` | `(receipt_id, line_no)` | `receipt_id, line_no → product_id, quantity, unit_price` |
| `daily_production` | `(branch_id, product_id, prod_date)` | `branch_id, product_id, prod_date → quantity_baked` |
| `waste` | `(branch_id, product_id, waste_date, reason)` | `branch_id, product_id, waste_date, reason → quantity_wasted` |

## Bewusst vermiedene Anomalien

**Kategorie nicht im Produkt gespeichert.** Stünde der Kategoriename direkt in `product`, gäbe es die
transitive Abhängigkeit `product_id → category_id → category_name`. Das wäre eine Verletzung der 3NF:
Eine Umbenennung („Snacks“ → „Herzhaftes“) müsste in vielen Zeilen geändert werden (Update-Anomalie).

**Filiale nur im Bon, nicht in der Bonposition.** `receipt_item` enthält keine `branch_id`, denn
`receipt_id → branch_id` würde sonst nur von einem Teil des Schlüssels `(receipt_id, line_no)` abhängen.
Das wäre eine partielle Abhängigkeit und damit eine Verletzung der 2NF.

## Designentscheidungen, die auf den ersten Blick redundant aussehen

**`receipt_item.unit_price` neben `product.price`.** Das ist keine Redundanz: `product.price` ist der
*aktuelle* Preis, `unit_price` der Preis *zum Verkaufszeitpunkt*. Nach der Preiserhöhung am 01.03.2026
unterscheiden sich beide. Ohne `unit_price` würden alte Umsätze rückwirkend falsch berechnet.

**Abfall wird gespeichert, nicht berechnet.** Theoretisch gilt `Abfall = produziert − verkauft`. In der Praxis
wird Abfall aber separat gezählt (mit Grund: abgelaufen oder beschädigt). Gerade die Abweichung zwischen
beiden Werten ist interessant: Sie zeigt Schwund oder Fehler. Die Abfrage F1 in `sql/analysen.sql`
prüft genau diese Gleichung.

**Schicht ohne Fremdschlüssel im Bon.** Die Schicht ergibt sich eindeutig aus der Uhrzeit (`sold_at`).
Ein zusätzliches Attribut `shift_id` in `receipt` würde die FD `sold_at → shift_id` erzeugen, also eine
transitive Abhängigkeit. Stattdessen ordnet der View `v_receipt_shift` jeden Bon per Zeitbereich zu.

## Grenzen der Integritätssicherung

**Ein Bon ohne Positionen ist technisch möglich.** Im ER-Modell hat ein Bon mindestens eine Position,
Kardinalität (1,*). Ein Fremdschlüssel sichert aber nur die Gegenrichtung: Jede Position gehört zu einem
existierenden Bon. Die *totale Teilnahme* von `receipt` lässt sich mit FKs allein nicht erzwingen.
Lösungen wären ein verzögert geprüfter Trigger (`CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED`)
oder das Anlegen von Bon und Positionen nur über eine Prozedur in einer Transaktion.

**Abfall kann nur zu einer existierenden Produktion gebucht werden.** Das wird über den
zusammengesetzten Fremdschlüssel `waste (branch_id, product_id, waste_date) → daily_production` gesichert.
Dass die Abfallmenge die Produktionsmenge nicht übersteigt, ist dagegen eine Bedingung über zwei
Tabellen und mit einem `CHECK` nicht ausdrückbar.
