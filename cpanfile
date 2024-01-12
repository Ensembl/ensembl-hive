requires 'DBI';
requires 'DBD::mysql', '<= 4.050'; # newer versions do not support MySQL 5
requires 'DBD::SQLite';
requires 'DBD::Pg';

requires 'Capture::Tiny';
requires 'DateTime';
requires 'Time::Piece';
requires 'JSON';
requires 'Proc::Daemon', '0.23';
requires 'Email::Stuffer';

on 'test' => sub {
	requires 'Test::Exception';
	requires 'Test::More';
	requires 'Test::Warn';
	requires 'Test::JSON';
	requires 'Test::Warnings';
	requires 'Test::File::Contents';
	requires 'Test::Perl::Critic';
	requires 'Perl::Critic::Utils';
	requires 'GraphViz';
};

recommends 'Getopt::ArgvFile';
recommends 'BSD::Resource';
recommends 'Chart::Gnuplot';
recommends 'GraphViz';

