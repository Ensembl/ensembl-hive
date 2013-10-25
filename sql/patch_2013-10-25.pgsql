    -- extend all VARCHAR fields to 255 (this will not affect neither storage nor performance) :

ALTER TABLE analysis_base           ALTER COLUMN logic_name  SET DATA TYPE VARCHAR(255);
ALTER TABLE analysis_base           ALTER COLUMN meadow_type SET DATA TYPE VARCHAR(255);
ALTER TABLE resource_class          ALTER COLUMN name        SET DATA TYPE VARCHAR(255);
ALTER TABLE resource_description    ALTER COLUMN meadow_type SET DATA TYPE VARCHAR(255);
ALTER TABLE hive_meta               ALTER COLUMN meta_key    SET DATA TYPE VARCHAR(255);
ALTER TABLE meta                    ALTER COLUMN meta_key    SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN meadow_type SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN meadow_name SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN host        SET DATA TYPE VARCHAR(255);
ALTER TABLE worker                  ALTER COLUMN process_id  SET DATA TYPE VARCHAR(255);

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=53 WHERE meta_key='hive_sql_schema_version' AND meta_value='52';

