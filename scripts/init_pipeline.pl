#!/usr/bin/env perl

# A generic loader of hive pipelines

use strict;
use warnings;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Utils::Argument;          # import 'rearrange()'
use Bio::EnsEMBL::Hive::Utils 'stringify';  # import 'stringify()'
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Extensions;

sub dbconn_2_url {
    my $db_conn = shift @_;

    return "mysql://$db_conn->{-user}:$db_conn->{-pass}\@$db_conn->{-host}:$db_conn->{-port}/$db_conn->{-dbname}";
}

sub main {

    my $topup_flag  = 0;  # do not run initial scripts and only add new analyses+jobs (ignore the fetchable analyses)
    my $config_file = '';

    GetOptions(
               'topup=i'    => \$topup_flag,
               'conf=s'     => \$config_file,
    );

    unless($config_file and (-f $config_file)) {
        warn "Please supply a valid pipeline configuration file using '-conf' option\n";
        warn "Usage example:\n\t$0 -conf ../docs/long_mult_pipeline.conf\n";
        exit(1);
    }

    my $self = bless ( do $config_file );

    if(!$topup_flag && $self->{-pipeline_create_commands}) {
        foreach my $cmd (@{$self->{-pipeline_create_commands}}) {
            warn "Running the command:\n\t$cmd\n";
            if(my $retval = system($cmd)) {
                die "Return value = $retval, possibly an error\n";
            } else {
                warn "Done.\n\n";
            }
        }
    }

    my $hive_dba                     = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{-pipeline_db}});
    
    if($self->{-pipeline_wide_parameters}) {
        my $meta_container = $hive_dba->get_MetaContainer;

        warn "Loading pipeline-wide parameters ...\n";

        while( my($meta_key, $meta_value) = each %{$self->{-pipeline_wide_parameters}} ) {
            if($topup_flag) {
                $meta_container->delete_key($meta_key);
            }
            $meta_container->store_key_value($meta_key, $meta_value);
        }

        warn "Done.\n\n";
    }

        # pre-load the resource_description table
    if($self->{-resource_classes}) {
        my $resource_description_adaptor = $hive_dba->get_ResourceDescriptionAdaptor;

        warn "Loading the ResourceDescriptions ...\n";

        while( my($rc_id, $mt2param) = each %{$self->{-resource_classes}} ) {
            my $description = delete $mt2param->{-desc};
            while( my($meadow_type, $xparams) = each %$mt2param ) {
                $resource_description_adaptor->create_new(
                    -RC_ID       => $rc_id,
                    -MEADOW_TYPE => $meadow_type,
                    -PARAMETERS  => $xparams,
                    -DESCRIPTION => $description,
                );
            }
        }

        warn "Done.\n\n";
    }

    my $analysis_adaptor             = $hive_dba->get_AnalysisAdaptor;

    foreach my $aha (@{$self->{-pipeline_analyses}}) {
        my ($logic_name, $module, $parameters_hash, $input_ids, $blocked, $batch_size, $hive_capacity, $rc_id) =
             rearrange([qw(logic_name module parameters input_ids blocked batch_size hive_capacity rc_id)], %$aha);

        if($topup_flag and $analysis_adaptor->fetch_by_logic_name($logic_name)) {
            warn "Skipping already existing analysis '$logic_name'\n";
            next;
        }

        warn "Creating '$logic_name'...\n";

        my $analysis = Bio::EnsEMBL::Analysis->new (
            -db              => '',
            -db_file         => '',
            -db_version      => '1',
            -logic_name      => $logic_name,
            -module          => $module,
            -parameters      => stringify($parameters_hash),    # have to stringify it here, because Analysis code is external wrt Hive code
        );

        $analysis_adaptor->store($analysis);

        my $stats = $analysis->stats();
        $stats->batch_size( $batch_size )       if(defined($batch_size));

# ToDo: hive_capacity for some analyses is set to '-1' (i.e. "not limited")
# Do we want this behaviour BY DEFAULT?
        $stats->hive_capacity( $hive_capacity ) if(defined($hive_capacity));

        $stats->rc_id( $rc_id ) if(defined($rc_id));

            # some analyses will be waiting for human intervention in blocked state:
        $stats->status($blocked ? 'BLOCKED' : 'READY');
        $stats->update();

            # now create the corresponding jobs (if there are any):
        foreach my $input_id_hash (@$input_ids) {

            Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                -input_id       => $input_id_hash,  # input_ids are now centrally stringified in the AnalysisJobAdaptor
                -analysis       => $analysis,
                -input_job_id   => 0, # because these jobs are created by the initialization script, not by another job
            );
        }
    }

        # Now, run separately through the already created analyses and link them together:
        #
    my $ctrl_rule_adaptor            = $hive_dba->get_AnalysisCtrlRuleAdaptor;
    my $dataflow_rule_adaptor        = $hive_dba->get_DataflowRuleAdaptor;

    foreach my $aha (@{$self->{-pipeline_analyses}}) {
        my ($logic_name, $wait_for, $flow_into) =
             rearrange([qw(logic_name wait_for flow_into)], %$aha);

        my $analysis = $analysis_adaptor->fetch_by_logic_name($logic_name);

        $wait_for ||= [];
        $wait_for   = [ $wait_for ] unless(ref($wait_for) eq 'ARRAY'); # force scalar into an arrayref

            # create control rules:
        foreach my $condition_logic_name (@$wait_for) {
            if(my $condition_analysis = $analysis_adaptor->fetch_by_logic_name($condition_logic_name)) {
                $ctrl_rule_adaptor->create_rule( $condition_analysis, $analysis);
                warn "Created Control rule: $condition_logic_name -| $logic_name\n";
            } else {
                die "Could not fetch analysis '$condition_logic_name' to create a control rule";
            }
        }

        $flow_into ||= {};
        $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

        foreach my $branch_code (sort {$a <=> $b} keys %$flow_into) {
            my $heir_logic_names = $flow_into->{$branch_code};
            $heir_logic_names    = [ $heir_logic_names ] unless(ref($heir_logic_names) eq 'ARRAY'); # force scalar into an arrayref

            foreach my $heir_logic_name (@$heir_logic_names) {
                if(my $heir_analysis = $analysis_adaptor->fetch_by_logic_name($heir_logic_name)) {
                    $dataflow_rule_adaptor->create_rule( $analysis, $heir_analysis, $branch_code);
                    warn "Created DataFlow rule: [$branch_code] $logic_name -> $heir_logic_name\n";
                } else {
                    die "Could not fetch analysis '$heir_logic_name' to create a dataflow rule";
                }
            }
        }
    }

    my $url = dbconn_2_url($self->{-pipeline_db});

    print "\n\n\tPlease run the following commands:\n\n";
    print "  beekeeper.pl -url $url -sync\n";
    print "  beekeeper.pl -url $url -loop\n";
}

main();

