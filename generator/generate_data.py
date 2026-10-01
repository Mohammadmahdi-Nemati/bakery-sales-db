"""
Testdaten-Generator für bakery-sales-db.

Simuliert den Betrieb von drei Bäckerei-Filialen über ein halbes Jahr:
  * Kunden kommen über den Tag verteilt (Morgen-, Mittags- und Nachmittagsspitze).
  * Was gekauft wird, hängt von Uhrzeit, Wochentag und Standort ab
    (Brötchen morgens, Snacks mittags, Kuchen nachmittags; Bürostandort am Wochenende fast leer).
  * Die Produktionsmenge wird wie in einer echten Bäckerei geplant:
    Durchschnitt der Nachfrage der letzten 4 gleichen Wochentage plus Sicherheitspuffer.
  * Ist ein Produkt ausverkauft, geht der Verkauf verloren; was abends übrig ist, wird abgeschrieben.

Dadurch entstehen Abfall und Ausverkäufe auf natürliche Weise, statt zufällig erfunden zu werden.

Nur Python-Standardbibliothek. Ergebnis: CSV-Dateien in ../data/
Aufruf:  python3 generator/generate_data.py
"""

import csv
import random
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from pathlib import Path

SEED = 42
START = date(2026, 1, 1)
END = date(2026, 6, 30)
WARMUP_DAYS = 28                      # Vorlauf, damit die Produktionsplanung Historie hat
PRICE_CHANGE = date(2026, 3, 1)       # Preiserhöhung bei Brötchen
PRICE_CHANGE_FACTOR = 1.10
SAFETY_BUFFER = 1.12                  # Produktion = Ø-Nachfrage * Puffer
PRICE_ELASTICITY = 0.95               # Brötchen-Nachfrage sinkt nach der Preiserhöhung um 5 %

# Gesetzliche Feiertage in NRW im Simulationszeitraum.
# An Feiertagen verhalten sich Kunden wie an einem Sonntag; die Produktionsplanung
# schaut aber nur auf den Wochentag -> genau hier entsteht Überproduktion.
HOLIDAYS = {
    date(2026, 1, 1): "Neujahr",
    date(2026, 4, 3): "Karfreitag",
    date(2026, 4, 6): "Ostermontag",
    date(2026, 5, 1): "Tag der Arbeit",
    date(2026, 5, 14): "Christi Himmelfahrt",
    date(2026, 5, 25): "Pfingstmontag",
    date(2026, 6, 4): "Fronleichnam",
}

OUT = Path(__file__).resolve().parent.parent / "data"

# ---------------------------------------------------------------- Stammdaten

CATEGORIES = {1: "Brötchen", 2: "Brot", 3: "Snacks", 4: "Süßgebäck", 5: "Kuchen"}

# id, name, category, price, unit_cost, shelf_life_hours, popularity
PRODUCTS = [
    (1, "Weizenbrötchen", 1, 0.45, 0.12, 12, 30),
    (2, "Körnerbrötchen", 1, 0.70, 0.20, 12, 14),
    (3, "Roggenbrötchen", 1, 0.60, 0.17, 12, 8),
    (4, "Laugenbrezel", 1, 0.95, 0.25, 12, 12),
    (5, "Croissant", 1, 1.40, 0.45, 12, 10),
    (6, "Bauernbrot", 2, 4.20, 1.30, 72, 4),
    (7, "Vollkornbrot", 2, 4.50, 1.45, 96, 3),
    (8, "Baguette", 2, 2.20, 0.60, 24, 6),
    (9, "Ciabatta", 2, 2.50, 0.75, 24, 3),
    (10, "Dinkelbrot", 2, 4.80, 1.60, 72, 2),
    (11, "Belegtes Käsebrötchen", 3, 3.20, 1.10, 8, 8),
    (12, "Schinken-Käse-Croissant", 3, 3.80, 1.40, 8, 6),
    (13, "Käse-Laugenstange", 3, 2.40, 0.80, 10, 7),
    (14, "Pizzaschnecke", 3, 2.60, 0.85, 10, 5),
    (15, "Berliner", 4, 1.60, 0.45, 24, 5),
    (16, "Zimtschnecke", 4, 2.30, 0.70, 24, 5),
    (17, "Apfeltasche", 4, 2.10, 0.65, 24, 4),
    (18, "Schoko-Donut", 4, 1.90, 0.55, 24, 4),
    (19, "Käsekuchen (Stück)", 5, 3.20, 1.00, 48, 4),
    (20, "Streuselkuchen (Stück)", 5, 2.80, 0.85, 48, 3),
    (21, "Bienenstich (Stück)", 5, 3.10, 1.00, 48, 2),
]

# id, name, district, location type, receipts per normal weekday
BRANCHES = [
    (1, "Filiale Bilk", "Bilk", "wohngebiet", 360),
    (2, "Filiale Medienhafen", "Hafen", "buero", 300),
    (3, "Filiale Hauptbahnhof", "Stadtmitte", "bahnhof", 430),
]

