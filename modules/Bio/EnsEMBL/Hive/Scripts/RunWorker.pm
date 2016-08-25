=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

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


package Bio::EnsEMBL::Hive::Scripts::RunWorker;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Utils::Stopwatch;

sub runWorker {
    my ($pipeline, $specialization_options, $life_options, $execution_options) = @_;

    my $worker_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    $worker_stopwatch->_unit(1); # lifespan_sec is in seconds
    $worker_stopwatch->restart();

    my $hive_dba = $pipeline->hive_dba;

    die "Hive's DBAdaptor is not a defined Bio::EnsEMBL::Hive::DBSQL::DBAdaptor\n" unless $hive_dba and $hive_dba->isa('Bio::EnsEMBL::Hive::DBSQL::DBAdaptor');

    $specialization_options ||= {};
    $life_options ||= {};
    $execution_options ||= {};

    my $queen = $hive_dba->get_Queen();
    die "No Queen, God Bless Her\n" unless $queen and $queen->isa('Bio::EnsEMBL::Hive::Queen');

    my ($meadow_type, $meadow_name, $process_id, $meadow_host, $meadow_user) = Bio::EnsEMBL::Hive::Valley->new()->whereami();
    die "Valley is not fully defined" unless ($meadow_type && $meadow_name && $process_id && $meadow_host && $meadow_user);

    if( $specialization_options->{'force_sync'} ) {       # sync the Hive in Test mode:
        my $list_of_analyses = $pipeline->collection_of('Analysis')->find_all_by_pattern( $specialization_options->{'analyses_pattern'} );

        $queen->synchronize_hive( $list_of_analyses );
    }

    # Create the worker
    my $worker = $queen->create_new_worker(
          # Worker identity:
             -meadow_type           => $meadow_type,
             -meadow_name           => $meadow_name,
             -process_id            => $process_id,
             -meadow_host           => $meadow_host,
             -meadow_user           => $meadow_user,
             -resource_class_id     => $specialization_options->{'resource_class_id'},
             -resource_class_name   => $specialization_options->{'resource_class_name'},
             -beekeeper_id          => $specialization_options->{'beekeeper_id'},

          # Worker control parameters:
             -job_limit             => $life_options->{'job_limit'},
             -life_span             => $life_options->{'life_span'},
             -no_cleanup            => $execution_options->{'no_cleanup'},
             -no_write              => $execution_options->{'no_write'},
             -worker_log_dir        => $execution_options->{'worker_log_dir'},
             -hive_log_dir          => $execution_options->{'hive_log_dir'},
             -retry_throwing_jobs   => $life_options->{'retry_throwing_jobs'},
             -can_respecialize      => $specialization_options->{'can_respecialize'},

          # Other parameters:
             -debug                 => $execution_options->{'debug'},
    );
    die "No worker !\n" unless $worker and $worker->isa('Bio::EnsEMBL::Hive::Worker');

    # Run the worker
    eval {
        $worker->run( {
             -analyses_pattern      => $specialization_options->{'analyses_pattern'},
             -job_id                => $specialization_options->{'job_id'},
             -force                 => $specialization_options->{'force'},
        } );
        cleanup_if_needed($worker);
        _update_resource_usage($worker, $worker_stopwatch);
        1;

    } or do {
        my $msg = $@;
        eval {
            $hive_dba->get_LogMessageAdaptor()->store_worker_message($worker, $msg, 1 );
            $worker->cause_of_death( 'SEE_MSG' );
            $queen->register_worker_death($worker, 1);
        };
        $msg .= "\nAND THEN:\n".$@ if $@;
        cleanup_if_needed($worker);
        _update_resource_usage($worker, $worker_stopwatch, 'error');

        die $msg;
    };

}

        # have runnable clean up any global/process files/data it may have created
sub cleanup_if_needed {
    my ($worker) = @_;
    if($worker->perform_cleanup) {
        if(my $runnable_object = $worker->runnable_object) {    # the temp_directory is actually kept in the Process object:
            $runnable_object->cleanup_worker_temp_directory();
        }
    }
}

sub _update_resource_usage {
    my ($worker, $worker_stopwatch, $exception_status) = @_;

    $worker_stopwatch->pause();
    my $resource_usage;
    eval {
        # Try BSD::Resource if present
        my $res_self;
        my $res_child;
        # NOTE: I couldn't find a way of require-ing the module and getting
        # the barewords RUSAGE_* imported
        eval q{
            use BSD::Resource;
            $res_self = BSD::Resource::getrusage(RUSAGE_SELF);
            $res_child = BSD::Resource::getrusage(RUSAGE_CHILDREN);
            };
        return 0 if $@;
        $resource_usage = {
            'exit_status'   => 'done',
            'mem_megs'      => ($res_self->maxrss + $res_child->maxrss) / 1024.,
            'swap_megs'     => undef,
            'pending_sec'   => 0,
            'cpu_sec'       => $res_self->utime + $res_self->stime + $res_child->utime + $res_child->stime,
            'lifespan_sec'  => $worker_stopwatch->get_elapsed(),
            'exception_status' => $exception_status,
        };

    } or eval {
        # Unix::Getrusage otherwise
        require Unix::Getrusage;
        my $res_self = Unix::Getrusage::getrusage();
        my $res_child = Unix::Getrusage::getrusage_children();
        $resource_usage = {
            'exit_status'   => 'done',
            'mem_megs'      => ($res_self->{ru_maxrss} + $res_child->{ru_maxrss}) / 1024.,
            'swap_megs'     => undef,
            'pending_sec'   => 0,
            'cpu_sec'       => $res_self->{ru_utime} + $res_self->{ru_stime} + $res_child->{ru_utime} + $res_child->{ru_stime},
            'lifespan_sec'  => $worker_stopwatch->get_elapsed(),
            'exception_status' => $exception_status,
        };
    };

    # Store the data if one of the above calls was successful
    if ($resource_usage) {
        $worker->adaptor->store_resource_usage(
            {$worker->process_id => $resource_usage},
            {$worker->process_id => $worker->dbID},
        );
    }
}

1;
