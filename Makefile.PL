
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Bio::EnsEMBL::Hive',
    VERSION_FROM      => 'modules/Bio/EnsEMBL/Hive/Version.pm', # finds $VERSION

    PREREQ_PM         => { JSON => 0, }, # e.g., Module::Name => 1.1

    PMLIBDIRS         => [ qw{ lib modules } ],
    PMLIBPARENTDIRS   => [ qw{ modules } ],


    ABSTRACT          => 'A system for creating and running pipelines on a distributed compute resource',
    AUTHOR            => 'Leo Gordon',

    test => { TESTS   => 't/*/*.t' },
);
