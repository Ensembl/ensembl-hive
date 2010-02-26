##########################################################################################
#
# Some stored functions and procedures used in hive:
#

############ make it more convenient to convert logic_name into analysis_id: #############

DROP FUNCTION IF EXISTS analysis_name2id;
DELIMITER |
CREATE FUNCTION analysis_name2id(param_logic_name CHAR(64))
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE var_analysis_id INT;
    SELECT analysis_id INTO var_analysis_id FROM analysis WHERE logic_name=param_logic_name;
    RETURN var_analysis_id;
END
|
DELIMITER ;


############## show hive progress for all analyses: #######################################

DROP PROCEDURE IF EXISTS show_progress;
CREATE PROCEDURE show_progress()
    SELECT CONCAT(a.logic_name,'(',a.analysis_id,')') analysis_name_and_id, j.status, j.retry_count, count(*)
    FROM analysis_job j, analysis a
    WHERE a.analysis_id=j.analysis_id
    GROUP BY a.analysis_id, j.status, j.retry_count
    ORDER BY a.analysis_id, j.status;

############## show hive progress for a particular analysis (given by name) ###############

DROP PROCEDURE IF EXISTS show_progress_analysis;
CREATE PROCEDURE show_progress_analysis(IN param_logic_name char(64))
    SELECT CONCAT(a.logic_name,'(',a.analysis_id,')') analysis_name_and_id, j.status, j.retry_count, count(*)
    FROM analysis_job j, analysis a
    WHERE a.analysis_id=j.analysis_id
    AND   a.logic_name=param_logic_name
    GROUP BY j.status, j.retry_count;

############## reset failed jobs for analysis #############################################

DROP PROCEDURE IF EXISTS reset_failed_jobs_for_analysis;
CREATE PROCEDURE reset_failed_jobs_for_analysis(IN param_logic_name char(64))
    UPDATE analysis_job j, analysis a
    SET j.status='READY', j.retry_count=0, j.job_claim=''
    WHERE a.logic_name=param_logic_name
    AND   a.analysis_id=j.analysis_id
    AND   j.status='FAILED';

