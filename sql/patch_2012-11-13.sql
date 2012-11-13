    # allow job_id and retry to be NULL by default, to make it possible for jobless workers to leave messages:
ALTER TABLE job_message MODIFY COLUMN job_id                    int(10) DEFAULT NULL;
ALTER TABLE job_message MODIFY COLUMN retry                     int(10) DEFAULT NULL;

    # re-route getting analysis_id/logic_name via worker table, so that it would work in the absence of the job:
CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM job_message m
    JOIN worker w USING (worker_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=w.analysis_id)
    LEFT JOIN job j ON (j.job_id=m.job_id);

