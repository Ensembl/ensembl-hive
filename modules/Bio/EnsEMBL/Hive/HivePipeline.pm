package Bio::EnsEMBL::Hive::HivePipeline;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify');
use Bio::EnsEMBL::Hive::Utils::Collection;

    # needed for offline graph generation:
use Bio::EnsEMBL::Hive::Accumulator;
use Bio::EnsEMBL::Hive::NakedTable;


sub hive_dba {      # The adaptor for HivePipeline objects
    my $self = shift @_;

    if(@_) {
        $self->{'_hive_dba'} = shift @_;
        $self->{'_hive_dba'}->hive_pipeline($self) if $self->{'_hive_dba'};
    }
    return $self->{'_hive_dba'};
}


sub display_name {
    my $self = shift @_;

    if(my $dbc = $self->hive_dba && $self->hive_dba->dbc) {
        return $dbc->dbname . '@' .($dbc->host||'');
    } else {
        return '(unstored '.$self->hive_pipeline_name.')';
    }
}


sub collection_of {
    my $self = shift @_;
    my $type = shift @_;

    if (@_) {
        $self->{'_cache_by_class'}->{$type} = shift @_;
    } elsif (not $self->{'_cache_by_class'}->{$type}) {

        if( (my $hive_dba = $self->hive_dba) and ($type ne 'NakedTable') and ($type ne 'Accumulator') ) {
            my $adaptor = $hive_dba->get_adaptor( $type );
            my $all_objects = $adaptor->fetch_all();
            if(@$all_objects and UNIVERSAL::can($all_objects->[0], 'hive_pipeline') ) {
                $_->hive_pipeline($self) for @$all_objects;
            }
            $self->{'_cache_by_class'}->{$type} = Bio::EnsEMBL::Hive::Utils::Collection->new( $all_objects );
        } else {
            $self->{'_cache_by_class'}->{$type} = Bio::EnsEMBL::Hive::Utils::Collection->new();
        }
    }

    return $self->{'_cache_by_class'}->{$type};
}


sub find_by_url_query {
    my $self        = shift @_;
    my $parsed_url  = shift @_;

    my $table_name      = $parsed_url->{'table_name'};
    my $tparam_name     = $parsed_url->{'tparam_name'};
    my $tparam_value    = $parsed_url->{'tparam_value'};

    if($table_name eq 'analysis') {

        die "Analyses can only be found using either logic_name or dbID" unless($tparam_name=~/^(logic_name|dbID)$/);

        return $self->collection_of('Analysis')->find_one_by( $tparam_name, $tparam_value);

    } elsif($table_name eq 'accu') {
        my $accu;

        unless($accu = $self->collection_of('Accumulator')->find_one_by( 'struct_name', $tparam_name, 'signature_template', $tparam_value )) {

            $accu = $self->add_new_or_update( 'Accumulator',
                $self->hive_dba ? (adaptor => $self->hive_dba->get_AccumulatorAdaptor) : (),
                struct_name        => $tparam_name,
                signature_template => $tparam_value,
            );
        }

        return $accu;

    } elsif($table_name eq 'job') {

        die "Jobs cannot yet be found by URLs, sorry";

    } else {
        my $naked_table;

        unless($naked_table = $self->collection_of('NakedTable')->find_one_by( 'table_name', $table_name )) {

            $naked_table = $self->add_new_or_update( 'NakedTable',
                $self->hive_dba ? (adaptor => $self->hive_dba->get_NakedTableAdaptor( 'table_name' => $table_name ) ) : (),
                table_name => $table_name,
                $tparam_value ? (insertion_method => $tparam_value) : (),
            );
        }

        return $naked_table;
    }
}


sub new {       # construct an attached or a detached Pipeline object
    my $class           = shift @_;

    my $self = bless {}, $class;

    my %dba_flags           = @_;
    my $existing_dba        = delete $dba_flags{'-dba'};

    if(%dba_flags) {
        my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( %dba_flags );
        $self->hive_dba( $hive_dba );
    } elsif ($existing_dba) {
        $self->hive_dba( $existing_dba );
    } else {
#       warn "Created a standalone pipeline";
    }

    return $self;
}


    # If there is a DBAdaptor, collection_of() will fetch a collection on demand:
sub invalidate_collections {
    my $self = shift @_;

    delete $self->{'_cache_by_class'};
    return;
}


