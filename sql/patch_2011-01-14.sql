# Extend several fields in analysis to 255 characters:

ALTER TABLE analysis MODIFY COLUMN module       VARCHAR(255);
ALTER TABLE analysis MODIFY COLUMN db_file      VARCHAR(255);
ALTER TABLE analysis MODIFY COLUMN program      VARCHAR(255);
ALTER TABLE analysis MODIFY COLUMN program_file VARCHAR(255);

ALTER TABLE meta DROP INDEX species_key_value_idx;
ALTER TABLE meta DROP INDEX species_value_idx;
ALTER TABLE meta MODIFY COLUMN meta_value TEXT;
ALTER TABLE meta ADD UNIQUE KEY species_key_value_idx (species_id,meta_key,meta_value(255));
ALTER TABLE meta ADD        KEY species_value_idx (species_id,meta_value(255));