CUSTOMER_TYPES = {1: "Stammkunde", 2: "Laufkundschaft", 3: "Firmenkunde"}

SHIFTS = [(1, "Frühschicht", "06:00", "13:00"), (2, "Spätschicht", "13:00", "20:00")]  # Ende exklusiv

# Öffnungszeiten je Standort und Tagestyp: (erste Stunde, letzte Stunde) oder None = geschlossen
OPENING = {
    "wohngebiet": {"wd": (6, 18), "sa": (6, 16), "so": (7, 11)},
    "buero":      {"wd": (6, 17), "sa": (8, 12), "so": None},
    "bahnhof":    {"wd": (6, 19), "sa": (7, 19), "so": (8, 18)},
}

# Kundenzahl relativ zum Werktag (Mo..So)
WEEKDAY_FACTOR = {
    "wohngebiet": [0.95, 0.90, 0.90, 0.95, 1.05, 1.35, 1.10],
    "buero":      [1.05, 1.00, 1.00, 1.00, 0.85, 0.25, 0.00],
    "bahnhof":    [1.05, 1.00, 1.00, 1.00, 1.10, 0.85, 0.75],
}

# Wie stark eine Kategorie zu einer Stunde gefragt ist (Stunde -> Gewicht)
def hour_profile(cat, h):
    if cat == 1:   # Brötchen: klar morgens
        return {6: 3.0, 7: 4.0, 8: 4.0, 9: 3.0, 10: 2.0, 11: 1.2}.get(h, 0.5)
    if cat == 2:   # Brot: morgens und am frühen Abend
        return {8: 1.5, 9: 1.5, 10: 1.2, 16: 1.4, 17: 1.6, 18: 1.2}.get(h, 0.8)
    if cat == 3:   # Snacks: Mittag
        return {11: 2.0, 12: 4.0, 13: 3.5, 14: 1.5}.get(h, 0.6)
    if cat == 4:   # Süßgebäck: Vormittag + Nachmittag
        return {10: 1.5, 14: 1.6, 15: 2.0, 16: 1.6}.get(h, 0.8)
    return {14: 2.0, 15: 3.0, 16: 2.5, 17: 1.2}.get(h, 0.3)  # Kuchen: Kaffeezeit

# Wie viele Kunden in einer Stunde kommen (relativ)
def traffic(location, h):
    base = {6: 0.8, 7: 1.6, 8: 1.8, 9: 1.3, 10: 1.0, 11: 1.0, 12: 1.4,
            13: 1.2, 14: 0.8, 15: 1.0, 16: 1.0, 17: 0.9, 18: 0.7, 19: 0.5}.get(h, 0.5)
    if location == "buero" and h in (12, 13):
        base *= 1.6                       # Mittagspause im Büroviertel
    if location == "bahnhof" and h in (7, 8, 17, 18):
        base *= 1.3                       # Pendler
    return base

# Standortabhängige Vorlieben je Kategorie
LOCATION_CAT = {
    "wohngebiet": {1: 1.2, 2: 1.4, 3: 0.6, 4: 1.0, 5: 1.3},
    "buero":      {1: 0.9, 2: 0.4, 3: 1.8, 4: 1.1, 5: 0.8},
    "bahnhof":    {1: 1.0, 2: 0.5, 3: 1.6, 4: 1.2, 5: 0.6},
}


def day_type(d):
    return "so" if d.weekday() == 6 or d in HOLIDAYS else "sa" if d.weekday() == 5 else "wd"


def price_on(product, d):
    _, _, cat, price, *_ = product
    if cat == 1 and d < PRICE_CHANGE:
        return round(price / PRICE_CHANGE_FACTOR, 2)
    return price


def quantity_for(rng, cat, ctype):
    if ctype == 3 and cat in (1, 3):                  # Firmenkunde: Großbestellung
        return rng.randint(8, 25)
    if cat == 1:
        return rng.choices([1, 2, 3, 4, 5, 6, 10], [20, 25, 15, 18, 6, 10, 6])[0]
    if cat == 2:
        return 1
    return rng.choices([1, 2, 3], [70, 25, 5])[0]


