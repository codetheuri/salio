-- +goose Up

-- The zone a business's calendar dates are taken in: which day "today" is when
-- a debt is recorded without a date, the date on a purchase order, the default
-- range of a report.
--
-- Only dates depend on it. Every instant — created_at, sync cursors, field
-- versions — stays a timestamptz in UTC.
--
-- Every existing business is in Kenya, so the default is also the backfill.
-- Names are validated against Go's IANA database on every API write; a CHECK
-- cannot consult that database, so this only refuses the blank value that
-- would mean "whatever the server is set to".
ALTER TABLE businesses
    ADD COLUMN time_zone VARCHAR(64) NOT NULL DEFAULT 'Africa/Nairobi'
        CHECK (btrim(time_zone) <> '');

-- +goose Down
ALTER TABLE businesses DROP COLUMN IF EXISTS time_zone;
