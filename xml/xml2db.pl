#!/usr/bin/env perl

use strict;
use warnings;
use XML::Simple qw(:strict);
use Data::Dumper;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('stringify');  # import 'stringify()'

sub dbconn_2_mysql {    # will save you a lot of typing
    my ($db_conn, $with_db) = @_;

    return '--host='.$db_conn->{host}.' '
          .'--port='.$db_conn->{port}.' '
          .'--user="'.$db_conn->{user}.'" '
          .'--pass="'.$db_conn->{pass}.'" '
          .($with_db ? ($db_conn->{dbname}.' ') : '');
}

sub dbconn_2_url {
    my ($db_conn) = @_;

    return 'mysql://'.$db_conn->{user}.':'.$db_conn->{pass}.'@'.$db_conn->{host}.':'.$db_conn->{port}.'/'.$db_conn->{dbname};
}


sub create_and_populate_db {
    my ($db_conn, $ensembl_cvs_root_dir) = @_;

    my $commands = [
        'mysql '.dbconn_2_mysql($db_conn, 0)." -e 'CREATE DATABASE `".$db_conn->{dbname}."`'",
        'mysql '.dbconn_2_mysql($db_conn, 1).' <'.$ensembl_cvs_root_dir.'/ensembl-hive/sql/tables.sql',
        'mysql '.dbconn_2_mysql($db_conn, 1).' <'.$ensembl_cvs_root_dir.'/ensembl-hive/sql/foreign_keys.mysql',
        'mysql '.dbconn_2_mysql($db_conn, 1).' <'.$ensembl_cvs_root_dir.'/ensembl-hive/sql/procedures.mysql',
    ];

    foreach my $cmd (@$commands) {
        warn "Running the command:\n\t$cmd\n";
        if(my $retval = system($cmd)) {
            die "Return value = $retval, possibly an error\n";
        } else {
            warn "Done.\n\n";
        }
    }
}




my $xml_filename = $ARGV[0] || 'LM1.xml';

my $tree = XML::Simple->new()->XMLin(
    $xml_filename,
    KeyAttr => [],
    NoAttr => 1,
    ForceArray => [ 'analysis', 'flow' ],
);

my $db_conn = $tree->{hive_db} || die "No connection parameters";

create_and_populate_db( $db_conn, $ENV{'ENSEMBL_CVS_ROOT_DIR'} );

my $url                             = dbconn_2_url( $db_conn );
my $hive_dba                        = Bio::EnsEMBL::Hive::URLFactory->fetch($url) || die "Unable to connect to $url\n";
my $meta_container                  = $hive_dba->get_MetaContainer;

        warn "Loading pipeline-wide parameters ...\n";

        foreach my $pair (@{ $tree->{pipeline_parameters}{param} }) {
            my $meta_key    = $pair->{param_name};
            my $meta_value  = $pair->{param_value};
#            $meta_container->delete_key($meta_key);
            $meta_container->store_key_value($meta_key, stringify($meta_value));
        }
        warn "Done.\n\n";




__END__



my $hive_dba                        = Bio::EnsEMBL::Hive::URLFactory->fetch($url) || die "Unable to connect to $url\n";
my $analysis_adaptor                = $hive_dba->get_AnalysisAdaptor;
my $ctrl_rule_adaptor               = $hive_dba->get_AnalysisCtrlRuleAdaptor;
my $dataflow_rule_adaptor           = $hive_dba->get_DataflowRuleAdaptor;
my $resource_class_adaptor          = $hive_dba->get_ResourceClassAdaptor;
my $resource_description_adaptor    = $hive_dba->get_ResourceDescriptionAdaptor;
