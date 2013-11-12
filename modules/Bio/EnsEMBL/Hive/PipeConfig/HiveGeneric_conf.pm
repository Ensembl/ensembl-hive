
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf

=head1 SYNOPSIS

    # Example 1: specifying only the mandatory option:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <mypass>

    # Example 2: specifying the mandatory options as well as overriding some defaults:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -host <myhost> -dbname <mydbname> -password <mypass>

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

use Bio::EnsEMBL::ApiVersion ();

use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;
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
            # Please note: ENVironment variables may be "exported" to inherit from enclosing shell,
            # but if you want to *prevent* that you need to specifically say so
            #  (setting a password to empty string does exactly that - sets it to an empty string)
            #
            #   [bash]      export -n ENSEMBL_CVS_ROOT_DIR  # will stop exporting, but the value in current shell stays as it was
            #   [tcsh]      unsetenv ENSEMBL_CVS_ROOT_DIR   # will destroy the variable even in current shell, and stop exporting

        'ensembl_cvs_root_dir'  => $ENV{'ENSEMBL_CVS_ROOT_DIR'} || $self->o('ensembl_cvs_root_dir'),    # it will make sense to set this variable if you are going to use ehive with ensembl
        'ensembl_release'       => Bio::EnsEMBL::ApiVersion::software_version(),                        # snapshot of EnsEMBL Core API version. Please do not change if not sure.

        'hive_root_dir'         => $ENV{'EHIVE_ROOT_DIR'}                                               # this value is set up automatically if this code is run by init_pipeline.pl
                                    || $self->o('ensembl_cvs_root_dir').'/ensembl-hive',                # otherwise we have to rely on other means

        'hive_driver'           => 'mysql',
        'host'                  => $ENV{'EHIVE_HOST'} || 'localhost',                                   # BEWARE that 'localhost' for mysql driver usually means a UNIX socket, not a TCPIP socket!
                                                                                                        # If you need to connect to TCPIP socket, set  -host => '127.0.0.1' instead.

        'port'                  => $ENV{'EHIVE_PORT'},                                                  # or remain undef, which means default for the driver
        'user'                  => $ENV{'EHIVE_USER'} || 'ensadmin',
        'password'              => $ENV{'EHIVE_PASS'} // $ENV{'ENSADMIN_PSW'} // $self->o('password'),  # people will have to make an effort NOT to insert it into config files like .bashrc etc
        'dbowner'               => $ENV{'EHIVE_USER'} || $ENV{'USER'}         || $self->o('dbowner'),   # although it is very unlikely $ENV{USER} is not set
        'pipeline_name'         => $self->pipeline_name(),

        'hive_use_triggers'     => 0,                   # there have been a few cases of big pipelines misbehaving with triggers on, let's keep the default off.
        'hive_use_param_stack'  => 0,                   # do not reconstruct the calling stack of parameters by default (yet)
        'hive_force_init'       => 0,                   # setting it to 1 will drop the database prior to creation (use with care!)

        'pipeline_db'   => {
            -driver => $self->o('hive_driver'),
            -host   => $self->o('host'),
            -port   => $self->o('port'),
            -user   => $self->o('user'),
            -pass   => $self->o('password'),
            -dbname => $self->o('dbowner').'_'.$self->o('pipeline_name'),  # example of a linked definition (resolved via saturation)
        },
    };
}


