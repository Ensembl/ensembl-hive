=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::EnsEMBL::Hive::HivePipeline;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::TheApiary;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify', 'throw');
use Bio::EnsEMBL::Hive::Utils::Collection;
use Bio::EnsEMBL::Hive::Utils::PCL;
use Bio::EnsEMBL::Hive::Utils::URL;

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


sub unambig_key {   # based on DBC's URL if present, otherwise on pipeline_name
    my $self = shift @_;

    if(my $dbc = $self->hive_dba && $self->hive_dba->dbc) {
        return Bio::EnsEMBL::Hive::Utils::URL::hash_to_unambig_url( $dbc->to_url_hash );
    } else {
        return 'unstored:'.$self->hive_pipeline_name;
    }
}


sub collection_of {
    my $self = shift @_;
    my $type = shift @_;

    if (@_) {
        $self->{'_cache_by_class'}->{$type} = shift @_;
    } elsif (not $self->{'_cache_by_class'}->{$type}) {

        if( (my $hive_dba = $self->hive_dba) and ($type ne 'NakedTable') and ($type ne 'Accumulator') and ($type ne 'Job') and ($type ne 'AnalysisJob')) {
            my $adaptor = $hive_dba->get_adaptor( $type );
            my $all_objects = $adaptor->fetch_all();
            if(@$all_objects and UNIVERSAL::can($all_objects->[0], 'hive_pipeline') ) {
                $_->hive_pipeline($self) for @$all_objects;
            }
            $self->{'_cache_by_class'}->{$type} = Bio::EnsEMBL::Hive::Utils::Collection->new( $all_objects );
#            warn "initialized collection_of($type) by loading all ".scalar(@$all_objects)."\n";
        } else {
            $self->{'_cache_by_class'}->{$type} = Bio::EnsEMBL::Hive::Utils::Collection->new();
#            warn "initialized collection_of($type) as an empty one\n";
        }
    }

    return $self->{'_cache_by_class'}->{$type};
}


sub find_by_query {
    my $self            = shift @_;
    my $query_params    = shift @_;
    my $no_die          = shift @_;

    if(my $object_type = delete $query_params->{'object_type'}) {
        my $object;

        if($object_type eq 'Accumulator' or $object_type eq 'NakedTable') {

            unless($object = $self->collection_of($object_type)->find_one_by( %$query_params )) {

                my @specific_adaptor_params = ($object_type eq 'NakedTable')
                    ? ('table_name' => $query_params->{'table_name'},
                        $query_params->{'insertion_method'}
                            ? ('insertion_method' => $query_params->{'insertion_method'})
                            : ()
                      )
                    : ();
                ($object) = $self->add_new_or_update( $object_type, # NB: add_new_or_update returns a list
                    %$query_params,
                    $self->hive_dba ? ('adaptor' => $self->hive_dba->get_adaptor($object_type, @specific_adaptor_params)) : (),
                );
            }
        } elsif($object_type eq 'AnalysisJob' or $object_type eq 'Semaphore') {
            my $id_name = { 'AnalysisJob' => 'job_id', 'Semaphore' => 'semaphore_id' }->{$object_type};
            my $dbID    = $query_params->{$id_name};
            my $coll    = $self->collection_of($object_type);
            unless($object = $coll->find_one_by( 'dbID' => $dbID )) {

                my $adaptor = $self->hive_dba->get_adaptor( $object_type );
                if( $object = $adaptor->fetch_by_dbID( $dbID ) ) {
                    $coll->add( $object );
                }
            }
        } else {
            $object = $self->collection_of($object_type)->find_one_by( %$query_params );
        }

        return $object if $object || $no_die;
        throw("Could not find an '$object_type' object from query ".stringify($query_params)." in ".$self->display_name);

    } else {
        throw("Could not find or guess the object_type from the query ".stringify($query_params)." , so could not find the object");
    }
}

