
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf

=head1 SYNOPSIS

    # Example 1: specifying only the mandatory option:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <mypass>

    # Example 2: specifying the mandatory options as well as overriding some defaults:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -ensembl_cvs_root_dir ~/ensembl_main -pipeline_db -host <myhost> -pipeline_db -dbname <mydbname> -password <mypass>

=head1 DESCRIPTION

Generic configuration module for all Hive pipelines with loader functionality.
All other Hive PipeConfig modules should inherit from this module and will probably need to redefine some or all of the following interface methods:

    * default_options:                  returns a hash of (possibly multilevel) defaults for the options on which depend the rest of the configuration

    * pipeline_create_commands:         returns a list of strings that will be executed as system commands needed to create and set up the pipeline database

    * pipeline_wide_parameters:         returns a hash of pipeline-wide parameter names and their values

    * resource_classes:                 returns a hash of resource class definitions

    * pipeline_analyses:                returns a list of hash structures that define analysis objects bundled with definitions of corresponding jobs, rules and resources

    * beekeeper_extra_cmdline_options   returns a string with command line options that you want to be passed to the beekeeper.pl

When defining anything except the keys of default_options() a call to $self->o('myoption') can be used.
This call means "substitute this call for the value of 'myoption' at the time of configuring the pipeline".
All option names mentioned in $self->o() calls within the five interface methods above can be given non-default values from the command line.

Please make sure you have studied the pipeline configuraton examples in Bio::EnsEMBL::Hive::PipeConfig before creating your own PipeConfig modules.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument;          # import 'rearrange()'
use Bio::EnsEMBL::Hive::Utils 'stringify';  # import 'stringify()'
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::Extensions;

use base ('Bio::EnsEMBL::Hive::DependentOptions');


# ---------------------------[the following methods will be overridden by specific pipelines]-------------------------


=head2 default_options

    Description : Interface method that should return a hash of option_name->default_option_value pairs.
                  Please see existing PipeConfig modules for examples.

=cut

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir'  => $self->o('ENV', 'ENSEMBL_CVS_ROOT_DIR'),     # it will make sense to set this variable if you are going to use ehive frequently
        'password'              => $self->o('ENV', 'ENSADMIN_PSW'),             # people will have to make an effort NOT to insert it into config files like .bashrc etc

        'host'                  => 'localhost',
        'pipeline_name'         => 'hive_generic',

        'pipeline_db'   => {
            -host   => $self->o('host'),
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => $self->o('ENV', 'USER').'_'.$self->o('pipeline_name'),  # example of a linked definition (resolved via saturation)
        },
    };
}


=head2 pipeline_create_commands

    Description : Interface method that should return a list of command lines to be run in order to create and set up the pipeline database.
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_create_commands {
    my $self    = shift @_;
    my $db_conn = shift @_ || 'pipeline_db';

    my $hive_use_triggers = $self->{'_extra_options'}{'hive_use_triggers'};

    return ($self->o($db_conn, '-driver') eq 'sqlite')
        ? [
                # standard eHive tables, triggers and procedures:
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/tables.sqlite',
            $hive_use_triggers ? ( $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/triggers.sqlite' ) : (),
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/procedures.sqlite',
        ]
        : [
            'mysql '.$self->dbconn_2_mysql($db_conn, 0)." -e 'CREATE DATABASE ".$self->o('pipeline_db', '-dbname')."'",

                # standard eHive tables, triggers, foreign_keys and procedures:
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/tables.sql',
            $hive_use_triggers ? ( $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/triggers.mysql' ) : (),
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/foreign_keys.mysql',
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/procedures.mysql',
        ];
}


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, can be any Perl structure now (will be stringified and de-stringified automagically).
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        'pipeline_name'  => $self->o('pipeline_name'),       # name the pipeline to differentiate the submitted processes
    };
}


=head2 resource_classes

    Description : Interface method that should return a hash of resource_description_id->resource_description_hash.
                  Please see existing PipeConfig modules for examples.

