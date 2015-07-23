package Bio::EnsEMBL::Hive::HivePipeline;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::Utils::Collection;


sub hive_dba {      # The adaptor for HivePipeline objects
    my $self = shift @_;

    if(@_) {
        $self->{'_hive_dba'} = shift @_;
    }
    return $self->{'_hive_dba'};
}


sub collection_of {
    my $self = shift @_;
    my $type = shift @_;

    my $class = 'Bio::EnsEMBL::Hive::'.$type;

    return $class->collection( @_ );    # temporary re-routing
}


sub new {       # construct an attached or a detached Pipeline object
    my $class = shift @_;

    my $self = bless {}, $class;

    my %dba_flags = @_;

    if(%dba_flags) {
        my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( %dba_flags );
        $self->hive_dba( $hive_dba );

        $self->load_collections();  # ToDo: should become lazy when $class->collection() is no longer used and $pipeline->collection_of() is used everywhere instead
    } else {
        $self->init_collections();
    }

    return $self;
}


sub init_collections {  # should not really belong to DBAdaptor, temporarily squatting here...
    my $self = shift @_;

    foreach my $AdaptorType ('MetaParameters', 'PipelineWideParameters', 'ResourceClass', 'ResourceDescription', 'Analysis', 'AnalysisStats', 'AnalysisCtrlRule', 'DataflowRule') {
        $self->collection_of( $AdaptorType, Bio::EnsEMBL::Hive::Utils::Collection->new() );
    }
}


sub load_collections {
    my $self = shift @_;

    my $hive_dba = $self->hive_dba();

    foreach my $AdaptorType ('MetaParameters', 'PipelineWideParameters', 'ResourceClass', 'ResourceDescription', 'Analysis', 'AnalysisStats', 'AnalysisCtrlRule', 'DataflowRule') {
        my $adaptor = $hive_dba->get_adaptor( $AdaptorType );
        $self->collection_of( $AdaptorType, Bio::EnsEMBL::Hive::Utils::Collection->new( $adaptor->fetch_all ) );
    }
}


sub save_collections {
    my $self = shift @_;

    my $hive_dba = $self->hive_dba();

    foreach my $AdaptorType ('MetaParameters', 'PipelineWideParameters', 'ResourceClass', 'ResourceDescription', 'Analysis', 'AnalysisStats', 'AnalysisCtrlRule', 'DataflowRule') {
        my $adaptor = $hive_dba->get_adaptor( $AdaptorType );
        my $class = 'Bio::EnsEMBL::Hive::'.$AdaptorType;
        foreach my $storable_object ( $self->collection_of( $AdaptorType )->list ) {
            $adaptor->store_or_update_one( $storable_object, $class->unikey() );
#            warn "Stored/updated ".$storable_object->toString()."\n";
        }
    }

    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
    foreach my $analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
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

        if( $object = $class->collection()->find_one_by( %unikey_pairs ) ) {
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

        my $found_display = UNIVERSAL::can($object, 'toString') ? $object->toString : 'naked entry '.stringify($object);
        warn "Created a new $found_display\n";

        $class->collection()->add( $object );
    }

    return $object;
}


1;
