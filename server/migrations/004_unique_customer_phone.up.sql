-- 004_unique_customer_phone.up.sql
-- Enforces strict phone number uniqueness per business.
-- We only apply this to non-null, non-empty phone numbers, allowing walk-in customers without phones.

CREATE UNIQUE INDEX idx_customer_phone_unique 
ON customers(business_id, phone) 
WHERE phone IS NOT NULL AND phone != '';
