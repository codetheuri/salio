-- 001_initial_schema.down.sql
-- Rolls back ALL tables created in the 001 up migration.
-- golang-migrate calls this when you run: migrate down 1
-- ORDER MATTERS: Drop child tables before parent tables (foreign key constraint order)

DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS business_invites;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS businesses;