=head2 pipeline_create_commands

    Description : Interface method that should return a list of command lines to be run in order to create and set up the pipeline database.
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_create_commands {
    my $self    = shift @_;

    my $pipeline_url    = $self->pipeline_url();
    my $parsed_url      = Bio::EnsEMBL::Hive::Utils::URL::parse( $pipeline_url );
    my $driver          = $parsed_url ? $parsed_url->{'driver'} : '';

    return [
            $self->o('hive_force_init') ? $self->db_cmd('DROP DATABASE IF EXISTS') : (),
            $self->db_cmd('CREATE DATABASE'),

                # we got table definitions for all drivers:
            $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/tables.'.$driver,

                # auto-sync'ing triggers are off by default and not yet available in pgsql:
            $self->o('hive_use_triggers') && ($driver ne 'pgsql')  ? ( $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/triggers.'.$driver ) : (),

                # FOREIGN KEY constraints cannot be defined in sqlite separately from table definitions, so they are off there:
                                             ($driver ne 'sqlite') ? ( $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/foreign_keys.sql' ) : (),

                # we got procedure definitions for all drivers:
            $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/procedures.'.$driver,
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
        'schema_version' => $self->o('ensembl_release'),    # keep compatibility with core API
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


sub hive_meta_table {
    my ($self) = @_;

    return {
        'hive_sql_schema_version'   => Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version(),
        'hive_pipeline_name'        => $self->o('pipeline_name'),
        'hive_use_param_stack'      => $self->o('hive_use_param_stack'),
    };
}

sub pre_options {
    my $self = shift @_;

    return {
        'help!' => '',
        'job_topup!' => '',
        'analysis_topup!' => '',
        'pipeline_url' => '',
#        'hive_use_triggers' => '',
    };
}


=head2 dbconn_2_mysql

    Description : Deprecated method. Please use $self->db_cmd() instead.

=cut

sub dbconn_2_mysql {    # will save you a lot of typing
    my ($self, $db_conn, $with_db) = @_;

    warn "\nDEPRECATED: dbconn_2_mysql() method is no longer supported, please call db_cmd(\$sql_command) instead, it will be more portable\n\n";

    my $port = $self->o($db_conn,'-port');

    return '--host='.$self->o($db_conn,'-host').' '
          .($port ? '--port='.$self->o($db_conn,'-port').' ' : '')
          .'--user="'.$self->o($db_conn,'-user').'" '
          .'--pass="'.$self->o($db_conn,'-pass').'" '
          .($with_db ? ($self->o($db_conn,'-dbname').' ') : '');
}


=head2 dbconn_2_pgsql

    Description : Deprecated method. Please use $self->db_cmd() instead.

=cut

sub dbconn_2_pgsql {    # will save you a lot of typing
    my ($self, $db_conn, $with_db) = @_;

    warn "\nDEPRECATED: dbconn_2_pgsql() method is no longer supported, please call db_cmd(\$sql_command) instead, it will be more portable\n\n";

    my $port = $self->o($db_conn,'-port');

    return '--host='.$self->o($db_conn,'-host').' '
          .($port ? '--port='.$self->o($db_conn,'-port').' ' : '')
          .'--username="'.$self->o($db_conn,'-user').'" '
          .($with_db ? ($self->o($db_conn,'-dbname').' ') : '');
}

=head2 db_connect_command

    Description : Deprecated method. Please use $self->db_cmd() instead.

=cut

sub db_connect_command {
    my ($self, $db_conn) = @_;

    warn "\nDEPRECATED: db_connect_command() method is no longer supported, please call db_cmd(\$sql_command) instead, it will be more portable\n\n";

    my $driver = $self->o($db_conn, '-driver');

    return {
        'sqlite'    => 'sqlite3 '.$self->o($db_conn, '-dbname'),
        'mysql'     => 'mysql '.$self->dbconn_2_mysql($db_conn, 1),
        'pgsql'     => "env PGPASSWORD='".$self->o($db_conn,'-pass')."' psql ".$self->dbconn_2_pgsql($db_conn, 1),
    }->{ $driver };
}


=head2 db_execute_command

    Description : Deprecated method. Please use $self->db_cmd() instead.

=cut

sub db_execute_command {
    my ($self, $db_conn, $sql_command, $with_db) = @_;

    warn "\nDEPRECATED: db_execute_command() method is no longer supported, please call db_cmd(\$sql_command) instead, it will be more portable\n\n";

    $with_db = 1 unless(defined($with_db));

    my $driver = $self->o($db_conn, '-driver');

    if(($driver eq 'sqlite') && !$with_db) {    # in these special cases we pretend sqlite can understand these commands
        return "rm -f $1" if($sql_command=~/DROP\s+DATABASE\s+(?:IF\s+EXISTS\s+)?(\w+)/);
        return "touch $1" if($sql_command=~/CREATE\s+DATABASE\s+(\w+)/);
    } else {
        return {
            'sqlite'    => 'sqlite3 '.$self->o($db_conn, '-dbname')." '$sql_command'",
            'mysql'     => 'mysql '.$self->dbconn_2_mysql($db_conn, $with_db)." -e '$sql_command'",
            'pgsql'     => "env PGPASSWORD='".$self->o($db_conn,'-pass')."' psql --command='$sql_command' ".$self->dbconn_2_pgsql($db_conn, $with_db),
        }->{ $driver };
    }
}


=head2 dbconn_2_url

    Description :  A convenience method used to stringify a connection-parameters hash into a 'pipeline_url' that beekeeper.pl will undestand

=cut

sub dbconn_2_url {
    my ($self, $db_conn, $with_db) = @_;

    $with_db = 1 unless(defined($with_db));

    my $driver = $self->o($db_conn, '-driver');
    my $port   = $self->o($db_conn,'-port');

    return (    ($driver eq 'sqlite')
            ? $driver.':///'
            : $driver.'://'.$self->o($db_conn,'-user').':'.$self->o($db_conn,'-pass').'@'.$self->o($db_conn,'-host').($port ? ':'.$port : '').'/'
           ) . ($with_db ? $self->o($db_conn,'-dbname') : '');
}


sub pipeline_url {
    my $self = shift @_;

    return $self->root()->{'pipeline_url'} || $self->dbconn_2_url('pipeline_db', 1); # used to force vivification of the whole 'pipeline_db' structure (used in run() )
}


=head2 db_cmd

    Description :  Returns a db_cmd.pl-based command line that should execute by any supported driver (mysql/pgsql/sqlite)

=cut

sub db_cmd {
    my ($self, $sql_command, $db_url) = @_;

    $db_url //= $self->pipeline_url();
    my $db_cmd_path = $self->o('hive_root_dir').'/scripts/db_cmd.pl';

    return "$db_cmd_path -url $db_url".($sql_command ? " -sql '$sql_command'" : '');
}


sub pipeline_name {
    my $self            = shift @_;
    my $pipeline_name   = shift @_;

    unless($pipeline_name) {    # or turn the ClassName into pipeline_name:
        $pipeline_name = ref($self);        # get the original class name
        $pipeline_name=~s/^.*:://;          # trim the leading classpath prefix
        $pipeline_name=~s/_conf$//;         # trim the optional _conf from the end
    }

    $pipeline_name=~s/([[:lower:]])([[:upper:]])/${1}_${2}/g;   # CamelCase into Camel_Case

    return lc($pipeline_name);
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
    $self->root()->{'pipeline_url'} = $self->{'_extra_options'}{'pipeline_url'};

    $self->use_cases( [ 'pipeline_create_commands', 'pipeline_wide_parameters', 'resource_classes', 'pipeline_analyses', 'beekeeper_extra_cmdline_options', 'pipeline_url', 'hive_meta_table' ] );
    return $self->SUPER::process_options();
}


=head2 run

    Description : The method that uses the Hive/EnsEMBL API to actually create all the analyses, jobs, dataflow and control rules and resource descriptions.

    Caller      : init_pipeline.pl or any other script that will drive this module.

=cut

sub run {
    my $self  = shift @_;
    my $analysis_topup  = $self->{'_extra_options'}{'analysis_topup'};
    my $job_topup       = $self->{'_extra_options'}{'job_topup'};
    my $pipeline_url    = $self->pipeline_url();
    my $pipeline_name   = $self->o('pipeline_name');

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

    Bio::EnsEMBL::Registry->no_version_check(1);
    my $hive_dba                     = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url, -no_sql_schema_version_check => 1 );
    my $resource_class_adaptor       = $hive_dba->get_ResourceClassAdaptor;

    unless($job_topup) {
        my $meta_adaptor = $hive_dba->get_MetaAdaptor;      # the new adaptor for 'hive_meta' table
        warn "Loading hive_meta table ...\n";
        my $hive_meta_table = $self->hive_meta_table;
        while( my($meta_key, $meta_value) = each %$hive_meta_table ) {
            $meta_adaptor->store_pair( $meta_key, $meta_value );
        }

        my $meta_container = $hive_dba->get_MetaContainer;  # adaptor over core's 'meta' table for compatibility with core API
        warn "Loading pipeline-wide parameters ...\n";

        my $pipeline_wide_parameters = $self->pipeline_wide_parameters;
        while( my($meta_key, $meta_value) = each %$pipeline_wide_parameters ) {
            if($analysis_topup) {
                $meta_container->remove_all_by_meta_key($meta_key);
            }
            $meta_container->store_pair($meta_key, $meta_value);
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

            my ($rc, $rc_newly_created) = $resource_class_adaptor->create_new(
                defined($rc_id) ? (-DBID   => $rc_id) : (),
                -NAME   => $rc_name,
                1   # check whether this ResourceClass was already present in the database
            );
            $rc_id = $rc->dbID();

            if($rc_newly_created) {
                warn "Creating resource_class $rc_name($rc_id).\n";
            } else {
                warn "Attempt to re-create and potentially redefine resource_class $rc_name($rc_id). NB: This may affect already created analyses!\n";
            }

            while( my($meadow_type, $resource_param_list) = each %$mt2param ) {
                $resource_param_list = [ $resource_param_list ] unless(ref($resource_param_list));  # expecting either a scalar or a 2-element array

                $resource_description_adaptor->create_new(
                    -resource_class_id      => $rc_id,
                    -meadow_type            => $meadow_type,
                    -submission_cmd_args    => $resource_param_list->[0],
                    -worker_cmd_args        => $resource_param_list->[1],
                );
            }
        }
        unless(my $default_rc = $resource_class_adaptor->fetch_by_name('default')) {
            warn "\tNB:'default' resource class is not in the database (did you forget to inherit from SUPER::resource_classes ?) - creating it for you\n";
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
         = @{$aha}{qw(-logic_name -module -parameters -input_ids -blocked -batch_size -hive_capacity -failed_job_tolerance
                 -max_retry_count -can_be_empty -rc_id -rc_name -priority -meadow_type -analysis_capacity)};   # slicing a hash reference

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

            if ($meadow_type and not exists $valley->available_meadow_hash()->{$meadow_type}) {
                die "The meadow '$meadow_type' is currently not registered (analysis '$logic_name')\n";
            }

            $parameters_hash ||= {};    # in case nothing was given
            die "'-parameters' has to be a hash" unless(ref($parameters_hash) eq 'HASH');

            $analysis = Bio::EnsEMBL::Hive::Analysis->new(
                -logic_name             => $logic_name,
                -module                 => $module,
                -parameters             => stringify($parameters_hash),    # have to stringify it here, because Analysis code is external wrt Hive code
                -resource_class_id      => $rc_id,
                -failed_job_tolerance   => $failed_job_tolerance,
                -max_retry_count        => $max_retry_count,
                -can_be_empty           => $can_be_empty,
                -priority               => $priority,
                -meadow_type            => $meadow_type,
                -analysis_capacity      => $analysis_capacity,
            );
            $analysis->get_compiled_module_name();  # check if it compiles and is named correctly
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
            my ($logic_name, $wait_for, $flow_into)
                 = @{$aha}{qw(-logic_name -wait_for -flow_into)};   # slicing a hash reference

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

    print "\n\n# --------------------[Useful commands]--------------------------\n";
    print "\n";
    print " # It is convenient to store the pipeline url in a variable:\n";
    print "\texport EHIVE_URL=$pipeline_url\t\t\t# bash version\n";
    print "(OR)\n";
    print "\tsetenv EHIVE_URL $pipeline_url\t\t\t# [t]csh version\n";
    print "\n";
    print " # Add a new job to the pipeline (usually done once before running, but pipeline can be \"topped-up\" at any time) :\n";
    print "\tseed_pipeline.pl -url $pipeline_url -logic_name <analysis_name> -input_id <param_hash>\n";
    print "\n";
    print " # Synchronize the Hive (should be done before [re]starting a pipeline) :\n";
    print "\tbeekeeper.pl -url $pipeline_url -sync\n";
    print "\n";
    print " # Run the pipeline (can be interrupted and restarted) :\n";
    print "\tbeekeeper.pl -url $pipeline_url ".$self->beekeeper_extra_cmdline_options()." -loop\t\t# run in looped automatic mode (a scheduling step performed every minute)\n";
    print "(OR)\n";
    print "\tbeekeeper.pl -url $pipeline_url ".$self->beekeeper_extra_cmdline_options()." -run \t\t# run one scheduling step of the pipeline and exit (useful for debugging/learning)\n";
    print "(OR)\n";
    print "\trunWorker.pl -url $pipeline_url ".$self->beekeeper_extra_cmdline_options()."      \t\t# run exactly one Worker locally (useful for debugging/learning)\n";
    print "\n";
    print " # At any moment during or after execution you can request a pipeline diagram in an image file (desired format is set via extension) :\n";
    print "\tgenerate_graph.pl -url $pipeline_url -out $pipeline_name.png\n";
    print "\n";
    print " # Peek into your pipeline database with a database client (useful to have open while the pipeline is running) :\n";
    print "\tdb_cmd.pl -url $pipeline_url\n\n";
}

1;

