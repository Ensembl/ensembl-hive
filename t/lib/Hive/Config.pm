package Hive::Config;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use base qw{Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf};

sub default_options {
    my $self = shift;
    return { 
	%{ $self->SUPER::default_options },
	'hive_driver' => 'sqlite',
    };     
}

sub init_pipeline_here {
    my $self = shift->SUPER::new();

    {
	local @ARGV = @_;
	$self->process_options( 1 );
    }

    $self->run_pipeline_create_commands();

    my $dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
	-url => $self->pipeline_url,
	-no_sql_schema_version_check => 1,
	);

    $dba->load_collections;

    $self->add_objects_from_config();

    $dba->save_collections;

    return $self;
}

sub test_suite_init { return (); }

1;
