# Extend several fields in analysis to 255 characters:

ALTER TABLE analysis     MODIFY COLUMN module varchar(255);
ALTER TABLE db_file      MODIFY COLUMN module varchar(255);
ALTER TABLE program      MODIFY COLUMN module varchar(255);
ALTER TABLE program_file MODIFY COLUMN module varchar(255);