sub save_collections {
    my $self = shift @_;

    my $hive_dba = $self->hive_dba();

    foreach my $AdaptorType ('MetaParameters', 'PipelineWideParameters', 'ResourceClass', 'ResourceDescription', 'Analysis', 'AnalysisStats', 'AnalysisCtrlRule', 'DataflowRule', 'DataflowTarget') {
        my $adaptor = $hive_dba->get_adaptor( $AdaptorType );
        my $class = 'Bio::EnsEMBL::Hive::'.$AdaptorType;
        foreach my $storable_object ( $self->collection_of( $AdaptorType )->list ) {
            $adaptor->store_or_update_one( $storable_object, $class->unikey() );
#            warn "Stored/updated ".$storable_object->toString()."\n";
        }
    }

    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
    foreach my $analysis ( $self->collection_of( 'Analysis' )->list ) {
        if(my $our_jobs = $analysis->jobs_collection ) {
            $job_adaptor->store( $our_jobs );
            foreach my $job (@$our_jobs) {
#                warn "Stored ".$job->toString()."\n";
            }
        }
    }
}


sub add_new_or_update {
    my $self = shift @_;
    my $type = shift @_;

    my $class = 'Bio::EnsEMBL::Hive::'.$type;

    my $object;

    if( my $unikey_keys = $class->unikey() ) {
        my %other_pairs = @_;
        my %unikey_pairs;
        @unikey_pairs{ @$unikey_keys} = delete @other_pairs{ @$unikey_keys };

        if( $object = $self->collection_of( $type )->find_one_by( %unikey_pairs ) ) {
            my $found_display = UNIVERSAL::can($object, 'toString') ? $object->toString : stringify($object);
            if(keys %other_pairs) {
                warn "Updating $found_display with (".stringify(\%other_pairs).")\n";
                if( ref($object) eq 'HASH' ) {
                    @$object{ keys %other_pairs } = values %other_pairs;
                } else {
                    while( my ($key, $value) = each %other_pairs ) {
                        $object->$key($value);
                    }
                }
            } else {
                warn "Found a matching $found_display\n";
            }
        }
    } else {
        warn "$class doesn't redefine unikey(), so unique objects cannot be identified";
    }

    unless( $object ) {
        $object = $class->can('new') ? $class->new( @_ ) : { @_ };

        $self->collection_of( $type )->add( $object );

        $object->hive_pipeline($self) if UNIVERSAL::can($object, 'hive_pipeline');

        my $found_display = UNIVERSAL::can($object, 'toString') ? $object->toString : 'naked entry '.stringify($object);
        warn "Created a new $found_display\n";
    }

    return $object;
}


=head2 get_source_analyses

    Description: returns a listref of analyses that do not have local inflow ("source analyses")

=cut

sub get_source_analyses {
    my $self = shift @_;

    my (%refset_of_analyses) = map { ("$_" => $_) } $self->collection_of( 'Analysis' )->list;

    foreach my $df_target ($self->collection_of( 'DataflowTarget' )->list) {
        delete $refset_of_analyses{ $df_target->to_analysis };
    }

    return [ values %refset_of_analyses ];
}


=head2 get_meta_value_by_key

    Description: returns a particular meta_value from 'MetaParameters' collection given meta_key

=cut

sub get_meta_value_by_key {
    my ($self, $meta_key) = @_;

    my $hash = $self->collection_of( 'MetaParameters' )->find_one_by( 'meta_key', $meta_key );
    return $hash && $hash->{'meta_value'};
}


=head2 hive_use_param_stack

    Description: (getter only) defines which one of two modes of parameter propagation is used in this pipeline

=cut

sub hive_use_param_stack {
    my $self = shift @_;

    return $self->get_meta_value_by_key('hive_use_param_stack') // 0;
}


=head2 hive_pipeline_name

    Description: (getter only) defines the symbolic name of the pipeline

=cut

sub hive_pipeline_name {
    my $self = shift @_;

    return $self->get_meta_value_by_key('hive_pipeline_name') // '';
}


=head2 params_as_hash

    Description: returns the destringified contents of the 'PipelineWideParameters' collection as a hash

=cut

sub params_as_hash {
    my $self = shift @_;

    my $collection = $self->collection_of( 'PipelineWideParameters' );
    return { map { $_->{'param_name'} => destringify($_->{'param_value'}) } $collection->list() };
}


sub print_diagram {
    my $self = shift @_;

    print ''.('─'x20).'[ '.$self->display_name.' ]'.('─'x20)."\n";

    my %seen = ();
    foreach my $source_analysis ( @{ $self->get_source_analyses } ) {
        print "\n";
        $source_analysis->print_diagram_node($self, '', \%seen);
    }
    foreach my $cyclic_analysis ( $self->collection_of( 'Analysis' )->list ) {
        next if $seen{$cyclic_analysis};
        print "\n";
        $cyclic_analysis->print_diagram_node($self, '', \%seen);
    }
}


1;
