
    # create the 3 analyses we are going to use:
INSERT INTO analysis (created, logic_name, module) VALUES (NOW(), 'start',          'Bio::EnsEMBL::Hive::RunnableDB::LongMult::Start');
INSERT INTO analysis (created, logic_name, module) VALUES (NOW(), 'part_multiply',  'Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply');
INSERT INTO analysis (created, logic_name, module) VALUES (NOW(), 'add_together',   'Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether');

    # link the analyses with control- and dataflow-rules:
INSERT INTO analysis_ctrl_rule (condition_analysis_url, ctrled_analysis_id) VALUES ('start', (SELECT analysis_id FROM analysis WHERE logic_name='add_together'));
INSERT INTO analysis_ctrl_rule (condition_analysis_url, ctrled_analysis_id) VALUES ('part_multiply', (SELECT analysis_id FROM analysis WHERE logic_name='add_together'));
INSERT INTO dataflow_rule (from_analysis_id, to_analysis_url) VALUES ((SELECT analysis_id FROM analysis WHERE logic_name='start'), 'add_together');

    # create a table for holding intermediate results (written by 'part_multiply' and read by 'add_together')
CREATE TABLE intermediate_result (
    a_multiplier    char(40) NOT NULL,
    digit           tinyint NOT NULL,
    result          char(41) NOT NULL,
    PRIMARY KEY (a_multiplier, digit)
);

    # create a table for holding final results (written by 'add_together')
CREATE TABLE final_result (
    a_multiplier    char(40) NOT NULL,
    b_multiplier    char(40) NOT NULL,
    result          char(80) NOT NULL,
    PRIMARY KEY (a_multiplier, b_multiplier)
);

