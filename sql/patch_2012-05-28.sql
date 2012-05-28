
-- Relax the meadow_type field to take any short string - to better support external Meadows:
ALTER TABLE worker MODIFY COLUMN meadow_type VARCHAR(40);
ALTER TABLE resource_description MODIFY COLUMN meadow_type VARCHAR(40);

