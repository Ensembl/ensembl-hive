#!/usr/bin/env perl

use strict;
use warnings;
use XML::Simple qw(:strict);
use Data::Dumper;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

my $url = $ARGV[0] || 'mysql://ensadmin:ensembl@localhost:3306/lg4_long_mult';

my $hive_dba                        = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $url);
my $analysis_adaptor                = $hive_dba->get_AnalysisAdaptor;
my $ctrl_rule_adaptor               = $hive_dba->get_AnalysisCtrlRuleAdaptor;
my $dataflow_rule_adaptor           = $hive_dba->get_DataflowRuleAdaptor;
my $resource_class_adaptor          = $hive_dba->get_ResourceClassAdaptor;
my $resource_description_adaptor    = $hive_dba->get_ResourceDescriptionAdaptor;


sub structured_type {
    my ($structure) = @_;

    if(!ref($structure)) {
        return $structure;
    } elsif(ref($structure) eq 'ARRAY') {
        my @mapped = map { structured_type($_) } @$structure;
        return { 'array' => { 'array_item' => \@mapped} };
    } elsif(ref($structure) eq 'HASH') {
        my @mapped = map { { 'hash_key' => $_, 'hash_value' => structured_type($structure->{$_}) } } keys %$structure;
        return { 'hash' => { 'hash_pair' => \@mapped } };
    } else {
        return 'UNKNOWN NODE TYPE';
    }
}

my $tree = {
    'pipeline' => {
        'pipeline_parameters' => {
            'param' => [],
        },
        'pipeline_analyses' => {
            'analysis' => [],
        },
    },
};

foreach my $method ('host', 'port', 'username', 'password', 'dbname') {
    my $value = $hive_dba->dbc->$method();
    my $tag = (length($method)==8) ? substr($method, 0, 4) : $method;
    $tree->{pipeline}{hive_db}{$tag} = $value;
}


my $rc_id2name  = $resource_class_adaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
my %meadow_type_rc_name2xparams = ();
foreach my $rd (@{ $resource_description_adaptor->fetch_all() }) {
    $meadow_type_rc_name2xparams{ $rd->meadow_type() }{ $rc_id2name->{$rd->resource_class_id} } = $rd->parameters();
}

my $resource_mapping = [];
foreach my $meadow_type (keys %meadow_type_rc_name2xparams) {
    my $meadow_node = { 'meadow_type' => $meadow_type };
    while(my($rc_name, $xparams) = each %{ $meadow_type_rc_name2xparams{$meadow_type} }) {
        push @{ $meadow_node->{resources}{resource} }, { 'resource_name' => $rc_name, 'resource_string' => $xparams };
    }
    push @$resource_mapping, { 'meadow' => $meadow_node };
}
$tree->{pipeline}{resource_mapping} = $resource_mapping;


my $pipeline_parameters     = $hive_dba->get_MetaContainer->get_param_hash();
while(my($key,$value) = each %$pipeline_parameters) {
    push @{ $tree->{pipeline}{pipeline_parameters}{param} }, { 'param_name' => $key, 'param_value' => structured_type($value) };
}

foreach my $analysis (@{ $analysis_adaptor->fetch_all() }) {

    my $analysis_id     = $analysis->dbID();
    my $analysis_node   = {};
    foreach my $attrib ('logic_name', 'module',
            'analysis_capacity', 'can_be_empty', 'failed_job_tolerance', 'max_retry_count', 'meadow_type', 'priority') {
        if(defined(my $value = $analysis->$attrib())) {
            $analysis_node->{$attrib} = $value;
        }
    }
    my $stats = $analysis->stats();
    foreach my $attrib ('hive_capacity', 'batch_size') {
        if(my $value = $stats->$attrib()) {
            $analysis_node->{$attrib} = $value;
        }
    }

    my $parameters_hash = eval ( $analysis->parameters() || '{}');
    while(my($key,$value) = each %$parameters_hash) {
        push @{ $analysis_node->{parameters}{param} }, { 'param_name' => $key, 'param_value' => structured_type($value) };
    }

    my $rc_name = $rc_id2name->{$analysis->resource_class_id};
    $analysis_node->{rc_name} = $rc_name;

    foreach my $c_rule (@{ $ctrl_rule_adaptor->fetch_all_by_ctrled_analysis_id( $analysis_id )}) {
        push @{ $analysis_node->{wait_for_rules}{wait_for} }, $c_rule->condition_analysis_url;
    }

    my %dependent_flow_nodes = ();
    my %toplevel_flow_nodes = ();

        # separate dataflow into semaphored and non-semaphored
    foreach my $df_rule (@{ $dataflow_rule_adaptor->fetch_all_by_from_analysis_id( $analysis_id )}) {
        my $dfr_id = $df_rule->dbID;

        my $flow_node = {
            target => $df_rule->to_analysis_url,
            $df_rule->branch_code != 1  ? (branch => $df_rule->branch_code) : (),
            $df_rule->input_id_template ? (template => structured_type(eval $df_rule->input_id_template)) : (),
        };

        if(my $funnel_rule_id = $df_rule->funnel_dataflow_rule_id) {    # dependent flows (semaphore fans)
            push @{ $dependent_flow_nodes{$funnel_rule_id} }, $flow_node;
        } else {    # independent ones (semaphored funnels & free ones)
            $toplevel_flow_nodes{$dfr_id} = $flow_node;
        }
    }

    while(my ($flow_id, $flow_node) = each %toplevel_flow_nodes) {
        if(my $dependants = $dependent_flow_nodes{$flow_id}) {
            $flow_node->{dependent}{flow} = $dependants;
        }
        push @{ $analysis_node->{flow_rules}{flow} }, $flow_node;
    }

    push @{ $tree->{pipeline}{pipeline_analyses}{analysis} }, $analysis_node;
}

#print Dumper($tree)."\n";

my $xml_simple = XML::Simple->new(
    XMLDecl => 1,
    KeepRoot => 1,
    KeyAttr => [],
    NoAttr => 1,
    ForceArray => [ 'analysis', 'flow' ],
);

my $xml = $xml_simple->XMLout( $tree );

print "$xml\n";
