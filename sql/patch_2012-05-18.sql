
-- add a way to distinguish between meadows of the same type:
ALTER TABLE worker ADD COLUMN meadow_name VARCHAR(40) AFTER meadow_type;