=cut

sub resource_classes {
    my ($self) = @_;
    return {
        0 => { -desc => 'default, 8h',      'LSF' => '' },
        1 => { -desc => 'urgent',           'LSF' => '-q yesterday' },
    };
}


=head2 pipeline_analyses

    Description : Interface method that should return a list of hashes that define analysis bundled with corresponding jobs, dataflow and analysis_ctrl rules and resource_id.
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
    ];
}


=head2 beekeeper_extra_cmdline_options

    Description : Interface method that should return a string with extra parameters that you want to be passed to beekeeper.pl

=cut

sub beekeeper_extra_cmdline_options {
    my ($self) = @_;

    return '';
}


# ---------------------------------[now comes the interfacing stuff - feel free to call but not to modify]--------------------


sub pre_options {
    my $self = shift @_;

    return {
        'help!' => '',
        'job_topup!' => '',
        'analysis_topup!' => '',
        'hive_driver' => '',
        'hive_use_triggers' => '',
    };
}


=head2 dbconn_2_mysql

    Description : A convenience method used to stringify a connection-parameters hash into a parameter string that both mysql and beekeeper.pl can understand

=cut

sub dbconn_2_mysql {    # will save you a lot of typing
    my ($self, $db_conn, $with_db) = @_;

    return '--host='.$self->o($db_conn,'-host').' '
          .'--port='.$self->o($db_conn,'-port').' '
          .'--user="'.$self->o($db_conn,'-user').'" '
          .'--pass="'.$self->o($db_conn,'-pass').'" '
          .($with_db ? ($self->o($db_conn,'-dbname').' ') : '');
}


=head2 db_connect_command

    Description : A convenience method used to stringify a command to connect to the db OR pipe an sql file into it.

=cut

sub db_connect_command {
    my ($self, $db_conn) = @_;

    return ($self->o($db_conn, '-driver') eq 'sqlite')
        ? 'sqlite3 '.$self->o($db_conn, '-dbname')
        : 'mysql '.$self->dbconn_2_mysql($db_conn, 1);
}


=head2 db_execute_command

    Description : A convenience method used to stringify a command to connect to the db OR pipe an sql file into it.

=cut

sub db_execute_command {
    my ($self, $db_conn, $sql_command) = @_;

    return ($self->o($db_conn, '-driver') eq 'sqlite')
        ? 'sqlite3 '.$self->o($db_conn, '-dbname')." '$sql_command'"
        : 'mysql '.$self->dbconn_2_mysql($db_conn, 1)." -e '$sql_command'";
}


=head2 dbconn_2_url

    Description :  A convenience method used to stringify a connection-parameters hash into a 'url' that beekeeper.pl will undestand

=cut

sub dbconn_2_url {
    my ($self, $db_conn) = @_;

    return ($self->o($db_conn, '-driver') eq 'sqlite')
        ? $self->o($db_conn, '-driver').':///'.$self->o($db_conn,'-dbname')
        : $self->o($db_conn, '-driver').'://'.$self->o($db_conn,'-user').':'.$self->o($db_conn,'-pass').'@'.$self->o($db_conn,'-host').':'.$self->o($db_conn,'-port').'/'.$self->o($db_conn,'-dbname');
}

sub pipeline_url {
    my $self = shift @_;

    return $self->dbconn_2_url('pipeline_db'); # used to force vivification of the whole 'pipeline_db' structure (used in run() )
}

=head2 process_options

    Description : The method that does all the parameter parsing magic.
                  It is two-pass through the interface methods: first pass collects the options, second is intelligent substitution.

    Caller      : init_pipeline.pl or any other script that will drive this module.

    Note        : You can override parsing the command line bit by providing a hash as the argument to this method.
                  This hash should contain definitions of all the parameters you would otherwise be providing from the command line.
                  Useful if you are creating batches of hive pipelines using a script.

=cut

