# adding resource requirements:

ALTER TABLE analysis_stats ADD COLUMN rc_id int(10) unsigned default 0 NOT NULL;
ALTER TABLE analysis_stats_monitor ADD COLUMN rc_id int(10) unsigned default 0 NOT NULL;

CREATE TABLE resource_description (
    rc_id                 int(10) unsigned DEFAULT 0 NOT NULL,
    meadow_type           enum('LSF', 'LOCAL') DEFAULT 'LSF' NOT NULL,
    parameters            varchar(255) DEFAULT '' NOT NULL,
    description           varchar(255),
    PRIMARY KEY(rc_id, meadow_type)
) ENGINE=InnoDB;

