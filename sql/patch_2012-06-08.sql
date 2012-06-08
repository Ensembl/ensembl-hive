

-- Split the former resource_description table into two:

-- Create a new auto-incrementing table:
DROP TABLE IF EXISTS resource_class;
CREATE TABLE resource_class (
    resource_class_id   int(10) unsigned NOT NULL AUTO_INCREMENT,     # unique internal id
    name                varchar(40) NOT NULL,

    PRIMARY KEY(resource_class_id),
    UNIQUE KEY(name)
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

-- Populate it with data from resource_description (unfortunately, id<=0 will be ignored - let's hope they were not used!)
INSERT INTO resource_class (resource_class_id, name) SELECT rc_id, description from resource_description WHERE rc_id>0;

-- The population command may crash if the original "description" contained non-unique values -
--   just fix the original table and reapply the patch.

-- Now drop the name/description column:
ALTER TABLE resource_description DROP COLUMN description;


