#!/usr/local/ensembl/bin/perl -w

# A generic loader of hive pipelines

use strict;
use DBI;
use Getopt::Long;
use Data::Dumper;                   # NB: in this case it is not for testing but for actual data structure stringification
use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Extensions;

sub main {

    my $topup_flag  = 0;  # do not run initial scripts and only add new analyses+jobs (ignore the fetchable analyses)
    my $config_file = '';

    GetOptions(
               'topup=i'    => \$topup_flag,
               'conf=s'     => \$config_file,
    );

    unless($config_file and (-f $config_file)) {
        warn "Please supply a valid pipeline configuration file using '-conf' option\n";
        warn "Usage example:\n\ttime $0 -conf ~lg4/work/ensembl-compara/scripts/family/family_pipeline.conf\n";
        exit(1);
    }

    my $self = bless { do $config_file };

    unless($topup_flag) {
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
    my $resource_description_adaptor = $hive_dba->get_ResourceDescriptionAdaptor;
    
    warn "Loading the ResourceDescriptions ...\n";

        # pre-load the resource_description table with the values that we'll need:
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

    my $analysis_adaptor             = $hive_dba->get_AnalysisAdaptor;

        # tune Data::Dumper module to produce the output we want:
    $Data::Dumper::Indent     = 0;  # we want everything on one line
    $Data::Dumper::Terse      = 1;  # and we want it without dummy variable names

    foreach my $aha (@{$self->{-pipeline_analyses}}) {
        my ($logic_name, $module, $parameters, $input_ids, $blocked, $batch_size, $hive_capacity, $rc_id) =
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
            -parameters      => Dumper($parameters),
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
        foreach my $input_id (@$input_ids) {

            Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                -input_id       => Dumper($input_id),
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

            # create control rules:
        foreach my $condition_logic_name (@$wait_for) {
            if(my $condition_analysis = $analysis_adaptor->fetch_by_logic_name($condition_logic_name)) {
                $ctrl_rule_adaptor->create_rule( $condition_analysis, $analysis);
                warn "Created Control rule: $condition_logic_name -| $logic_name\n";
            } else {
                die "Could not fetch analysis '$condition_logic_name' to create a control rule";
            }
        }
        foreach my $heir (@$flow_into) {
            my ($heir_logic_name, $branch) = (ref($heir) eq 'ARRAY') ? (@$heir, 1) : ($heir, 1);

            if(my $heir_analysis = $analysis_adaptor->fetch_by_logic_name($heir_logic_name)) {
                $dataflow_rule_adaptor->create_rule( $analysis, $heir_analysis, $branch);
                warn "Created DataFlow rule: $logic_name -> $heir_logic_name (branch=$branch)\n";
            } else {
                die "Could not fetch analysis '$heir_logic_name' to create a dataflow rule";
            }
        }
    }

    print "\n\n\tPlease run the following commands:\n\n";
    print "  beekeeper.pl -url ".dbconn_2_url($self->{-pipeline_db})." -sync\n";
    print "  beekeeper.pl -url ".dbconn_2_url($self->{-pipeline_db})." -loop\n";
}

main();

