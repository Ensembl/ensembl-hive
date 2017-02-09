#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('destringify');
use Bio::EnsEMBL::Hive::Utils::GraphViz;


my $self = {};

main();


sub main {

    my $pipeline;

    GetOptions(
            # connection parameters
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc=i'             => \$self->{'nosqlvc'},     # using "=i" instead of "!" for consistency with scripts where it is a propagated option

        'o|out|output=s'        => \$self->{'output'},
        'dot_input=s'           => \$self->{'dot_input'},   # filename to store the intermediate dot input (valuable for debugging)

        'h|help'                => \$self->{'help'},
    );

    if($self->{'url'} or $self->{'reg_alias'}) {
        $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

    } else {
        die "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
    }

    if($self->{'output'}) {

        if(!$self->{'format'}) {
            if($self->{'output'}=~/\.(\w+)$/) {
                $self->{'format'} = $1;
            } else {
                die "Format was not set and could not guess from ".$self->{'output'}.". Please use either way to select it.\n";
            }
        }

        $self->{'graph'} = Bio::EnsEMBL::Hive::Utils::GraphViz->new(
                    'name'          => 'JobDependencyGraph',
                    'concentrate'   => 'true',
                    'pad'           => 1,
        );

        my $job_adaptor = $pipeline->hive_dba->get_AnalysisJobAdaptor;

        $self->{'graph'}->cluster_2_nodes( {} );
        $self->{'graph'}->main_pipeline_name( $pipeline->hive_pipeline_name );
        $self->{'graph'}->other_pipeline_bgcolour( [ 'pastel19', 3 ] );
        $self->{'graph'}->display_cluster_names( 1 );

        foreach my $seed_job ( @{$job_adaptor->fetch_all_by_analysis_id( 1 ) } ) {
            my $job_node_name   = add_family_tree( $seed_job );
        }

            ## If you need to take a look at the intermediate dot file:
        if( $self->{'dot_input'} ) {
            $self->{'graph'}->dot_input_filename( $self->{'dot_input'} );
        }

        my $call = 'as_'.$self->{'format'};

        $self->{'graph'}->$call($self->{'output'});

    } else {
        die "\nERROR : -output filename has to be defined\n\n";
    }

}


my %job_node_hash = ();

sub add_job_node {
    my $job = shift @_;

    my $job_id          = $job->dbID;
    my $job_node_name   = 'job_'.$job_id;

    unless($job_node_hash{$job_node_name}++) {
        my $job_shape           = 'record';
        my $job_status_colour   = {'DONE' => 'DeepSkyBlue', 'READY' => 'green', 'SEMAPHORED' => 'grey', 'FAILED' => 'red'}->{$job->status} // 'blue';
        my $job_id              = $job->dbID;
        my $job_params          = destringify($job->input_id);

        my $job_label           = qq{<<table border="0" cellborder="0" cellspacing="0" cellpadding="1">}
                                 .qq{<tr><td><u><i>job_id:</i></u></td><td><i>$job_id</i></td></tr>};

        if(my $param_id_stack = $job->param_id_stack) {
            $job_label  .=  qq{<tr><td><u><i>params from:</i></u></td><td><i>$param_id_stack</i></td></tr>};
        }

        foreach my $param_key (sort keys %$job_params) {
            my $param_value = $job_params->{$param_key};
            $job_label  .= "<tr><td>$param_key:</td><td> $param_value</td></tr>";
        }

        my $accu_adaptor    = $job->adaptor->db->get_AccumulatorAdaptor;
        my $accu            = $accu_adaptor->fetch_structures_for_job_ids( $job_id )->{ $job_id };

        foreach my $accu_name (sort keys %$accu) {
            $job_label  .=  qq{<tr><td><u><i>accumulated:</i></u></td><td><i>$accu_name</i></td></tr>};
        }

        $job_label  .= "</table>>";


        $self->{'graph'}->add_node( $job_node_name,
            shape       => $job_shape,
            style       => 'filled',
            fillcolor   => $job_status_colour,
            label       => $job_label,
        );

            # adding the job to the corresponding analysis' cluster:
        push @{$self->{'graph'}->cluster_2_nodes->{ $job->analysis->logic_name }}, $job_node_name;
    }

    return $job_node_name;
}


my %semaphore_node_hash = ();

sub add_semaphore_node {
    my $semaphore = shift @_;

    my $semaphore_node_name         = 'semaphore_'.$semaphore->dbID;
    my $semaphore_blockers          = $semaphore->local_jobs_counter + $semaphore->remote_jobs_counter;
    my $semaphore_is_blocked        = $semaphore_blockers > 0;

    my ($semaphore_colour, $semaphore_shape, $dependent_blocking_arrow_colour, $dependent_blocking_arrow_shape ) = $semaphore_is_blocked
        ? ('red', 'triangle', 'red', 'tee')
        : ('darkgreen', 'invtriangle', 'darkgreen', 'none');

    my $semaphore_label = $semaphore_is_blocked ? 'blockers: '.$semaphore_blockers : 'open';

    unless($semaphore_node_hash{$semaphore_node_name}++) {
        $self->{'graph'}->add_node( $semaphore_node_name,
            shape       => $semaphore_shape,
            style       => 'filled',
            fillcolor   => $semaphore_colour,
            label       => $semaphore_label,
        );
        
        if(my $dependent_job = $semaphore->dependent_job) {
            my $dependent_job_node_name = add_job_node( $dependent_job );

            $self->{'graph'}->add_edge( $semaphore_node_name => $dependent_job_node_name,
                color       => $dependent_blocking_arrow_colour,
                style       => 'dashed',
                arrowhead   => $dependent_blocking_arrow_shape,
            );

                # adding the semaphore node to the dependent job's cluster:
            push @{$self->{'graph'}->cluster_2_nodes->{ $dependent_job->analysis->logic_name }}, $semaphore_node_name;
        } else {
            warn "Remote semaphores not yet supported";
        }
    }

    return $semaphore_node_name;
}


sub add_family_tree {
    my $parent_job = shift @_;
    
    my $parent_node_name = add_job_node( $parent_job );

    my $children = $parent_job->adaptor->fetch_all_by_prev_job_id( $parent_job->dbID );
    foreach my $child_job ( @$children ) {
        my $child_node_name = add_family_tree( $child_job );

        $self->{'graph'}->add_edge( $parent_node_name => $child_node_name,
            color   => 'blue',
        );
    }

    if(my $controlled_semaphore = $parent_job->controlled_semaphore) {
        my $semaphore_node_name = add_semaphore_node( $controlled_semaphore );

        my $parent_status               = $parent_job->status;
        my $parent_is_blocking          = ($parent_status eq 'DONE' or $parent_status eq 'PASSED_ON') ? 0 : 1;
        my $parent_controlling_colour   = $parent_is_blocking ? 'red' : 'darkgreen';
        my $blocking_arrow              = $parent_is_blocking ? 'tee' : 'none';

        $self->{'graph'}->add_edge( $parent_node_name => $semaphore_node_name,
            color       => $parent_controlling_colour,
            style       => 'dashed',
            arrowhead   => $blocking_arrow,
        );
    }

    return $parent_node_name;
}