def simulate():
    rng = random.Random(SEED)
    product_by_id = {p[0]: p for p in PRODUCTS}

    receipts, items, production, waste = [], [], [], []
    # unbeschränkte Nachfrage (inkl. verlorener Verkäufe) je (Filiale, Produkt, Wochentag)
    demand_history = defaultdict(list)
    receipt_id = 0

    day = START - timedelta(days=WARMUP_DAYS)
    while day <= END:
        record = day >= START
        for branch_id, _, _, loc, base_receipts in BRANCHES:
            hours = OPENING[loc][day_type(day)]
            if hours is None:
                continue
            wd = day.weekday()

            # 1) Produktion planen: Ø der letzten 4 gleichen Wochentage * Puffer
            stock = {}
            for p in PRODUCTS:
                hist = demand_history[(branch_id, p[0], wd)][-4:]
                if hist:
                    planned = sum(hist) / len(hist) * SAFETY_BUFFER
                else:
                    planned = base_receipts * WEEKDAY_FACTOR[loc][wd] * p[6] / 40
                stock[p[0]] = max(0, round(planned))
            baked = dict(stock)
            demand_today = defaultdict(int)

            # 2) Kunden des Tages simulieren
            behaves_like = 6 if day in HOLIDAYS else wd     # Feiertag = Kundenverhalten wie Sonntag
            n_receipts = round(base_receipts * WEEKDAY_FACTOR[loc][behaves_like] * rng.lognormvariate(0, 0.12))
            open_hours = list(range(hours[0], hours[1] + 1))
            hour_weights = [traffic(loc, h) for h in open_hours]

            for _ in range(n_receipts):
                h = rng.choices(open_hours, hour_weights)[0]
                ctype = rng.choices([1, 2, 3], [45, 52, 3])[0]
                if ctype == 3 and (behaves_like >= 5 or h > 11):
                    ctype = 2
                weights = [p[6] * hour_profile(p[2], h) * LOCATION_CAT[loc][p[2]]
                           * (PRICE_ELASTICITY if p[2] == 1 and day >= PRICE_CHANGE else 1.0)
                           for p in PRODUCTS]
                n_lines = rng.choices([1, 2, 3, 4], [50, 30, 15, 5])[0]
                chosen = set()
                while len(chosen) < n_lines:
                    chosen.add(rng.choices(PRODUCTS, weights)[0][0])

                lines = []
                for pid in sorted(chosen):
                    p = product_by_id[pid]
                    qty = quantity_for(rng, p[2], ctype)
                    demand_today[pid] += qty
                    sold = min(qty, stock[pid])
                    if sold > 0:
                        stock[pid] -= sold
                        lines.append((pid, sold, price_on(p, day)))
                if not lines:
                    continue                          # alles ausverkauft: Kunde geht ohne Kauf

                receipt_id += 1
                ts = datetime.combine(day, time(h, rng.randint(0, 59), rng.randint(0, 59)))
                total = sum(q * pr for _, q, pr in lines)
                pay = "karte" if rng.random() < min(0.85, 0.25 + total / 20) else "bar"
                if record:
                    receipts.append((receipt_id, branch_id, ctype, ts.isoformat(sep=" "), pay))
                    for line_no, (pid, q, pr) in enumerate(lines, start=1):
                        items.append((receipt_id, line_no, pid, q, f"{pr:.2f}"))

            # 3) Tagesabschluss: Produktion speichern, Reste abschreiben
            for p in PRODUCTS:
                pid = p[0]
                demand_history[(branch_id, pid, wd)].append(demand_today[pid])
                if not record:
                    continue
                production.append((branch_id, pid, day.isoformat(), baked[pid]))
                left = stock[pid]
                damaged = min(left, rng.choices([0, 1, 2], [85, 12, 3])[0])
                if damaged:
                    waste.append((branch_id, pid, day.isoformat(), "beschaedigt", damaged))
                if left - damaged > 0:
                    waste.append((branch_id, pid, day.isoformat(), "abgelaufen", left - damaged))
        day += timedelta(days=1)

    return receipts, items, production, waste


def write(name, header, rows):
    with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  {name}.csv: {len(rows):>7} Zeilen")


def main():
    OUT.mkdir(exist_ok=True)
    receipts, items, production, waste = simulate()
    print(f"Schreibe CSV-Dateien nach {OUT}")
    write("category", ["category_id", "name"], CATEGORIES.items())
    write("product", ["product_id", "name", "category_id", "price", "unit_cost", "shelf_life_hours"],
          [p[:6] for p in PRODUCTS])
    write("branch", ["branch_id", "name", "district", "location"], [b[:4] for b in BRANCHES])
    write("customer_type", ["customer_type_id", "name"], CUSTOMER_TYPES.items())
    write("shift", ["shift_id", "name", "start_time", "end_time"], SHIFTS)
    write("public_holiday", ["holiday_date", "name"],
          [(d.isoformat(), n) for d, n in sorted(HOLIDAYS.items())])
    write("receipt", ["receipt_id", "branch_id", "customer_type_id", "sold_at", "payment_method"], receipts)
    write("receipt_item", ["receipt_id", "line_no", "product_id", "quantity", "unit_price"], items)
    write("daily_production", ["branch_id", "product_id", "prod_date", "quantity_baked"], production)
    write("waste", ["branch_id", "product_id", "waste_date", "reason", "quantity_wasted"], waste)


if __name__ == "__main__":
    main()
