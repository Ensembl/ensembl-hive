
    -- First remove the ForeignKeys from job.worker_id and job_file.worker_id:
ALTER TABLE job DROP CONSTRAINT job_worker_id_fkey;
ALTER TABLE job_file DROP CONSTRAINT job_file_worker_id_fkey;

    -- Also remove Indices from the old columns:
DROP INDEX job_worker_id_status_idx;
DROP INDEX job_file_worker_id_idx;

    -- Add role_id columns:
ALTER TABLE job ADD COLUMN role_id INTEGER DEFAULT NULL;
ALTER TABLE job_file ADD COLUMN role_id INTEGER DEFAULT NULL;

    -- Pretend we had role entries from the very beginning (the data is very approximately correct!):
UPDATE job j set role_id = (SELECT r.role_id FROM role r WHERE r.worker_id=j.worker_id AND CASE WHEN completed IS NOT NULL THEN when_started<=completed AND (when_finished IS NULL OR completed<=when_finished) ELSE when_finished IS NULL END);
UPDATE job_file jf set role_id = (SELECT role_id FROM job j WHERE j.job_id=jf.job_id);

    -- Now we can drop the columns themselves:
ALTER TABLE job DROP COLUMN worker_id;
ALTER TABLE job_file DROP COLUMN worker_id;

    -- Add new Indices:
CREATE INDEX ON job (role_id, status);
CREATE INDEX ON job_file (role_id);


    -- Add ForeignKeys on the new columns:
ALTER TABLE job                     ADD FOREIGN KEY (role_id)                   REFERENCES role(role_id)                        ON DELETE CASCADE;
ALTER TABLE job_file                ADD FOREIGN KEY (role_id)                   REFERENCES role(role_id)                        ON DELETE CASCADE;

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=62 WHERE meta_key='hive_sql_schema_version' AND meta_value='61';

