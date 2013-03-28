#!/usr/bin/env perl

use strict;
use warnings;
use XML::LibXML;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;


sub struct_2_dom {
    my ($structure, $dom) = @_;

    my $ref = ref($structure);

    if(!$ref) {
        my $scalar_node = $dom->createTextNode( $structure );
        return $scalar_node;
    } elsif($ref eq 'ARRAY') {
        my $array_node = $dom->createElement('array');
        foreach my $value (@$structure) {
            my $array_item = $dom->createElement('item');
            $array_node->appendChild($array_item);

            $array_item->appendChild( struct_2_dom( $value, $dom ) );
        }
        return $array_node;
    } elsif($ref eq 'HASH') {
        my $hash_node = $dom->createElement('hash');
        while(my ($key, $value) = each %$structure) {
            my $hash_pair = $dom->createElement('pair');
            $hash_node->appendChild($hash_pair);

            $hash_pair->setAttribute('key', $key);
            $hash_pair->appendChild( struct_2_dom( $value, $dom ) );
        }
        return $hash_node;
    } else {
        return "UNSUPPORTED NODE TYPE '$ref'";
    }
}


sub resource_mapping_2_dom {
    my ($hive_dba, $dom) = @_;

    my $resource_class_adaptor          = $hive_dba->get_ResourceClassAdaptor;
    my $resource_description_adaptor    = $hive_dba->get_ResourceDescriptionAdaptor;

    my $rc_id2name  = $resource_class_adaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
    my %meadow_type_rc_name2xparams = ();
    foreach my $rd (@{ $resource_description_adaptor->fetch_all() }) {
        $meadow_type_rc_name2xparams{ $rd->meadow_type() }{ $rc_id2name->{$rd->resource_class_id} } = $rd->parameters();
    }

    my $resource_mapping_element = $dom->createElement('resource_mapping');

    foreach my $meadow_type (keys %meadow_type_rc_name2xparams) {
        my $meadow_element = $dom->createElement('meadow');
        $resource_mapping_element->appendChild($meadow_element);
        $meadow_element->setAttribute('type', $meadow_type);

        while(my($rc_name, $xparams) = each %{ $meadow_type_rc_name2xparams{$meadow_type} }) {
            my $resource_element = $dom->createElement('resource');
            $meadow_element->appendChild($resource_element);
            $resource_element->setAttribute('name', $rc_name);
            $resource_element->setAttribute('value', $xparams);
        }
    }
    return $resource_mapping_element;
}


sub parameters_2_dom {
    my ($parameters_element_name, $parameters_hash, $dom) = @_;

    my $parameters_element = $dom->createElement( $parameters_element_name );

    while(my($key,$value) = each %$parameters_hash) {
        my $param_element = $dom->createElement('param');
        $parameters_element->appendChild($param_element);

        $param_element->setAttribute('name', $key);
        $param_element->appendChild( struct_2_dom( $value, $dom ) );
    }

    return $parameters_element;
}


