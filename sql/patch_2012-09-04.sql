
# Substitute the legacy 'analysis' table with the slimmer version 'analysis_base',
# but do not bother deleting the original table in the patch
# because of the many already established foreign key relationships.

CREATE TABLE analysis_base (
  analysis_id                 int(10) unsigned NOT NULL AUTO_INCREMENT,
  logic_name                  VARCHAR(40) NOT NULL,
  module                      VARCHAR(255),
  parameters                  TEXT,

  PRIMARY KEY (analysis_id),
  UNIQUE KEY logic_name_idx (logic_name)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

INSERT INTO analysis_base (analysis_id, logic_name, module, parameters) SELECT analysis_id, logic_name, module, parameters FROM analysis;

