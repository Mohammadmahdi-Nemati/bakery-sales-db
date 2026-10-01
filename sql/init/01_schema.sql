-- =====================================================================
-- bakery-sales-db: Schema
-- Relationales Modell einer Bäckerei-Kette mit mehreren Filialen.
-- Ziel: Verkäufe, Produktion und Abfall so speichern, dass sich
-- Überproduktion erkennen und reduzieren lässt.
-- Normalisiert bis BCNF (Begründung: docs/normalisierung.md).
-- =====================================================================

DROP SCHEMA IF EXISTS bakery CASCADE;
CREATE SCHEMA bakery;
SET search_path TO bakery;

-- ---------------------------------------------------------------------
-- Stammdaten
-- ---------------------------------------------------------------------

CREATE TABLE category (
    category_id   SMALLINT     PRIMARY KEY,
    name          VARCHAR(40)  NOT NULL UNIQUE
);

CREATE TABLE product (
    product_id        SMALLINT      PRIMARY KEY,
    name              VARCHAR(60)   NOT NULL UNIQUE,
    category_id       SMALLINT      NOT NULL REFERENCES category (category_id),
    price             NUMERIC(5,2)  NOT NULL CHECK (price > 0),
    unit_cost         NUMERIC(5,2)  NOT NULL CHECK (unit_cost > 0),
    shelf_life_hours  SMALLINT      NOT NULL CHECK (shelf_life_hours > 0),
    CHECK (unit_cost < price)   -- kein Produkt wird mit Verlust verkauft
);

CREATE TABLE branch (
    branch_id   SMALLINT     PRIMARY KEY,
    name        VARCHAR(60)  NOT NULL UNIQUE,
    district    VARCHAR(40)  NOT NULL,
    location    VARCHAR(20)  NOT NULL CHECK (location IN ('wohngebiet', 'buero', 'bahnhof'))
);

CREATE TABLE customer_type (
    customer_type_id  SMALLINT     PRIMARY KEY,
    name              VARCHAR(30)  NOT NULL UNIQUE   -- Stammkunde, Laufkundschaft, Firmenkunde
);

-- Schichten als Zeitfenster; ein Verkauf wird über seine Uhrzeit
-- einer Schicht zugeordnet (siehe View v_receipt_shift).
CREATE TABLE shift (
    shift_id    SMALLINT     PRIMARY KEY,
    name        VARCHAR(20)  NOT NULL UNIQUE,
    start_time  TIME         NOT NULL,
    end_time    TIME         NOT NULL,
    CHECK (start_time < end_time)
);

-- Gesetzliche Feiertage (NRW). Wichtig für die Produktionsplanung,
-- weil Kunden an Feiertagen wie an einem Sonntag einkaufen.
CREATE TABLE public_holiday (
    holiday_date  DATE         PRIMARY KEY,
    name          VARCHAR(40)  NOT NULL
);

-- ---------------------------------------------------------------------
-- Bewegungsdaten
-- ---------------------------------------------------------------------

-- Ein Kassenbon (Beleg). Jeder Bon gehört zu genau einer Filiale.
CREATE TABLE receipt (
    receipt_id        INTEGER      PRIMARY KEY,
    branch_id         SMALLINT     NOT NULL REFERENCES branch (branch_id),
    customer_type_id  SMALLINT     NOT NULL REFERENCES customer_type (customer_type_id),
    sold_at           TIMESTAMP    NOT NULL,
    payment_method    VARCHAR(10)  NOT NULL CHECK (payment_method IN ('bar', 'karte'))
);

-- Bonposition: schwache Entität, identifiziert über (receipt_id, line_no).
-- unit_price ist der Preis ZUM VERKAUFSZEITPUNKT. Das ist keine Redundanz
-- zu product.price, denn Preise ändern sich über die Zeit.
CREATE TABLE receipt_item (
    receipt_id  INTEGER       NOT NULL REFERENCES receipt (receipt_id) ON DELETE CASCADE,
    line_no     SMALLINT      NOT NULL CHECK (line_no > 0),
    product_id  SMALLINT      NOT NULL REFERENCES product (product_id),
    quantity    SMALLINT      NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(5,2)  NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (receipt_id, line_no)
);

-- Tagesproduktion: wie viele Stück eines Produkts eine Filiale
-- an einem Tag bekommen hat.
CREATE TABLE daily_production (
    branch_id       SMALLINT  NOT NULL REFERENCES branch (branch_id),
    product_id      SMALLINT  NOT NULL REFERENCES product (product_id),
    prod_date       DATE      NOT NULL,
    quantity_baked  SMALLINT  NOT NULL CHECK (quantity_baked >= 0),
    PRIMARY KEY (branch_id, product_id, prod_date)
);

-- Abschriften (Abfall) am Ende des Tages, getrennt nach Grund.
-- Bezieht sich immer auf eine vorhandene Produktionsmenge (zusammengesetzter FK).
CREATE TABLE waste (
    branch_id         SMALLINT     NOT NULL,
    product_id        SMALLINT     NOT NULL,
    waste_date        DATE         NOT NULL,
    reason            VARCHAR(15)  NOT NULL CHECK (reason IN ('abgelaufen', 'beschaedigt')),
    quantity_wasted   SMALLINT     NOT NULL CHECK (quantity_wasted > 0),
    PRIMARY KEY (branch_id, product_id, waste_date, reason),
    FOREIGN KEY (branch_id, product_id, waste_date)
        REFERENCES daily_production (branch_id, product_id, prod_date)
);
