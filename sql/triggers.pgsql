/*

DESCRIPTION

    Triggers for automatic synchronization (currently off by default)


LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

*/


CREATE FUNCTION add_job() RETURNS TRIGGER AS $add_job$
BEGIN
    UPDATE analysis_stats SET
        total_job_count         = total_job_count       + 1,
        semaphored_job_count    = semaphored_job_count  + (CASE NEW.status WHEN 'SEMAPHORED'    THEN 1                         ELSE 0 END),
        ready_job_count         = ready_job_count       + (CASE NEW.status WHEN 'READY'         THEN 1                         ELSE 0 END),
        done_job_count          = done_job_count        + (CASE NEW.status WHEN 'DONE'          THEN 1 WHEN 'PASSED_ON' THEN 1 ELSE 0 END),
        failed_job_count        = failed_job_count      + (CASE NEW.status WHEN 'FAILED'        THEN 1                         ELSE 0 END),
        status              = (CASE WHEN status='EMPTY' THEN 'READY' ELSE status END)
    WHERE analysis_id = NEW.analysis_id;
    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$add_job$ LANGUAGE plpgsql;

CREATE TRIGGER add_job AFTER INSERT ON job FOR EACH ROW EXECUTE PROCEDURE add_job();



CREATE FUNCTION delete_job() RETURNS TRIGGER AS $delete_job$
BEGIN
    UPDATE analysis_stats SET
        total_job_count         = total_job_count       - 1,
        semaphored_job_count    = semaphored_job_count  - (CASE OLD.status WHEN 'SEMAPHORED'    THEN 1                         ELSE 0 END),
        ready_job_count         = ready_job_count       - (CASE OLD.status WHEN 'READY'         THEN 1                         ELSE 0 END),
        done_job_count          = done_job_count        - (CASE OLD.status WHEN 'DONE'          THEN 1 WHEN 'PASSED_ON' THEN 1 ELSE 0 END),
        failed_job_count        = failed_job_count      - (CASE OLD.status WHEN 'FAILED'        THEN 1                         ELSE 0 END)
    WHERE analysis_id = OLD.analysis_id;
    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$delete_job$ LANGUAGE plpgsql;

CREATE TRIGGER delete_job AFTER DELETE ON job FOR EACH ROW EXECUTE PROCEDURE delete_job();



CREATE FUNCTION update_job() RETURNS TRIGGER AS $update_job$
BEGIN
    CASE WHEN (OLD.status<>NEW.status OR OLD.analysis_id<>NEW.analysis_id) THEN
        BEGIN
            UPDATE analysis_stats SET
                total_job_count         = total_job_count       - 1,
                semaphored_job_count    = semaphored_job_count  - (CASE OLD.status WHEN 'SEMAPHORED'    THEN 1                         ELSE 0 END),
                ready_job_count         = ready_job_count       - (CASE OLD.status WHEN 'READY'         THEN 1                         ELSE 0 END),
                done_job_count          = done_job_count        - (CASE OLD.status WHEN 'DONE'          THEN 1 WHEN 'PASSED_ON' THEN 1 ELSE 0 END),
                failed_job_count        = failed_job_count      - (CASE OLD.status WHEN 'FAILED'        THEN 1                         ELSE 0 END)
            WHERE analysis_id = OLD.analysis_id;
            UPDATE analysis_stats SET
                total_job_count         = total_job_count       + 1,
                semaphored_job_count    = semaphored_job_count  + (CASE NEW.status WHEN 'SEMAPHORED'    THEN 1                         ELSE 0 END),
                ready_job_count         = ready_job_count       + (CASE NEW.status WHEN 'READY'         THEN 1                         ELSE 0 END),
                done_job_count          = done_job_count        + (CASE NEW.status WHEN 'DONE'          THEN 1 WHEN 'PASSED_ON' THEN 1 ELSE 0 END),
                failed_job_count        = failed_job_count      + (CASE NEW.status WHEN 'FAILED'        THEN 1                         ELSE 0 END)
            WHERE analysis_id = NEW.analysis_id;
        END;
    ELSE BEGIN END;
    END CASE;
    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$update_job$ LANGUAGE plpgsql;

CREATE TRIGGER update_job AFTER UPDATE ON job FOR EACH ROW EXECUTE PROCEDURE update_job();



CREATE FUNCTION add_role() RETURNS TRIGGER AS $add_role$
BEGIN
    UPDATE analysis_stats SET
        num_running_workers = num_running_workers + 1
    WHERE analysis_id = NEW.analysis_id;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$add_role$ LANGUAGE plpgsql;

CREATE TRIGGER add_role AFTER INSERT ON role FOR EACH ROW EXECUTE PROCEDURE add_role();



CREATE FUNCTION update_role() RETURNS TRIGGER AS $update_role$
BEGIN
    UPDATE analysis_stats SET
        num_running_workers = num_running_workers - 1
    WHERE analysis_id = NEW.analysis_id
      AND OLD.when_finished IS NULL
      AND NEW.when_finished IS NOT NULL;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$update_role$ LANGUAGE plpgsql;

CREATE TRIGGER update_role AFTER UPDATE ON role FOR EACH ROW EXECUTE PROCEDURE update_role();



    -- inform the runtime part of the system that triggers are in place:
INSERT INTO hive_meta (meta_key, meta_value) VALUES ('hive_use_triggers', '1');
