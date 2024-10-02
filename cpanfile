requires 'DBI';
requires 'DBD::mysql', '< 5.0'; # newer versions do not support MySQL 5
requires 'DBD::SQLite';
requires 'DBD::Pg';

requires 'Capture::Tiny';
requires 'DateTime';
requires 'Time::Piece';
requires 'JSON';
requires 'Proc::Daemon', '>= 0.23';
requires 'Email::Stuffer';
requires 'IPC::Cmd';
requires 'DateTime::Format::ISO8601';

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
   requires 'Devel::Cover';
   requires 'Devel::Cover::Report::Codecov';
};

recommends 'Getopt::ArgvFile';
recommends 'BSD::Resource';
recommends 'Chart::Gnuplot';
recommends 'GraphViz';

