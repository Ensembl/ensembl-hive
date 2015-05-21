=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;

sub runWorker {
    my ($hive_dba, $specialization_options, $life_options, $execution_options) = @_;

    die "Hive's DBAdaptor is not a defined Bio::EnsEMBL::Hive::DBSQL::DBAdaptor\n" unless $hive_dba and $hive_dba->isa('Bio::EnsEMBL::Hive::DBSQL::DBAdaptor');

    $specialization_options ||= {};
    $life_options ||= {};
    $execution_options ||= {};

    my $queen = $hive_dba->get_Queen();
    die "No Queen, God Bless Her\n" unless $queen and $queen->isa('Bio::EnsEMBL::Hive::Queen');

    my ($meadow_type, $meadow_name, $process_id, $meadow_host, $meadow_user) = Bio::EnsEMBL::Hive::Valley->new()->whereami();
    die "Valley is not fully defined" unless ($meadow_type && $meadow_name && $process_id && $meadow_host && $meadow_user);

        #       preloading all Analysis objects now:
    Bio::EnsEMBL::Hive::Analysis->collection( Bio::EnsEMBL::Hive::Utils::Collection->new( $hive_dba->get_AnalysisAdaptor->fetch_all ) );
        #
        #       and all AnalysisStats objects as well:
    Bio::EnsEMBL::Hive::AnalysisStats->collection( Bio::EnsEMBL::Hive::Utils::Collection->new( $hive_dba->get_AnalysisStatsAdaptor->fetch_all ) );
        #
        #       and all DataflowRule objects too:
    Bio::EnsEMBL::Hive::DataflowRule->collection( Bio::EnsEMBL::Hive::Utils::Collection->new( $hive_dba->get_DataflowRuleAdaptor->fetch_all ) );


    if( $specialization_options->{'force_sync'} ) {       # sync the Hive in Test mode:
        my $list_of_analyses = Bio::EnsEMBL::Hive::Analysis->collection()->find_all_by_pattern( $specialization_options->{'analyses_pattern'} );

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
        1;

    } or do {
        my $msg = $@;

        $hive_dba->get_LogMessageAdaptor()->store_worker_message($worker, $msg, 1 );

        $worker->cause_of_death( 'SEE_MSG' );
        $queen->register_worker_death($worker, 1);

        die $msg;
    };
}

1;
