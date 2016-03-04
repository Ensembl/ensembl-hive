package Bio::EnsEMBL::Hive::HivePipeline;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify', 'throw');
use Bio::EnsEMBL::Hive::Utils::Collection;
use Bio::EnsEMBL::Hive::Utils::PCL;

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


sub find_by_query {
    my $self            = shift @_;
    my $query_params    = shift @_;

    if(my $object_type = delete $query_params->{'object_type'}) {
        my $object;

        if($object_type eq 'Accumulator' or $object_type eq 'NakedTable') {

            unless($object = $self->collection_of($object_type)->find_one_by( %$query_params )) {

                my @specific_adaptor_params = ($object_type eq 'NakedTable') ? ('table_name' => $query_params->{'table_name'}) : ();
                ($object) = $self->add_new_or_update( $object_type, # NB: add_new_or_update returns a list
                    %$query_params,
                    $self->hive_dba ? ('adaptor' => $self->hive_dba->get_adaptor($object_type, @specific_adaptor_params)) : (),
                );
            }
        } else {
            $object = $self->collection_of($object_type)->find_one_by( %$query_params );
        }

        return $object || throw("Could not find an '$object_type' object from query ".stringify($query_params)." in ".$self->display_name);

    } else {
        throw("Could not find or guess the object_type from the query ".stringify($query_params)." , so could not find the object");
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
    my $newly_made = 0;

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
        $newly_made = 1;

        $self->collection_of( $type )->add( $object );

        $object->hive_pipeline($self) if UNIVERSAL::can($object, 'hive_pipeline');

        my $found_display = UNIVERSAL::can($object, 'toString') ? $object->toString : 'naked entry '.stringify($object);
        warn "Created a new $found_display\n";
    }

    return ($object, $newly_made);
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


sub apply_tweaks {
    my $self    = shift @_;
    my $tweaks  = shift @_;

    foreach my $tweak (@$tweaks) {
        print "Tweak request: ".stringify($tweak)."\n";

        if($tweak=~/^global\.param\[(\w+)\]=(.+)$/) {
            my ($param_name, $new_value_str) = ($1, $2);

            print "\tRequest: $tweak :: global variable $param_name := $new_value_str\n";

            my $new_value = destringify( $new_value_str );

            if(my $hash_pair = $self->collection_of( 'PipelineWideParameters' )->find_one_by('param_name', $1)) {
                print "\tFound the global var $param_name, its current value is '$hash_pair->{param_value}'\n";

                $hash_pair->{'param_value'} = stringify($new_value);

                print "\tSet the new value to $new_value_str\n";
            } else {
                print "\tCould not find the global var $param_name, creating it\n";

                $self->add_new_or_update( 'PipelineWideParameters',
                    'param_name'    => $param_name,
                    'param_value'   => stringify($new_value),
                );
            }

        } elsif($tweak=~/^analysis\[([^\]]+)\]\.(?:param\[(\w+)\]|(\w+))=(.+)$/) {
            my ($analyses_pattern, $param_name, $attrib_name, $new_value_str) = ($1, $2, $3, $4);
            my $analyses = $self->collection_of( 'Analysis' )->find_all_by_pattern( $analyses_pattern );

            my $new_value = destringify( $new_value_str );

            if($param_name) {
                $attrib_name = 'parameters';
                print "\tRequest: $tweak :: analysis($analyses_pattern) variable $param_name := $new_value_str\n";
            } else {
                print "\tRequest: $tweak :: analysis($analyses_pattern) attribute $attrib_name := $new_value_str\n";
            }

            print "Found ".scalar(@$analyses)." analyses matching the pattern '$analyses_pattern'\n";
            foreach my $analysis (@$analyses) {

                if( $attrib_name eq 'flow_into' ) {
                    Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($self, $analysis, $new_value );

                } else {

                    my $old_value   = $analysis->$attrib_name();

                    print "Analysis '".$analysis->logic_name."' :\n";

                    if($param_name) {
                        my $param_hash  = destringify( $old_value );
                        $old_value      = $param_hash->{ $param_name };

                        print "\t the old '$param_name' var is ".(defined($old_value) ? "'$old_value'" : 'undef')."\n";

                        $param_hash->{ $param_name } = $new_value;
                        $analysis->$attrib_name( stringify($param_hash) );

                        print "\t the new '$param_name' var is $new_value_str\n";

                    } elsif( $attrib_name eq 'resource_class' ) {
                        print "\t the old '$attrib_name' attribute is ".(defined($old_value) ? "'".$old_value->name."'" : 'undef')."\n";

                        if(my $resource_class = $self->collection_of( 'ResourceClass' )->find_one_by( 'name', $new_value )) {
                            print "\t found the RC object with name=$new_value_str, reassigning\n";

                            $analysis->$attrib_name( $resource_class );
                        } else {
                            my ($resource_class) = $self->add_new_or_update( 'ResourceClass',   # NB: add_new_or_update returns a list
                                'name'  => $new_value,
                            );
                            print "\t created a new RC object with name=$new_value_str, reassigning\n";

                            $analysis->$attrib_name( $resource_class );
                        }

                    } else {
                        print "\t the old '$attrib_name' attribute is ".(defined($old_value) ? "'$old_value'" : 'undef')."\n";

                        $analysis->$attrib_name( $new_value );

                        print "\t the new '$attrib_name' attribute is '$new_value'\n";
                    }
                }
            }

        } elsif($tweak=~/^resource_class\[([^\]]+)\]\.(\w+)=(.+)$/) {
            my ($rc_pattern, $meadow_type, $new_value_str) = ($1, $2, $3);
            print "\tRequest: $tweak :: resource_class($rc_pattern) attribute $meadow_type := $new_value_str\n";

            my $new_value = destringify( $new_value_str );

            my ($new_submission_cmd_args, $new_worker_cmd_args) = (ref($new_value) eq 'ARRAY') ? @$new_value : ($new_value, '');

            my $resource_classes = $self->collection_of( 'ResourceClass' )->find_all_by_pattern( $rc_pattern );
            print "Found ".scalar(@$resource_classes)." resource_classes matching the pattern '$rc_pattern'\n";

            foreach my $rc (@$resource_classes) {
                print "ResourceClass '".$rc->name."' :\n";

                if(my $rd = $self->collection_of( 'ResourceDescription' )->find_one_by('resource_class', $rc, 'meadow_type', $meadow_type)) {
                    my ($submission_cmd_args, $worker_cmd_args) = ($rd->submission_cmd_args, $rd->worker_cmd_args);
                    print "\t description for meadow '$meadow_type' found: submission_cmd_args='$submission_cmd_args', worker_cmd_args='$worker_cmd_args'\n";

                    $rd->submission_cmd_args(   $new_submission_cmd_args );
                    $rd->worker_cmd_args(       $new_worker_cmd_args     );
                } else {
                    print "\t description for meadow '$meadow_type' not found, creating it\n";

                    my ($rd) = $self->add_new_or_update( 'ResourceDescription',   # NB: add_new_or_update returns a list
                        'resource_class'        => $rc,
                        'meadow_type'           => $meadow_type,
                        'submission_cmd_args'   => $new_submission_cmd_args,
                        'worker_cmd_args'       => $new_worker_cmd_args,
                    );
                }
            }

        } else {
            print "Could not parse '$tweak'\n";
        }
    }
}

1;