sub test_connections {
    my $self = shift;

    my @warnings;

    foreach my $dft ($self->collection_of('DataflowTarget')->list) {
        my $analysis_url = $dft->to_analysis_url;
        if ($analysis_url =~ m{^\w+$}) {
            my $heir_analysis = $self->collection_of('Analysis')->find_one_by('logic_name', $analysis_url)
                or push @warnings, "Could not find a local analysis named '$analysis_url' (dataflow from analysis '".($dft->source_dataflow_rule->from_analysis->logic_name)."')";
        }
    }

    foreach my $cf ($self->collection_of('AnalysisCtrlRule')->list) {
        my $analysis_url = $cf->condition_analysis_url;
        if ($analysis_url =~ m{^\w+$}) {
            my $heir_analysis = $self->collection_of('Analysis')->find_one_by('logic_name', $analysis_url)
                or push @warnings, "Could not find a local analysis named '$analysis_url' (control-flow for analysis '".($cf->ctrled_analysis->logic_name)."')";
        }

    }

    if (@warnings) {
        push @warnings, '', 'Please fix these before running the pipeline';
        warn join("\n", '', '# ' . '-' x 26 . '[WARNINGS]' . '-' x 26, '', @warnings), "\n";
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

    $self->{TWEAK_ERROR_MSG} = {
        PARSE_ERROR  => "Tweak cannot be parsed",
        ACTION_ERROR => "Action is not supported",
        FIELD_ERROR  => "Field not recognized",
        VALUE_ERROR  => "Invalid value",
    };

    $self->{TWEAK_ACTION} = {
        '=' => "SET",
        '+' => "SET",
        '?' => "SHOW",
        '#' => "DELETE",
    };

    $self->{TWEAK_OBJECT_TYPE} = {
        PIPELINE => "Pipeline",
        ANALYSIS => "Analysis",
        RESOURCE_CLASS => "Resource class",
    };

    Bio::EnsEMBL::Hive::TheApiary->pipelines_collection->add( $self );

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

    my @adaptor_types = ('MetaParameters', 'PipelineWideParameters', 'ResourceClass', 'ResourceDescription', 'Analysis', 'AnalysisStats', 'AnalysisCtrlRule', 'DataflowRule', 'DataflowTarget');

    foreach my $AdaptorType (reverse @adaptor_types) {
        my $adaptor = $hive_dba->get_adaptor( $AdaptorType );
        my $coll    = $self->collection_of( $AdaptorType );
        if( my $dark_collection = $coll->dark_collection) {
            foreach my $obj_to_be_deleted ( $coll->dark_collection->list ) {
                $adaptor->remove( $obj_to_be_deleted );
#                warn "Deleted ".(UNIVERSAL::can($obj_to_be_deleted, 'toString') ? $obj_to_be_deleted->toString : stringify($obj_to_be_deleted))."\n";
            }
            $coll->dark_collection( undef );
        }
    }

    foreach my $AdaptorType (@adaptor_types) {
        my $adaptor = $hive_dba->get_adaptor( $AdaptorType );
        my $class   = 'Bio::EnsEMBL::Hive::'.$AdaptorType;
        my $coll    = $self->collection_of( $AdaptorType );
        foreach my $storable_object ( $coll->list ) {
            $adaptor->store_or_update_one( $storable_object, $class->unikey() );
#            warn "Stored/updated ".$storable_object->toString()."\n";
        }
    }

    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
    foreach my $analysis ( $self->collection_of( 'Analysis' )->list ) {
        if(my $our_jobs = $analysis->jobs_collection ) {
            $job_adaptor->store( $our_jobs );
#            foreach my $job (@$our_jobs) {
#                warn "Stored ".$job->toString()."\n";
#            }
        }
    }
}


sub add_new_or_update {
    my $self = shift @_;
    my $type = shift @_;

    # $verbose is an extra optional argument that sits between the type and the object hash
    my $verbose = scalar(@_) % 2 ? shift : 0;

    my $class   = 'Bio::EnsEMBL::Hive::'.$type;
    my $coll    = $self->collection_of( $type );

    my $object;
    my $newly_made = 0;

    if( my $unikey_keys = $class->unikey() ) {
        my %other_pairs = @_;
        my %unikey_pairs;
        @unikey_pairs{ @$unikey_keys} = delete @other_pairs{ @$unikey_keys };

        if( $object = $coll->find_one_by( %unikey_pairs ) ) {
            my $found_display = $verbose && (UNIVERSAL::can($object, 'toString') ? $object->toString : stringify($object));
            if(keys %other_pairs) {
                print "Updating $found_display with (".stringify(\%other_pairs).")\n" if $verbose;
                if( ref($object) eq 'HASH' ) {
                    @$object{ keys %other_pairs } = values %other_pairs;
                } else {
                    while( my ($key, $value) = each %other_pairs ) {
                        $object->$key($value);
                    }
                }
            } else {
                print "Found a matching $found_display\n" if $verbose;
            }
        } elsif( my $dark_coll = $coll->dark_collection) {
            if( my $shadow_object = $dark_coll->find_one_by( %unikey_pairs ) ) {
                $dark_coll->forget( $shadow_object );
                my $found_display = $verbose && (UNIVERSAL::can($shadow_object, 'toString') ? $shadow_object->toString : stringify($shadow_object));
                print "Undeleting $found_display\n" if $verbose;
            }
        }
    } else {
        warn "$class doesn't redefine unikey(), so unique objects cannot be identified";
    }

    unless( $object ) {
        $object = $class->can('new') ? $class->new( @_ ) : { @_ };
        $newly_made = 1;

        $coll->add( $object );

        $object->hive_pipeline($self) if UNIVERSAL::can($object, 'hive_pipeline');

        my $found_display = $verbose && (UNIVERSAL::can($object, 'toString') ? $object->toString : 'naked entry '.stringify($object));
        print "Created a new $found_display\n" if $verbose;
    }

    return ($object, $newly_made);
}


=head2 get_source_analyses

    Description: returns a listref of analyses that do not have local inflow ("source analyses")

=cut

sub get_source_analyses {
    my $self = shift @_;

    my %analyses_to_discard = map {scalar($_->to_analysis) => 1} $self->collection_of( 'DataflowTarget' )->list;

    return [grep {!$analyses_to_discard{"$_"}} $self->collection_of( 'Analysis' )->list];
}


=head2 _meta_value_by_key

    Description: getter/setter for a particular meta_value from 'MetaParameters' collection given meta_key

=cut

sub _meta_value_by_key {
    my $self    = shift @_;
    my $meta_key= shift @_;

    my $hash = $self->collection_of( 'MetaParameters' )->find_one_by( 'meta_key', $meta_key );

    if(@_) {
        my $new_value = shift @_;

        if($hash) {
            $hash->{'meta_value'} = $new_value;
        } else {
            ($hash) = $self->add_new_or_update( 'MetaParameters',
                'meta_key'      => $meta_key,
                'meta_value'    => $new_value,
            );
        }
    }

    return $hash && $hash->{'meta_value'};
}


=head2 hive_use_param_stack

    Description: getter/setter via MetaParameters. Defines which one of two modes of parameter propagation is used in this pipeline

=cut

sub hive_use_param_stack {
    my $self = shift @_;

    return $self->_meta_value_by_key('hive_use_param_stack', @_) // 0;
}


=head2 hive_pipeline_name

    Description: getter/setter via MetaParameters. Defines the symbolic name of the pipeline.

=cut

sub hive_pipeline_name {
    my $self = shift @_;

    return $self->_meta_value_by_key('hive_pipeline_name', @_) // '';
}


=head2 hive_auto_rebalance_semaphores

    Description: getter/setter via MetaParameters. Defines whether beekeeper should attempt to rebalance semaphores on each iteration.

=cut

sub hive_auto_rebalance_semaphores {
    my $self = shift @_;

    return $self->_meta_value_by_key('hive_auto_rebalance_semaphores', @_) // '0';
}


=head2 hive_use_triggers

    Description: getter via MetaParameters. Defines whether SQL triggers are used to automatically update AnalysisStats counters

=cut

sub hive_use_triggers {
    my $self = shift @_;

    if(@_) {
        throw('HivePipeline::hive_use_triggers is not settable, it is only a getter');
    }

    return $self->_meta_value_by_key('hive_use_triggers') // '0';
}

=head2 hive_default_max_retry_count

    Description: getter/setter via MetaParameters. Defines the default value for analysis_base.max_retry_count

=cut

sub hive_default_max_retry_count {
    my $self = shift @_;

    return $self->_meta_value_by_key('hive_default_max_retry_count', @_) // 0;
}


=head2 list_all_hive_tables

    Description: getter via MetaParameters. Lists the (MySQL) table names used by the HivePipeline

=cut

sub list_all_hive_tables {
    my $self = shift @_;

    if(@_) {
        throw('HivePipeline::list_all_hive_tables is not settable, it is only a getter');
    }

    return [ split /,/, ($self->_meta_value_by_key('hive_all_base_tables') // '') ];
}


=head2 list_all_hive_views

    Description: getter via MetaParameters. Lists the (MySQL) view names used by the HivePipeline

=cut

sub list_all_hive_views {
    my $self = shift @_;

    if(@_) {
        throw('HivePipeline::list_all_hive_views is not settable, it is only a getter');
    }

    return [ split /,/, ($self->_meta_value_by_key('hive_all_views') // '') ];
}


=head2 hive_sql_schema_version

    Description: getter via MetaParameters. Defines the Hive SQL schema version of the database if it has been stored

=cut

sub hive_sql_schema_version {
    my $self = shift @_;

    if(@_) {
        throw('HivePipeline::hive_sql_schema_version is not settable, it is only a getter');
    }

    return $self->_meta_value_by_key('hive_sql_schema_version') // 'N/A';
}


=head2 params_as_hash

    Description: returns the destringified contents of the 'PipelineWideParameters' collection as a hash

=cut

sub params_as_hash {
    my $self = shift @_;

    my $collection = $self->collection_of( 'PipelineWideParameters' );
    return { map { $_->{'param_name'} => destringify($_->{'param_value'}) } $collection->list() };
}


=head2 get_cached_hive_current_load

    Description: Proxy for RoleAdaptor::get_hive_current_load() that caches the last value.

=cut

sub get_cached_hive_current_load {
    my $self = shift @_;

    if (not exists $self->{'_cached_hive_load'}) {
        if ($self->hive_dba) {
            $self->{'_cached_hive_load'} = $self->hive_dba->get_RoleAdaptor->get_hive_current_load();
        } else {
            $self->{'_cached_hive_load'} = 0;
        }
    }
    return $self->{'_cached_hive_load'};
}


=head2 invalidate_hive_current_load

    Description: Method that forces the next get_cached_hive_current_load() call to fetch a fresh value from the database

=cut

sub invalidate_hive_current_load {
    my $self = shift @_;

    delete $self->{'_cached_hive_load'};
}


=head2 print_diagram

    Description: prints a "Unicode art" textual representation of the pipeline's flow diagram

=cut

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


=head2 apply_tweaks

    Description: changes attributes of Analyses|ResourceClasses|ResourceDescriptions or values of pipeline/analysis parameters

=cut

sub apply_tweaks {
    my $self    = shift @_;
    my $tweaks  = shift @_;
    my @response;
    my $responseStructure;
    my $need_write = 0;
    $responseStructure->{Tweaks} = [];
    foreach my $tweak (@$tweaks) {
        push @response, "\nTweak.Request\t$tweak\n";

        if($tweak=~/^pipeline\.param\[(\w+)\](\?|#|=(.+))$/) {
            my ($param_name, $operator, $new_value_str) = ($1, $2, $3);
            my $tweakStructure;
            $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};
            $tweakStructure->{Object}->{Type} =  $self->{TWEAK_OBJECT_TYPE}->{PIPELINE};
            $tweakStructure->{Object}->{Id} = undef;
            $tweakStructure->{Object}->{Name} = undef;
            $tweakStructure->{Return}->{Field} = $param_name;
            my $pwp_collection  = $self->collection_of( 'PipelineWideParameters' );
            my $hash_pair       = $pwp_collection->find_one_by('param_name', $param_name);
            if($operator eq '?') {
                my $value = $hash_pair ? $hash_pair->{'param_value'} : undef;
                $tweakStructure->{Return}->{OldValue} = $value;
                $tweakStructure->{Return}->{NewValue} = $value;
                push @response, "Tweak.Show    \tpipeline.param[$param_name] ::\t"
	               . ($hash_pair ? $hash_pair->{'param_value'} : '(missing_value)') . "\n";
            } elsif($operator eq '#') {
                $tweakStructure->{Return}->{OldValue} = $hash_pair ? $hash_pair->{'param_value'} : undef;
                $tweakStructure->{Return}->{NewValue} = undef;
                if ($hash_pair) {
                    $need_write = 1;
                    $pwp_collection->forget_and_mark_for_deletion( $hash_pair );
                    push @response, "Tweak.Deleting\tpipeline.param[$param_name] ::\t".stringify($hash_pair->{'param_value'})." --> (missing value)\n";
                } else {
                    push @response, "Tweak.Deleting\tpipeline.param[$param_name] skipped (does not exist)\n";
                }
            } else {
                $need_write = 1;
                my $new_value = destringify( $new_value_str );
                $new_value_str = stringify($new_value);
                $tweakStructure->{Return}->{NewValue} = $new_value_str;
                if($hash_pair) {
                    $tweakStructure->{Return}->{OldValue} = $hash_pair->{'param_value'};
                    push @response, "Tweak.Changing\tpipeline.param[$param_name] ::\t$hash_pair->{'param_value'} --> $new_value_str\n";

                    $hash_pair->{'param_value'} = $new_value_str;
                } else {
                    $tweakStructure->{Return}->{OldValue} = undef;
                    push @response, "Tweak.Adding  \tpipeline.param[$param_name] ::\t(missing value) --> $new_value_str\n";
                    $self->add_new_or_update( 'PipelineWideParameters',
                        'param_name'    => $param_name,
                        'param_value'   => $new_value_str,
                    );
                }
            }
          push @{$responseStructure->{Tweaks}}, $tweakStructure;
        } elsif($tweak=~/^pipeline\.(\w+)(\?|=(.+))$/) {
            my $tweakStructure;
            my ($attrib_name, $operator, $new_value_str) = ($1, $2, $3);
            $tweakStructure->{Object}->{Type} = $self->{TWEAK_OBJECT_TYPE}->{PIPELINE};
            $tweakStructure->{Object}->{Id} = undef;
            $tweakStructure->{Object}->{Name} = undef;
            $tweakStructure->{Return}->{Field} = $attrib_name;
            $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};

            if($self->can($attrib_name)) {
                my $old_value = stringify( $self->$attrib_name() );

                if($operator eq '?') {
                    $tweakStructure->{Return}->{OldValue} = $old_value;
                    $tweakStructure->{Return}->{NewValue} = $old_value;
                    push @response, "Tweak.Show    \tpipeline.$attrib_name ::\t$old_value\n";
                } else {
                    $tweakStructure->{Return}->{OldValue} = $old_value;
                    $tweakStructure->{Return}->{NewValue} = $new_value_str;
                    push @response, "Tweak.Changing\tpipeline.$attrib_name ::\t$old_value --> $new_value_str\n";

                    $self->$attrib_name( $new_value_str );
                    $need_write = 1;
                }

            } else {
                $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{FIELD_ERROR};
                push @response, "Tweak.Error   \tCould not find the pipeline-wide '$attrib_name' method\n";
            }
            push @{$responseStructure->{Tweaks}}, $tweakStructure;
        } elsif($tweak=~/^analysis\[([^\]]+)\]\.param\[(\w+)\](\?|#|=(.+))$/) {
            my ($analyses_pattern, $param_name, $operator, $new_value_str) = ($1, $2, $3, $4);
            my $analyses = $self->collection_of( 'Analysis' )->find_all_by_pattern( $analyses_pattern );
            push @response, "Tweak.Found   \t".scalar(@$analyses)." analyses matching the pattern '$analyses_pattern'\n";

            my $new_value = destringify( $new_value_str );
            $new_value_str = stringify( $new_value );

            foreach my $analysis (@$analyses) {
                my $tweakStructure;
                $tweakStructure->{Object}->{Type} = $self->{TWEAK_OBJECT_TYPE}->{ANALYSIS};
                $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};
                my $analysis_name = $analysis->logic_name;
                my $old_value = $analysis->parameters;

                $tweakStructure->{Object}->{Id} = $analysis->dbID + 0;
                $tweakStructure->{Object}->{Name} = $analysis_name;
                $tweakStructure->{Return}->{Field} = $param_name;
                my $param_hash  = destringify( $old_value );
                $tweakStructure->{Return}->{OldValue} =  exists($param_hash->{ $param_name }) ? stringify($param_hash->{ $param_name }) : undef;

                if($operator eq '?') {
                    $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue};
                    push @response, "Tweak.Show    \tanalysis[$analysis_name].param[$param_name] ::\t"
    	               . (exists($param_hash->{ $param_name }) ? stringify($param_hash->{ $param_name }) : '(missing value)')
	                   ."\n";
                } elsif($operator eq '#') {
                    $tweakStructure->{Return}->{NewValue} = undef;
                    push @response, "Tweak.Deleting\tanalysis[$analysis_name].param[$param_name] ::\t".stringify($param_hash->{ $param_name })." --> (missing value)\n";

                    delete $param_hash->{ $param_name };
                    $analysis->parameters( stringify($param_hash) );
                    $need_write = 1;
                } else {
                    $tweakStructure->{Return}->{NewValue} = $new_value_str;
                    if(exists($param_hash->{ $param_name })) {
                        push @response, "Tweak.Changing\tanalysis[$analysis_name].param[$param_name] ::\t".stringify($param_hash->{ $param_name })." --> $new_value_str\n";
                    } else {
                        push @response, "Tweak.Adding  \tanalysis[$analysis_name].param[$param_name] ::\t(missing value) --> $new_value_str\n";
                    }

                    $param_hash->{ $param_name } = $new_value;
                    $analysis->parameters( stringify($param_hash) );
                    $need_write = 1;
                }
                push @{$responseStructure->{Tweaks}}, $tweakStructure;
            }


        } elsif($tweak=~/^analysis\[([^\]]+)\]\.(wait_for|flow_into)(\?|#|\+?=(.+))$/) {

            my ($analyses_pattern, $attrib_name, $operation, $new_value_str) = ($1, $2, $3, $4);
            $operation=~/^(\?|#|\+?=)/;
            my $operator = $1;

            my $analyses = $self->collection_of( 'Analysis' )->find_all_by_pattern( $analyses_pattern );
            push @response, "Tweak.Found   \t".scalar(@$analyses)." analyses matching the pattern '$analyses_pattern'\n";

            my $new_value = destringify( $new_value_str );

            foreach my $analysis (@$analyses) {
                my $tweakStructure;
                $tweakStructure->{Object}->{Type} = $self->{TWEAK_OBJECT_TYPE}->{ANALYSIS};
                $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};
                my $analysis_name = $analysis->logic_name;
                $tweakStructure->{Object}->{Id} = $analysis->dbID + 0;
                $tweakStructure->{Object}->{Name} = $analysis->logic_name;
                $tweakStructure->{Return}->{Field} = $attrib_name;
                if( $attrib_name eq 'wait_for' ) {
                    my $cr_collection   = $self->collection_of( 'AnalysisCtrlRule' );
                    my $acr_collection  = $analysis->control_rules_collection;
                    $tweakStructure->{Return}->{OldValue} = [map { $_->condition_analysis_url } @$acr_collection];
                    if($operator eq '?') {
                        $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue};
                        push @response, "Tweak.Show    \tanalysis[$analysis_name].wait_for ::\t[".join(', ', map { $_->condition_analysis_url } @$acr_collection )."]\n";
                    }

                    if($operator eq '#' or $operator eq '=') {     # delete the existing rules
                        $tweakStructure->{Return}->{NewValue} = undef;
                        foreach my $c_rule ( @$acr_collection ) {
                            $cr_collection->forget_and_mark_for_deletion( $c_rule );
                            $need_write = 1;

                            push @response, "Tweak.Deleting\t".$c_rule->toString." --> (missing value)\n";
                        }
                    }

                    if($operator eq '=' or $operator eq '+=') {     # create new rules
                        $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue} . $new_value;
                        Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($self, $analysis, $new_value);
                        $need_write = 1;
                    }

                } elsif( $attrib_name eq 'flow_into' ) {
                    $tweakStructure->{Warning} = "Value can't be displayed";
                    if($operator eq '?') {
                        # FIXME: should not recurse
                        #$analysis->print_diagram_node($self, '', {}); TODO: refactor with formatter.pm
                    }

                    if($operator eq '#' or $operator eq '=') {     # delete the existing rules
                        my $dfr_collection = $self->collection_of( 'DataflowRule' );
                        my $dft_collection = $self->collection_of( 'DataflowTarget' );

                        foreach my $group ( @{$analysis->get_grouped_dataflow_rules} ) {
                            my ($funnel_dfr, $fan_dfrs, $funnel_df_targets) = @$group;

                            foreach my $df_rule (@$fan_dfrs, $funnel_dfr) {

                                foreach my $df_target ( @{$df_rule->get_my_targets} ) {
                                    $dft_collection->forget_and_mark_for_deletion( $df_target );

                                    push @response, "Tweak.Deleting\t".$df_target->toString." --> (missing value)\n";
                                }
                                $dfr_collection->forget_and_mark_for_deletion( $df_rule );
                                $need_write = 1;

                                push @response, "Tweak.Deleting\t".$df_rule->toString." --> (missing value)\n";
                            }
                        }
                    }

                    if($operator eq '=' or $operator eq '+=') {     # create new rules
                        $need_write = 1;
                        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($self, $analysis, $new_value );
                    }
                }
                push @{$responseStructure->{Tweaks}}, $tweakStructure;
            }

        } elsif($tweak=~/^analysis\[([^\]]+)\]\.(\w+)(\?|#|=(.+))$/) {

            my ($analyses_pattern, $attrib_name, $operator, $new_value_str) = ($1, $2, $3, $4);

            my $analyses = $self->collection_of( 'Analysis' )->find_all_by_pattern( $analyses_pattern );
            push @response, "Tweak.Found   \t".scalar(@$analyses)." analyses matching the pattern '$analyses_pattern'\n";

            my $new_value = destringify( $new_value_str );

            foreach my $analysis (@$analyses) {

                my $analysis_name = $analysis->logic_name;
                my $tweakStructure;
                $tweakStructure->{Object}->{Type} = $self->{TWEAK_OBJECT_TYPE}->{ANALYSIS};
                $tweakStructure->{Object}->{Id} = $analysis->dbID + 0;
                $tweakStructure->{Object}->{Name} = $analysis_name;
                $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};
                $tweakStructure->{Return}->{Field} = $attrib_name;
                if( $attrib_name eq 'resource_class' ) {
                    $tweakStructure->{Return}->{OldValue} = $analysis->resource_class ? $analysis->resource_class->name : undef;

                    if($operator eq '?') {
                        $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue};
                        if(my $old_value = $analysis->resource_class) {
                            push @response, "Tweak.Show    \tanalysis[$analysis_name].resource_class ::\t".$old_value->name."\n";
                        } else {
                            push @response, "Tweak.Show    \tanalysis[$analysis_name].resource_class ::\t(missing value)\n";
                        }
                    } elsif($operator eq '#') {
                        $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{ACTION_ERROR};
                        push @response, "Tweak.Error   \tDeleting of ResourceClasses is not supported\n";
                    } else {
                        $tweakStructure->{Return}->{NewValue} = $new_value_str;
                        if(my $old_value = $analysis->resource_class) {
                            push @response, "Tweak.Changing\tanalysis[$analysis_name].resource_class ::\t".$old_value->name." --> $new_value_str\n";
                        } else {
                            push @response, "Tweak.Adding  \tanalysis[$analysis_name].resource_class ::\t(missing value) --> $new_value_str\n";    # do we ever NOT have resource_class set?
                        }

                        my $resource_class;
                        if($resource_class = $self->collection_of( 'ResourceClass' )->find_one_by( 'name', $new_value )) {
                            push @response, "Tweak.Found   \tresource_class[$new_value_str]\n";
                        } else {
                            push @response, "Tweak.Adding  \tresource_class[$new_value_str]\n";

                            ($resource_class) = $self->add_new_or_update( 'ResourceClass',   # NB: add_new_or_update returns a list
                                'name'  => $new_value,
                            );
                        }
                        $analysis->resource_class( $resource_class );
                        $need_write = 1;
                    }

                } elsif( $attrib_name eq 'is_excluded' ) {
                    my $analysis_stats = $analysis->stats();
                    $tweakStructure->{Return}->{OldValue} = $analysis_stats->is_excluded();
                    if($operator eq '?') {
                        $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue};
                        push @response, "Tweak.Show    \tanalysis[$analysis_name].is_excluded ::\t".$analysis_stats->is_excluded()."\n";
                    } elsif($operator eq '#') {
                        $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{ACTION_ERROR};
                        push @response, "Tweak.Error   \tDeleting of excluded status is not supported\n";
                    } else {
                        $tweakStructure->{Return}->{NewValue} = $new_value_str;
                        if(!($new_value =~ /^[01]$/)) {
                            $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{VALUE_ERROR};
                            push @response, "Tweak.Error    \tis_excluded can only be 0 (no) or 1 (yes)\n";
                        } elsif ($new_value == $analysis_stats->is_excluded()) {
                            push @response, "Tweak.Info    \tanalysis[$analysis_name].is_excluded is already $new_value, leaving as is\n";
                        } else {
                           push @response, "Tweak.Changing\tanalysis[$analysis_name].is_excluded ::\t" .
                               $analysis_stats->is_excluded() . " --> $new_value_str\n";
                           $analysis_stats->is_excluded($new_value);
                           $need_write = 1;
                        }
                    }
                } elsif($analysis->can($attrib_name)) {
                    my $old_value = stringify($analysis->$attrib_name());
                    $tweakStructure->{Return}->{OldValue} = $old_value;
                    if($operator eq '?') {
                        $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue};
                        push @response, "Tweak.Show    \tanalysis[$analysis_name].$attrib_name ::\t$old_value\n";
                    } elsif($operator eq '#') {
                        $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{ACTION_ERROR};
                        push @response, "Tweak.Error   \tDeleting of Analysis attributes is not supported\n";
                    } else {
                        $tweakStructure->{Return}->{NewValue} = stringify($new_value);
                        push @response, "Tweak.Changing\tanalysis[$analysis_name].$attrib_name ::\t$old_value --> ".stringify($new_value)."\n";
                        $analysis->$attrib_name( $new_value );
                        $need_write = 1;
                    }
                } else {
                    $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{FIELD_ERROR};
                    push @response, "Tweak.Error   \tAnalysis does not support '$attrib_name' attribute\n";
                }

                push @{$responseStructure->{Tweaks}}, $tweakStructure;
            }

        } elsif($tweak=~/^resource_class\[([^\]]+)\]\.(\w+)(\?|=(.+))$/) {
            my ($rc_pattern, $meadow_type, $operator, $new_value_str) = ($1, $2, $3, $4);

            my $resource_classes = $self->collection_of( 'ResourceClass' )->find_all_by_pattern( $rc_pattern );
            push @response, "Tweak.Found   \t".scalar(@$resource_classes)." resource_classes matching the pattern '$rc_pattern'\n";

            if($operator eq '?') {
                foreach my $rc (@$resource_classes) {
                    my $tweakStructure;
                    $tweakStructure->{Object}->{Type} = $self->{TWEAK_OBJECT_TYPE}->{RESOURCE_CLASS};
                    my $rc_name = $rc->name;
                    $tweakStructure->{Object}->{Id} = $rc->dbID + 0;
                    $tweakStructure->{Object}->{Name} = $rc_name;
                    $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};

                    if(my $rd = $self->collection_of( 'ResourceDescription' )->find_one_by('resource_class', $rc, 'meadow_type', $meadow_type)) {
                        my ($submission_cmd_args, $worker_cmd_args) = ($rd->submission_cmd_args, $rd->worker_cmd_args);
                        push @response, "Tweak.Show    \tresource_class[$rc_name].$meadow_type ::\t".stringify([$submission_cmd_args, $worker_cmd_args])."\n";
                        $tweakStructure->{Return}->{OldValue} = stringify([$submission_cmd_args, $worker_cmd_args]);
                    } else {
                        push @response, "Tweak.Show    \tresource_class[$rc_name].$meadow_type ::\t(missing values)\n";
                        $tweakStructure->{Return}->{OldValue} = undef;
                    }
                    $tweakStructure->{Return}->{Field} = $meadow_type;
                    $tweakStructure->{Return}->{NewValue} = $tweakStructure->{Return}->{OldValue};
                    push @{$responseStructure->{Tweaks}}, $tweakStructure;
                }

            } else {

                my $new_value = destringify( $new_value_str );
                my ($new_submission_cmd_args, $new_worker_cmd_args) = (ref($new_value) eq 'ARRAY') ? @$new_value : ($new_value, '');

                foreach my $rc (@$resource_classes) {
                    my $tweakStructure;
                    $tweakStructure->{Object}->{Type} = $self->{TWEAK_OBJECT_TYPE}->{RESOURCE_CLASS};
                    $tweakStructure->{Action} = $self->{TWEAK_ACTION}->{substr($operator, 0, 1)};
                    my $rc_name = $rc->name;
                    $tweakStructure->{Object}->{Id} = $rc->dbID + 0;
                    $tweakStructure->{Object}->{Name} = $rc_name;

                    if(my $rd = $self->collection_of( 'ResourceDescription' )->find_one_by('resource_class', $rc, 'meadow_type', $meadow_type)) {
                        my ($submission_cmd_args, $worker_cmd_args) = ($rd->submission_cmd_args, $rd->worker_cmd_args);
                        push @response, "Tweak.Changing\tresource_class[$rc_name].$meadow_type :: "
                                .stringify([$submission_cmd_args, $worker_cmd_args])." --> "
                                .stringify([$new_submission_cmd_args, $new_worker_cmd_args])."\n";

                        $rd->submission_cmd_args(   $new_submission_cmd_args );
                        $rd->worker_cmd_args(       $new_worker_cmd_args     );
                        $tweakStructure->{Return}->{OldValue} = stringify([$submission_cmd_args, $worker_cmd_args]);

                    } else {
                        push @response, "Tweak.Adding  \tresource_class[$rc_name].$meadow_type :: (missing values) --> "
                                .stringify([$new_submission_cmd_args, $new_worker_cmd_args])."\n";

                        my ($rd) = $self->add_new_or_update( 'ResourceDescription',   # NB: add_new_or_update returns a list
                            'resource_class'        => $rc,
                            'meadow_type'           => $meadow_type,
                            'submission_cmd_args'   => $new_submission_cmd_args,
                            'worker_cmd_args'       => $new_worker_cmd_args,
                        );
                        $tweakStructure->{Return}->{OldValue} = undef;
                    }
                    $tweakStructure->{Return}->{Field} = $meadow_type;
                    $tweakStructure->{Return}->{NewValue} = stringify([$new_submission_cmd_args, $new_worker_cmd_args]);
                    $need_write = 1;
                    push @{$responseStructure->{Tweaks}}, $tweakStructure;
                }
            }


        } else {
            my $tweakStructure;
            $tweakStructure->{Error} = $self->{TWEAK_ERROR_MSG}->{PARSE_ERROR};
            push @response, "Tweak.Error   \tFailed to parse the tweak\n";
            push @{$responseStructure->{Tweaks}}, $tweakStructure;
        }

    }
    return $need_write, \@response, $responseStructure;
}

1;
