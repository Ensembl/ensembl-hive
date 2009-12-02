
    # To multiply two long numbers using the long_mult pipeline
    # we have to create the 'start' job and provide the two multipliers:

INSERT INTO analysis_job (analysis_id, input_id) VALUES (
    (SELECT analysis_id FROM analysis WHERE logic_name='start'),
    "{ 'a_multiplier' => '123456789', 'b_multiplier' => '90319' }");