sub process_options {
    my $self = shift @_;

        # pre-patch definitely_used_options:
    $self->{'_extra_options'} = $self->load_cmdline_options( $self->pre_options() );
    $self->root()->{'pipeline_db'}{'-driver'} = $self->{'_extra_options'}{'hive_driver'} || 'mysql';

    $self->use_cases( [ 'pipeline_create_commands', 'pipeline_wide_parameters', 'resource_classes', 'pipeline_analyses', 'beekeeper_extra_cmdline_options', 'pipeline_url' ] );
    return $self->SUPER::process_options();
}


=head2 run

    Description : The method that uses the Hive/EnsEMBL API to actually create all the analyses, jobs, dataflow and control rules and resource descriptions.

    Caller      : init_pipeline.pl or any other script that will drive this module.

=cut

sub run {
    my $self  = shift @_;
    my $analysis_topup = $self->{'_extra_options'}{'analysis_topup'};
    my $job_topup      = $self->{'_extra_options'}{'job_topup'};

    unless($analysis_topup || $job_topup) {
        foreach my $cmd (@{$self->pipeline_create_commands}) {
            warn "Running the command:\n\t$cmd\n";
            if(my $retval = system($cmd)) {
                die "Return value = $retval, possibly an error\n";
            } else {
                warn "Done.\n\n";
            }
        }
    }

    my $hive_dba                     = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->o('pipeline_db')});
    
    unless($job_topup) {
        my $meta_container = $hive_dba->get_MetaContainer;
        warn "Loading pipeline-wide parameters ...\n";

        my $pipeline_wide_parameters = $self->pipeline_wide_parameters;
        while( my($meta_key, $meta_value) = each %$pipeline_wide_parameters ) {
            if($analysis_topup) {
                $meta_container->delete_key($meta_key);
            }
            $meta_container->store_key_value($meta_key, stringify($meta_value));
        }
        warn "Done.\n\n";

            # pre-load the resource_description table
        my $resource_description_adaptor = $hive_dba->get_ResourceDescriptionAdaptor;
        warn "Loading the ResourceDescriptions ...\n";

        my $resource_classes = $self->resource_classes;
        while( my($rc_id, $mt2param) = each %$resource_classes ) {
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

    my %seen_logic_name = ();

    foreach my $aha (@{$self->pipeline_analyses}) {
        my ($logic_name, $module, $parameters_hash, $input_ids, $program_file, $blocked, $batch_size, $hive_capacity, $failed_job_tolerance, $max_retry_count, $can_be_empty, $rc_id) =
             rearrange([qw(logic_name module parameters input_ids program_file blocked batch_size hive_capacity failed_job_tolerance max_retry_count can_be_empty rc_id)], %$aha);

        unless($logic_name) {
            die "logic_name' must be defined in every analysis";
        }

        if($seen_logic_name{$logic_name}++) {
            die "an entry with logic_name '$logic_name' appears at least twice in the configuration file, can't continue";
        }

        my $analysis = $analysis_adaptor->fetch_by_logic_name($logic_name);
        if( $analysis ) {

            if($analysis_topup) {
                warn "Skipping creation of already existing analysis '$logic_name'.\n";
                next;
            }

        } else {

            if($job_topup) {
                die "Could not fetch analysis '$logic_name'";
            }

            warn "Creating analysis '$logic_name'.\n";

            $analysis = Bio::EnsEMBL::Analysis->new(
                -db              => '',
                -db_file         => '',
                -db_version      => '1',
                -logic_name      => $logic_name,
                -module          => $module,
                -parameters      => stringify($parameters_hash || {}),    # have to stringify it here, because Analysis code is external wrt Hive code
                -program_file    => $program_file,
            );

            $analysis_adaptor->store($analysis);

            my $stats = $analysis->stats();
            $stats->batch_size( $batch_size )                       if(defined($batch_size));
            $stats->hive_capacity( $hive_capacity )                 if(defined($hive_capacity));
            $stats->failed_job_tolerance( $failed_job_tolerance )   if(defined($failed_job_tolerance));
            $stats->max_retry_count( $max_retry_count )             if(defined($max_retry_count));
            $stats->rc_id( $rc_id )                                 if(defined($rc_id));
            $stats->can_be_empty( $can_be_empty )                   if(defined($can_be_empty));
            $stats->status($blocked ? 'BLOCKED' : 'READY');         # be careful, as this "soft" way of blocking may be accidentally unblocked by deep sync
            $stats->update();
        }

            # now create the corresponding jobs (if there are any):
        foreach my $input_id_hash (@{$input_ids || []}) {

            Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                -input_id       => $input_id_hash,  # input_ids are now centrally stringified in the AnalysisJobAdaptor
                -analysis       => $analysis,
                -input_job_id   => undef, # these jobs are created by the initialization script, not by another job
            );
        }
    }

    unless($job_topup) {

            # Now, run separately through the already created analyses and link them together:
            #
        my $ctrl_rule_adaptor            = $hive_dba->get_AnalysisCtrlRuleAdaptor;
        my $dataflow_rule_adaptor        = $hive_dba->get_DataflowRuleAdaptor;

        foreach my $aha (@{$self->pipeline_analyses}) {
            my ($logic_name, $wait_for, $flow_into) =
                 rearrange([qw(logic_name wait_for flow_into)], %$aha);

            my $analysis = $analysis_adaptor->fetch_by_logic_name($logic_name);

            $wait_for ||= [];
            $wait_for   = [ $wait_for ] unless(ref($wait_for) eq 'ARRAY'); # force scalar into an arrayref

                # create control rules:
            foreach my $condition_url (@$wait_for) {
                if(my $condition_analysis = $analysis_adaptor->fetch_by_logic_name_or_url($condition_url)) {

                    $ctrl_rule_adaptor->create_rule( $condition_analysis, $analysis);

                    warn "Control rule: $condition_url -| $logic_name\n";
                } else {
                    die "Could not fetch analysis '$condition_url' to create a control rule";
                }
            }

            $flow_into ||= {};
            $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

            foreach my $branch_tag (keys %$flow_into) {
                my ($branch_name_or_code, $funnel_branch_name_or_code) = split(/:/, $branch_tag);
                my $heirs = $flow_into->{$branch_tag};

                $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first

                $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY'); # now force it into a hash if it wasn't

                while(my ($heir_url, $input_id_template_list) = each %$heirs) {
                    
                    $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

                    foreach my $input_id_template (@$input_id_template_list) {

                        my $heir_analysis = $analysis_adaptor->fetch_by_logic_name_or_url($heir_url);

                        $dataflow_rule_adaptor->create_rule( $analysis, $heir_analysis || $heir_url, $branch_name_or_code, $input_id_template, $funnel_branch_name_or_code);

                        warn "DataFlow rule: [$branch_tag] $logic_name -> $heir_url"
                            .($input_id_template ? ' WITH TEMPLATE: '.stringify($input_id_template) : '')."\n";
                    }
                }
            }
        }
    }

    my $url = $self->dbconn_2_url('pipeline_db');

    print "\n\n\tPlease run the following commands:\n\n";
    print "  beekeeper.pl -url $url -sync\t\t\t# (synchronize the Hive - should always be done before [re]starting a pipeline)\n\n";
    print "  beekeeper.pl -url $url ".$self->beekeeper_extra_cmdline_options()." -loop\t\t# (run the pipeline in automatic mode)\n";
    print "(OR)\n";
    print "  beekeeper.pl -url $url ".$self->beekeeper_extra_cmdline_options()." -run \t\t# (run one step of the pipeline - useful for debugging/learning)\n";
    print "(OR)\n";
    print "  runWorker.pl -url $url ".$self->beekeeper_extra_cmdline_options()."      \t\t# (run exactly one Worker locally - useful for debugging/learning)\n";

    print "\n\n\tTo connect to your pipeline database use the following line:\n\n";
    print "  ".$self->db_connect_command('pipeline_db')."\n\n";
}

1;

