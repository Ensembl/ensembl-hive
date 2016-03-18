requires 'DBI';
requires 'DBD::mysql';
requires 'DBD::SQLite';
requires 'DBD::Pg';

requires 'JSON';

on 'test' => sub {
	requires 'Capture::Tiny';
	requires 'Test::Exception';
	requires 'Test::More';
}

