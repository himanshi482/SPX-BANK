-- Run this once as the Amazon RDS master user after database/setup_db.sql.
-- Replace the password only at execution time; never commit a real value.
CREATE USER IF NOT EXISTS 'spxapp'@'%' IDENTIFIED BY 'REPLACE_WITH_STRONG_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON spxbank.* TO 'spxapp'@'%';
FLUSH PRIVILEGES;
