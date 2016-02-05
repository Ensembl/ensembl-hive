requires 'DBI';
requires 'DBD::mysql';
requires 'DBD::SQLite';
requires 'DBD::Pg';

requires 'Capture::Tiny';
requires 'DateTime';
requires 'JSON';

on 'test' => sub {
	requires 'Test::Exception';
	requires 'Test::More';
	requires 'Test::Warn';
};

recommends 'Getopt::ArgvFile';

