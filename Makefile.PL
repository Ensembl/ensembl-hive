
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Bio::EnsEMBL::Hive',
    VERSION_FROM      => 'modules/Bio/EnsEMBL/Hive.pm', # finds $VERSION

    PREREQ_PM         => { JSON => 0, }, # e.g., Module::Name => 1.1

    PMLIBDIRS         => [ qw{ lib modules } ],
    PMLIBPARENTDIRS   => [ qw{ modules } ],


    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'modules/Bio/EnsEMBL/Hive.pm', # retrieve abstract from module
       AUTHOR         => 'Leo Gordon') : ()),

    test => { TESTS   => 't/*/*.t' },
);
