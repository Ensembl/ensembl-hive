    # adding a new table for accumulated dataflow:

CREATE TABLE accu (
    sending_job_id          int(10),
    receiving_job_id        int(10) NOT NULL,
    struct_name             varchar(255) NOT NULL,
    key_signature           varchar(255) NOT NULL,
    value                   varchar(255)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