sub pipeline_analyses_2_dom {
    my ($hive_dba, $dom) = @_;

    my $analysis_adaptor                = $hive_dba->get_AnalysisAdaptor;
    my $ctrl_rule_adaptor               = $hive_dba->get_AnalysisCtrlRuleAdaptor;
    my $dataflow_rule_adaptor           = $hive_dba->get_DataflowRuleAdaptor;

    my $rc_id2name                      = $hive_dba->get_ResourceClassAdaptor->fetch_HASHED_FROM_resource_class_id_TO_name();

    my $pipeline_analyses_element       = $dom->createElement('pipeline_analyses');

    foreach my $analysis (@{ $analysis_adaptor->fetch_all() }) {
        my $analysis_id         = $analysis->dbID();
        my $analysis_element    = $dom->createElement('analysis');
        $pipeline_analyses_element->appendChild( $analysis_element );

        foreach my $attrib ('logic_name', 'module',
                'analysis_capacity', 'can_be_empty', 'failed_job_tolerance', 'max_retry_count', 'meadow_type', 'priority') {
            if(defined(my $value = $analysis->$attrib())) {
                $analysis_element->setAttribute( $attrib, $value );
            }
        }
        my $stats = $analysis->stats();
        foreach my $attrib ('hive_capacity', 'batch_size') {
            if(my $value = $stats->$attrib()) {
                $analysis_element->setAttribute( $attrib, $value );
            }
        }

        my $analysis_parameters_hash = eval ( $analysis->parameters() || '{}');
        $analysis_element->appendChild( parameters_2_dom( 'parameters', $analysis_parameters_hash, $dom ) ) if(scalar(keys %$analysis_parameters_hash));

        $analysis_element->setAttribute( 'rc_name', $rc_id2name->{$analysis->resource_class_id} );

        if(my @wait_for_rules = @{ $ctrl_rule_adaptor->fetch_all_by_ctrled_analysis_id( $analysis_id ) }) {
            my $wait_for_rules_element    = $dom->createElement('wait_for_rules');
            $analysis_element->appendChild( $wait_for_rules_element );
            foreach my $c_rule (@wait_for_rules) {
                my $wait_for_element    = $dom->createElement('wait_for');
                $wait_for_rules_element->appendChild( $wait_for_element );
                $wait_for_element->setAttribute( 'condition', $c_rule->condition_analysis_url );
            }
        }

        my %dependent_flow_elements = ();
        my %toplevel_flow_elements = ();

        if(my @flow_rules = @{ $dataflow_rule_adaptor->fetch_all_by_from_analysis_id( $analysis_id )}) {

            my $flow_rules_element = $dom->createElement('flow_rules');
            $analysis_element->appendChild( $flow_rules_element );

                # separate dataflow into semaphored and non-semaphored
            foreach my $df_rule (@flow_rules) {
                my $dfr_id = $df_rule->dbID;

                my $flow_element = $dom->createElement('flow');
                $flow_element->setAttribute( 'target', $df_rule->to_analysis_url );
                $flow_element->setAttribute( 'branch', $df_rule->branch_code ) if($df_rule->branch_code != 1);
                if($df_rule->input_id_template) {
                    my $template_element = $dom->createElement('template');
                    $flow_element->appendChild( $template_element );
                    $template_element->appendChild( struct_2_dom( eval $df_rule->input_id_template, $dom ) );
                }

                if(my $funnel_rule_id = $df_rule->funnel_dataflow_rule_id) {    # dependent flows (semaphore fans)
                    push @{ $dependent_flow_elements{$funnel_rule_id} }, $flow_element;
                } else {    # independent ones (semaphored funnels & free ones)
                    $toplevel_flow_elements{$dfr_id} = $flow_element;
                }
            }

            while(my ($flow_id, $flow_element) = each %toplevel_flow_elements) {
                if(my $dependants = $dependent_flow_elements{$flow_id}) {
                    my $dependent_rules_element = $dom->createElement('dependent');
                    $flow_element->appendChild( $dependent_rules_element );

                    foreach my $dependent_rule_element (@$dependants) {
                        $dependent_rules_element->appendChild( $dependent_rule_element );
                    }
                }
                $flow_rules_element->appendChild( $flow_element );
            }
        }
    }

    return $pipeline_analyses_element;
}


sub pipeline_2_dom {
    my $hive_dba = shift @_;

    my $dom = XML::LibXML::Document->new('1.0', 'UTF-8');

    my $pipeline = $dom->createElement('pipeline');
    $dom->setDocumentElement($pipeline);

    $pipeline->appendChild( resource_mapping_2_dom( $hive_dba, $dom ) );

    my $pipeline_parameters_hash = $hive_dba->get_MetaContainer->get_param_hash();
    $pipeline->appendChild( parameters_2_dom( 'pipeline_parameters', $pipeline_parameters_hash, $dom ) );

    $pipeline->appendChild( pipeline_analyses_2_dom( $hive_dba, $dom ) );

    return $dom;
}


sub main {
    my $url         = $ARGV[0] || 'mysql://ensadmin:ensembl@localhost:3306/lg4_long_mult';

    my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $url);

    my $dom         = pipeline_2_dom( $hive_dba );

    print $dom->toString(1);
}

main();
