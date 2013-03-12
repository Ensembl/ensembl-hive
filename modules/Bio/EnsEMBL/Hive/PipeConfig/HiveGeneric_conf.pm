
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
use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::Hive::Valley;

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
        'hive_use_triggers'     => 0,                   # there have been a few cases of big pipelines misbehaving with triggers on, let's keep the default off.

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

    return ($self->o($db_conn, '-driver') eq 'sqlite')
        ? [
                # standard eHive tables, triggers and procedures:
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/tables.sqlite',
            $self->o('hive_use_triggers') ? ( $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/triggers.sqlite' ) : (),
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/procedures.sqlite',
        ]
        : [
            'mysql '.$self->dbconn_2_mysql($db_conn, 0)." -e 'CREATE DATABASE `".$self->o('pipeline_db', '-dbname')."`'",

                # standard eHive tables, triggers, foreign_keys and procedures:
            $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/tables.sql',
            $self->o('hive_use_triggers') ? ( $self->db_connect_command($db_conn).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/triggers.mysql' ) : (),
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
## Old style:
#        1 => { -desc => 'default',  'LSF' => '' },
#        2 => { -desc => 'urgent',   'LSF' => '-q yesterday' },
## New style:
        'default' => { 'LSF' => '' },
        'urgent'  => { 'LSF' => '-q yesterday' },
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
#        'hive_use_triggers' => '',
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

    my $hive_dba                     = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( %{$self->o('pipeline_db')} );
    my $resource_class_adaptor       = $hive_dba->get_ResourceClassAdaptor;
    
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

            # pre-load resource_class and resource_description tables:
        my $resource_description_adaptor    = $hive_dba->get_ResourceDescriptionAdaptor;
        warn "Loading the Resources ...\n";

        my $resource_classes_hash = $self->resource_classes;
        my @resource_classes_order = sort { ($b eq 'default') or -($a eq 'default') or ($a cmp $b) } keys %$resource_classes_hash; # put 'default' to the front
        my %seen_resource_name = ();
        foreach my $rc_id (@resource_classes_order) {
            my $mt2param = $resource_classes_hash->{$rc_id};

            my $rc_name = delete $mt2param->{-desc};
            if($rc_id!~/^\d+$/) {
                $rc_name  = $rc_id;
                $rc_id = undef;
            }

            if(!$rc_name or $seen_resource_name{lc($rc_name)}++) {
                die "Every resource has to have a unique description, please fix the PipeConfig file";
            }

            my $rc = $resource_class_adaptor->create_new(
                defined($rc_id) ? (-DBID   => $rc_id) : (),
                -NAME   => $rc_name,
            );
            $rc_id = $rc->dbID();

            warn "Creating resource_class $rc_name($rc_id).\n";

            while( my($meadow_type, $xparams) = each %$mt2param ) {
                $resource_description_adaptor->create_new(
                    -RESOURCE_CLASS_ID  => $rc_id,
                    -MEADOW_TYPE        => $meadow_type,
                    -PARAMETERS         => $xparams,
                );
            }
        }
        unless($seen_resource_name{'default'}) {
            warn "\tNB:You don't seem to have 'default' as one of the resource classes (forgot to inherit from SUPER::resource_classes ?) - creating one for you\n";
            $resource_class_adaptor->create_new(-NAME => 'default');
        }
        warn "Done.\n\n";
    }

    my $analysis_adaptor             = $hive_dba->get_AnalysisAdaptor;
    my $analysis_stats_adaptor       = $hive_dba->get_AnalysisStatsAdaptor;

    my $valley = Bio::EnsEMBL::Hive::Valley->new( {}, 'LOCAL' );

    my %seen_logic_name = ();

    foreach my $aha (@{$self->pipeline_analyses}) {
        my ($logic_name, $module, $parameters_hash, $input_ids, $blocked, $batch_size, $hive_capacity, $failed_job_tolerance,
                $max_retry_count, $can_be_empty, $rc_id, $rc_name, $priority, $meadow_type, $analysis_capacity)
         = rearrange([qw(logic_name module parameters input_ids blocked batch_size hive_capacity failed_job_tolerance
                 max_retry_count can_be_empty rc_id rc_name priority meadow_type analysis_capacity)], %$aha);

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

            if($rc_id) {
                warn "(-rc_id => $rc_id) syntax is deprecated, please start using (-rc_name => 'your_resource_class_name')";
            } else {
                $rc_name ||= 'default';
                my $rc = $resource_class_adaptor->fetch_by_name($rc_name ) or die "Could not fetch resource with name '$rc_name', please check that resource_classes() method of your PipeConfig either contain it or inherit from the parent class";
                $rc_id = $rc->dbID();
            }

	    ## Module has to be compilable and accessible
            eval "require $module;";
            die "The module '$module' cannot be loaded.\n$@" if $@;
	    die "Problem accessing methods in '$module'. Please check that it inherits from Bio::EnsEMBL::Hive::Process and is named correctly.\n"
                unless($module->isa('Bio::EnsEMBL::Hive::Process'));

            if ($meadow_type and not exists $valley->available_meadow_hash()->{$meadow_type}) {
                die "The meadow '$meadow_type' is currently not registered (analysis '$logic_name')\n";
            }

            $analysis = Bio::EnsEMBL::Hive::Analysis->new(
                -logic_name             => $logic_name,
                -module                 => $module,
                -parameters             => stringify($parameters_hash || {}),    # have to stringify it here, because Analysis code is external wrt Hive code
                -resource_class_id      => $rc_id,
                -failed_job_tolerance   => $failed_job_tolerance,
                -max_retry_count        => $max_retry_count,
                -can_be_empty           => $can_be_empty,
                -priority               => $priority,
                -meadow_type            => $meadow_type,
                -analysis_capacity      => $analysis_capacity,
            );
            $analysis_adaptor->store($analysis);

            my $stats = Bio::EnsEMBL::Hive::AnalysisStats->new(
                -analysis_id            => $analysis->dbID,
                -batch_size             => $batch_size,
                -hive_capacity          => $hive_capacity,
                -status                 => $blocked ? 'BLOCKED' : 'EMPTY',  # be careful, as this "soft" way of blocking may be accidentally unblocked by deep sync
            );
            $analysis_stats_adaptor->store($stats);
        }

            # now create the corresponding jobs (if there are any):
        foreach my $input_id_hash (@{$input_ids || []}) {

            Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                -input_id       => $input_id_hash,  # input_ids are now centrally stringified in the AnalysisJobAdaptor
                -analysis       => $analysis,
                -prev_job_id    => undef, # these jobs are created by the initialization script, not by another job
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
                unless ($condition_url =~ m{^\w*://}) {
                    my $condition_analysis = $analysis_adaptor->fetch_by_logic_name($condition_url);
                    die "Could not fetch analysis '$condition_url' to create a control rule (in '".($analysis->logic_name)."')\n" unless defined $condition_analysis;
                }
                my $c_rule = Bio::EnsEMBL::Hive::AnalysisCtrlRule->new(
                        -condition_analysis_url => $condition_url,
                        -ctrled_analysis_id     => $analysis->dbID,
                );
                $ctrl_rule_adaptor->store( $c_rule, 1 );

                warn $c_rule->toString."\n";
            }

            $flow_into ||= {};
            $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

            my %group_tag_to_funnel_dataflow_rule_id = ();

            my $semaphore_sign = '->';

            my @all_branch_tags = keys %$flow_into;
            foreach my $branch_tag ((grep {/^[A-Z]$semaphore_sign/} @all_branch_tags), (grep {/$semaphore_sign[A-Z]$/} @all_branch_tags), (grep {!/$semaphore_sign/} @all_branch_tags)) {

                my ($branch_name_or_code, $group_role, $group_tag);

                if($branch_tag=~/^([A-Z])$semaphore_sign(-?\w+)$/) {
                    ($branch_name_or_code, $group_role, $group_tag) = ($2, 'funnel', $1);
                } elsif($branch_tag=~/^(-?\w+)$semaphore_sign([A-Z])$/) {
                    ($branch_name_or_code, $group_role, $group_tag) = ($1, 'fan', $2);
                } elsif($branch_tag=~/^(-?\w+)$/) {
                    ($branch_name_or_code, $group_role, $group_tag) = ($1, '');
                } elsif($branch_tag=~/:/) {
                    die "Please use newer '2${semaphore_sign}A' and 'A${semaphore_sign}1' notation instead of '2:1' and '1'\n";
                } else {
                    die "Error parsing the group tag '$branch_tag'\n";
                }

                my $funnel_dataflow_rule_id = undef;    # NULL by default

                if($group_role eq 'fan') {
                    unless($funnel_dataflow_rule_id = $group_tag_to_funnel_dataflow_rule_id{$group_tag}) {
                        die "No funnel dataflow_rule defined for group '$group_tag'\n";
                    }
                }

                my $heirs = $flow_into->{$branch_tag};
                $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first
                $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY'); # now force it into a hash if it wasn't

                while(my ($heir_url, $input_id_template_list) = each %$heirs) {

                    unless ($heir_url =~ m{^\w*://}) {
                        my $heir_analysis = $analysis_adaptor->fetch_by_logic_name($heir_url);
                        die "No analysis named '$heir_url' (dataflow from analysis '".($analysis->logic_name)."')\n" unless defined $heir_analysis;
                    }
                    
                    $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

                    foreach my $input_id_template (@$input_id_template_list) {

                        my $df_rule = Bio::EnsEMBL::Hive::DataflowRule->new(
                            -from_analysis              => $analysis,
                            -to_analysis_url            => $heir_url,
                            -branch_code                => $dataflow_rule_adaptor->branch_name_2_code( $branch_name_or_code ),
                            -input_id_template          => $input_id_template,
                            -funnel_dataflow_rule_id    => $funnel_dataflow_rule_id,
                        );
                        $dataflow_rule_adaptor->store( $df_rule, 1 );

                        warn $df_rule->toString."\n";

                        if($group_role eq 'funnel') {
                            if($group_tag_to_funnel_dataflow_rule_id{$group_tag}) {
                                die "More than one funnel dataflow_rule defined for group '$group_tag'\n";
                            } else {
                                $group_tag_to_funnel_dataflow_rule_id{$group_tag} = $df_rule->dbID();
                            }
                        }
                    } # /for all templates
                } # /for all heirs
            } # /for all branch_tags
        }
    }

    my $url = $self->dbconn_2_url('pipeline_db');

    print "\n\n# --------------------[Useful commands]--------------------------\n";
    print "\n";
    print " # It is convenient to store the pipeline url in a variable:\n";
    print "\texport HIVE_URL=$url\t\t\t# bash version\n";
    print "(OR)\n";
    print "\tsetenv HIVE_URL $url\t\t\t# [t]csh version\n";
    print "\n";
    print " # Add a new job to the pipeline (usually done once before running, but pipeline can be \"topped-up\" at any time) :\n";
    print "\tseed_pipeline.pl -url $url -logic_name <analysis_name> -input_id <param_hash>\n";
    print "\n";
    print " # Synchronize the Hive (should be done before [re]starting a pipeline) :\n";
    print "\tbeekeeper.pl -url $url -sync\n";
    print "\n";
    print " # Run the pipeline (can be interrupted and restarted) :\n";
    print "\tbeekeeper.pl -url $url ".$self->beekeeper_extra_cmdline_options()." -loop\t\t# run in looped automatic mode (a scheduling step performed every minute)\n";
    print "(OR)\n";
    print "\tbeekeeper.pl -url $url ".$self->beekeeper_extra_cmdline_options()." -run \t\t# run one scheduling step of the pipeline and exit (useful for debugging/learning)\n";
    print "(OR)\n";
    print "\trunWorker.pl -url $url ".$self->beekeeper_extra_cmdline_options()."      \t\t# run exactly one Worker locally (useful for debugging/learning)\n";
    print "\n";
    print " # At any moment during or after execution you can request a pipeline diagram in an image file (desired format is set via extension) :\n";
    print "\tgenerate_graph.pl -url $url -out diagram.png\n";
    print "\n";
    print " # Peek into your pipeline database with a database client (useful to have open while the pipeline is running) :\n";
    print "\t".$self->db_connect_command('pipeline_db')."\n\n";
}

1;

