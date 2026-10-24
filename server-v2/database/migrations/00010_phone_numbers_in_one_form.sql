-- +goose Up

-- Phone numbers in one form, E.164 (B15).
--
-- "0712 345 678", "0712345678" and "+254712345678" were three customers in
-- one shop, and three different sign-ins. From now on internal/phone stores
-- every new number as +254712345678; this converts the ones already stored.
--
-- The rule is written a second time here, in SQL, because a migration must be
-- a fixed record and cannot call Go. internal/phone's tests run this function
-- against the same shared cases as phone.Normalize (testdata/shared/phone.json),
-- so the two cannot drift apart. NULL means "not a phone number".
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION salio_canonical_phone(raw text) RETURNS text
    LANGUAGE sql IMMUTABLE AS $$
    WITH typed AS (
        SELECT btrim(raw, E' \t\n\r') AS t
    ), digits AS (
        -- Only digits, a leading +, and the separators people type.
        SELECT CASE WHEN t ~ '^\+?[0-9 ().-]*$'
                    THEN regexp_replace(t, '[ ().-]', '', 'g') END AS d
        FROM typed
    )
    SELECT CASE
        WHEN d ~ '^\+254[1-9][0-9]{8}$'  THEN d
        WHEN d ~ '^00254[1-9][0-9]{8}$'  THEN '+' || substr(d, 3)
        WHEN d ~ '^254[1-9][0-9]{8}$'    THEN '+' || d
        WHEN d ~ '^0[1-9][0-9]{8}$'      THEN '+254' || substr(d, 2)
        WHEN d ~ '^[71][0-9]{8}$'        THEN '+254' || d
        -- A Kenyan code with the wrong number of digits is not some other
        -- country's number.
        WHEN d ~ '^(\+|00)254'           THEN NULL
        WHEN d ~ '^\+[1-9][0-9]{7,14}$'  THEN d
        WHEN d ~ '^00[1-9][0-9]{7,14}$'  THEN '+' || substr(d, 3)
    END
    FROM digits
$$;
-- +goose StatementEnd

-- FORCE ROW LEVEL SECURITY applies policies to the tables' owner as well, so
-- without a tenant this migration would see no rows and convert nothing,
-- quietly. It is lifted for this transaction only, and restored below
-- before the transaction commits.
ALTER TABLE users     NO FORCE ROW LEVEL SECURITY;
ALTER TABLE customers NO FORCE ROW LEVEL SECURITY;
ALTER TABLE suppliers NO FORCE ROW LEVEL SECURITY;

-- Converted only where the result is free. Two records that turn out to be one
-- number are left exactly as they were, both of them, for a person to decide
-- about: merging two customers' ledgers, or two people's logins, is not a
-- migration's call. docs/09 has the query that lists them.

-- Logins: unique across every shop.
UPDATE users u
   SET phone = salio_canonical_phone(u.phone)
 WHERE salio_canonical_phone(u.phone) IS NOT NULL
   AND salio_canonical_phone(u.phone) <> u.phone
   AND NOT EXISTS (
        SELECT 1 FROM users o
         WHERE o.id <> u.id
           AND coalesce(salio_canonical_phone(o.phone), o.phone) = salio_canonical_phone(u.phone));

-- Customers: unique within a shop.
UPDATE customers c
   SET phone = salio_canonical_phone(c.phone)
 WHERE c.phone IS NOT NULL
   AND salio_canonical_phone(c.phone) IS NOT NULL
   AND salio_canonical_phone(c.phone) <> c.phone
   AND NOT EXISTS (
        SELECT 1 FROM customers o
         WHERE o.business_id = c.business_id
           AND o.id <> c.id
           AND o.phone IS NOT NULL
           AND coalesce(salio_canonical_phone(o.phone), o.phone) = salio_canonical_phone(c.phone));

-- Suppliers: no uniqueness, so every readable number is converted.
UPDATE suppliers s
   SET phone = salio_canonical_phone(s.phone)
 WHERE s.phone IS NOT NULL
   AND salio_canonical_phone(s.phone) IS NOT NULL
   AND salio_canonical_phone(s.phone) <> s.phone;

ALTER TABLE users     FORCE ROW LEVEL SECURITY;
ALTER TABLE customers FORCE ROW LEVEL SECURITY;
ALTER TABLE suppliers FORCE ROW LEVEL SECURITY;

-- The UPDATEs move each changed customer's and supplier's change_seq (the
-- bump_change_seq trigger), so every phone receives the new form on its next
-- pull.

-- +goose Down

-- The old forms are not kept, so the conversion cannot be undone; only the
-- function goes.
DROP FUNCTION IF EXISTS salio_canonical_phone(text);
