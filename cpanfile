requires 'DBI';
requires 'DBD::mysql';
requires 'DBD::SQLite';
requires 'DBD::Pg';

requires 'Capture::Tiny';
requires 'DateTime';
requires 'HTML::Entities';
requires 'JSON';

on 'test' => sub {
	requires 'Test::Exception';
	requires 'Test::More';
	requires 'Test::Warn';
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

recommends 'HTTP::Daemon';
recommends 'HTTP::Status';

