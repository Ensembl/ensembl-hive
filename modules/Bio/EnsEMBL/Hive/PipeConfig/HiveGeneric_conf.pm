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

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive;
use Bio::EnsEMBL::Hive::Utils::Collection;
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisCtrlRule;
use Bio::EnsEMBL::Hive::DataflowRule;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::ResourceClass;
use Bio::EnsEMBL::Hive::ResourceDescription;
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
        'hive_root_dir'         => $ENV{'EHIVE_ROOT_DIR'},                                      # this value is set up automatically if this code is run by init_pipeline.pl

        'hive_driver'           => 'mysql',
        'host'                  => $ENV{'EHIVE_HOST'} || 'localhost',                           # BEWARE that 'localhost' for mysql driver usually means a UNIX socket, not a TCPIP socket!
                                                                                                # If you need to connect to TCPIP socket, set  -host => '127.0.0.1' instead.

        'port'                  => $ENV{'EHIVE_PORT'},                                          # or remain undef, which means default for the driver
        'user'                  => $ENV{'EHIVE_USER'} // $self->o('user'),
        'password'              => $ENV{'EHIVE_PASS'} // $self->o('password'),                  # people will have to make an effort NOT to insert it into config files like .bashrc etc
        'dbowner'               => $ENV{'EHIVE_USER'} || $ENV{'USER'} || $self->o('dbowner'),   # although it is very unlikely $ENV{USER} is not set
        'pipeline_name'         => $self->pipeline_name(),

        'hive_use_triggers'     => 0,                   # there have been a few cases of big pipelines misbehaving with triggers on, let's keep the default off.
        'hive_use_param_stack'  => 0,                   # do not reconstruct the calling stack of parameters by default (yet)
        'hive_force_init'       => 0,                   # setting it to 1 will drop the database prior to creation (use with care!)
        'hive_no_init'          => 0,                   # setting it to 1 will skip pipeline_create_commands (useful for topping up)

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
    my $hive_force_init = $self->o('hive_force_init');

    return [
            $hive_force_init ? $self->db_cmd('DROP DATABASE IF EXISTS') : (),
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
        # 'variable1'   => 'value1',
        # 'variable2'   => 'value2',
    };
}


=head2 resource_classes

    Description : Interface method that should return a hash of resource_description_id->resource_description_hash.
                  Please see existing PipeConfig modules for examples.

=cut

sub resource_classes {
    my ($self) = @_;
    return {
## No longer supported resource declaration syntax:
#        1 => { -desc => 'default',  'LSF' => '' },
#        2 => { -desc => 'urgent',   'LSF' => '-q yesterday' },
## Currently supported resource declaration syntax:
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
        'pipeline_url' => '',
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
          .'--password="'.$self->o($db_conn,'-pass').'" '
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
    my ($self, $include_pcc_use_case) = @_;

        # pre-patch definitely_used_options:
    $self->{'_extra_options'} = $self->load_cmdline_options( $self->pre_options() );
    $self->root()->{'pipeline_url'} = $self->{'_extra_options'}{'pipeline_url'};

    my @use_cases = ( 'pipeline_wide_parameters', 'resource_classes', 'pipeline_analyses', 'beekeeper_extra_cmdline_options', 'hive_meta_table' );
    if($include_pcc_use_case) {
        unshift @use_cases, 'overridable_pipeline_create_commands';
        push @use_cases, 'useful_commands_legend';
    }
    $self->use_cases( \@use_cases );

    return $self->SUPER::process_options();
}


sub overridable_pipeline_create_commands {
    my $self                        = shift @_;
    my $pipeline_create_commands    = $self->pipeline_create_commands();

    return $self->o('hive_no_init') ? [] : $pipeline_create_commands;
}


sub run_pipeline_create_commands {
    my $self            = shift @_;

    foreach my $cmd (@{$self->overridable_pipeline_create_commands}) {
        warn "Running the command:\n\t$cmd\n";
        if(my $retval = system($cmd)) {
            die "Return value = $retval, possibly an error\n";
        } else {
            warn "Done.\n\n";
        }
    }
}


=head2 add_objects_from_config

    Description : The method that uses the Hive/EnsEMBL API to actually create all the analyses, jobs, dataflow and control rules and resource descriptions.

    Caller      : init_pipeline.pl or any other script that will drive this module.

=cut

sub add_objects_from_config {
    my $self                = shift @_;

    warn "Adding hive_meta table entries ...\n";
    my $new_meta_entries = $self->hive_meta_table();
    while( my ($meta_key, $meta_value) = each %$new_meta_entries ) {
        Bio::EnsEMBL::Hive::MetaParameters->add_new_or_update(
            'meta_key'      => $meta_key,
            'meta_value'    => $meta_value,
        );
    }
    warn "Done.\n\n";

    warn "Adding pipeline-wide parameters ...\n";
    my $new_pwp_entries = $self->pipeline_wide_parameters();
    while( my ($param_name, $param_value) = each %$new_pwp_entries ) {
        Bio::EnsEMBL::Hive::PipelineWideParameters->add_new_or_update(
            'param_name'    => $param_name,
            'param_value'   => $param_value,
        );
    }
    warn "Done.\n\n";

    warn "Adding Resources ...\n";
    my $resource_classes_hash = $self->resource_classes;
    unless( exists $resource_classes_hash->{'default'} ) {
        warn "\tNB:'default' resource class is not in the database (did you forget to inherit from SUPER::resource_classes ?) - creating it for you\n";
        $resource_classes_hash->{'default'} = {};
    }
    my @resource_classes_order = sort { ($b eq 'default') or -($a eq 'default') or ($a cmp $b) } keys %$resource_classes_hash; # put 'default' to the front
    foreach my $rc_name (@resource_classes_order) {
        if($rc_name=~/^\d+$/) {
            die "-rc_id syntax is no longer supported, please use the new resource notation (-rc_name)";
        }

        my $resource_class = Bio::EnsEMBL::Hive::ResourceClass->add_new_or_update(
            'name'  => $rc_name,
        );

        while( my($meadow_type, $resource_param_list) = each %{ $resource_classes_hash->{$rc_name} } ) {
            $resource_param_list = [ $resource_param_list ] unless(ref($resource_param_list));  # expecting either a scalar or a 2-element array

            my $resource_description = Bio::EnsEMBL::Hive::ResourceDescription->add_new_or_update(
                'resource_class'        => $resource_class,
                'meadow_type'           => $meadow_type,
                'submission_cmd_args'   => $resource_param_list->[0],
                'worker_cmd_args'       => $resource_param_list->[1],
            );

        }
    }
    warn "Done.\n\n";


    my $valley = Bio::EnsEMBL::Hive::Valley->new( {}, 'LOCAL' );

    my %seen_logic_name = ();

    warn "Adding Analyses ...\n";
    foreach my $aha (@{$self->pipeline_analyses}) {
        my ($logic_name, $module, $parameters_hash, $input_ids, $blocked, $batch_size, $hive_capacity, $failed_job_tolerance,
                $max_retry_count, $can_be_empty, $rc_id, $rc_name, $priority, $meadow_type, $analysis_capacity)
         = @{$aha}{qw(-logic_name -module -parameters -input_ids -blocked -batch_size -hive_capacity -failed_job_tolerance
                 -max_retry_count -can_be_empty -rc_id -rc_name -priority -meadow_type -analysis_capacity)};   # slicing a hash reference

        unless($logic_name) {
            die "logic_name' must be defined in every analysis";
        }

        if($seen_logic_name{$logic_name}++) {
            die "an entry with logic_name '$logic_name' appears at least twice in the same configuration file, probably a typo";
        }

        if($rc_id) {
            die "(-rc_id => $rc_id) syntax is deprecated, please use (-rc_name => 'your_resource_class_name')";
        }

        my $analysis = Bio::EnsEMBL::Hive::Analysis->collection()->find_one_by('logic_name', $logic_name);  # the analysis with this logic_name may have already been stored in the db
        my $stats;
        if( $analysis ) {

            warn "Skipping creation of already existing analysis '$logic_name'.\n";
            next;

        } else {

            $rc_name ||= 'default';
            my $resource_class = Bio::EnsEMBL::Hive::ResourceClass->collection()->find_one_by('name', $rc_name)
                or die "Could not find local resource with name '$rc_name', please check that resource_classes() method of your PipeConfig either contains or inherits it from the parent class";

            if ($meadow_type and not exists $valley->available_meadow_hash()->{$meadow_type}) {
                die "The meadow '$meadow_type' is currently not registered (analysis '$logic_name')\n";
            }

            $parameters_hash ||= {};    # in case nothing was given
            die "'-parameters' has to be a hash" unless(ref($parameters_hash) eq 'HASH');

            $analysis = Bio::EnsEMBL::Hive::Analysis->add_new_or_update(
                'logic_name'            => $logic_name,
                'module'                => $module,
                'parameters'            => $parameters_hash,
                'resource_class'        => $resource_class,
                'failed_job_tolerance'  => $failed_job_tolerance,
                'max_retry_count'       => $max_retry_count,
                'can_be_empty'          => $can_be_empty,
                'priority'              => $priority,
                'meadow_type'           => $meadow_type,
                'analysis_capacity'     => $analysis_capacity,
            );
            $analysis->get_compiled_module_name();  # check if it compiles and is named correctly

            $stats = Bio::EnsEMBL::Hive::AnalysisStats->add_new_or_update(
                'analysis'              => $analysis,
                'batch_size'            => $batch_size,
                'hive_capacity'         => $hive_capacity,
                'status'                => $blocked ? 'BLOCKED' : 'EMPTY',  # be careful, as this "soft" way of blocking may be accidentally unblocked by deep sync
                'total_job_count'       => 0,
                'semaphored_job_count'  => 0,
                'ready_job_count'       => 0,
                'done_job_count'        => 0,
                'failed_job_count'      => 0,
                'num_running_workers'   => 0,
                'num_required_workers'  => 0,
                'behaviour'             => 'STATIC',
                'input_capacity'        => 4,
                'output_capacity'       => 4,
                'sync_lock'             => 0,
            );
        }

            # now create the corresponding jobs (if there are any):
        if($input_ids) {
            push @{ $analysis->jobs_collection }, map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                'prev_job'      => undef,           # these jobs are created by the initialization script, not by another job
                'analysis'      => $analysis,
                'input_id'      => $_,              # input_ids are now centrally stringified in the AnalysisJob itself
            ) } @$input_ids;

            $stats->recalculate_from_job_counts( { 'READY' => scalar(@$input_ids) } );
        }
    }
    warn "Done.\n\n";

    warn "Adding Control and Dataflow Rules ...\n";
    foreach my $aha (@{$self->pipeline_analyses}) {
        my ($logic_name, $wait_for, $flow_into)
             = @{$aha}{qw(-logic_name -wait_for -flow_into)};   # slicing a hash reference

        my $analysis = Bio::EnsEMBL::Hive::Analysis->collection()->find_one_by('logic_name', $logic_name);

        $wait_for ||= [];
        $wait_for   = [ $wait_for ] unless(ref($wait_for) eq 'ARRAY'); # force scalar into an arrayref

            # create control rules:
        foreach my $condition_url (@$wait_for) {
            unless ($condition_url =~ m{^\w*://}) {
                my $condition_analysis = Bio::EnsEMBL::Hive::Analysis->collection()->find_one_by('logic_name', $condition_url)
                    or die "Could not find a local analysis '$condition_url' to create a control rule (in '".($analysis->logic_name)."')\n";
            }
            my $c_rule = Bio::EnsEMBL::Hive::AnalysisCtrlRule->add_new_or_update(
                    'condition_analysis_url'    => $condition_url,
                    'ctrled_analysis'           => $analysis,
            );
        }

        $flow_into ||= {};
        $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

        my %group_tag_to_funnel_dataflow_rule = ();

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

            my $funnel_dataflow_rule = undef;    # NULL by default

            if($group_role eq 'fan') {
                unless($funnel_dataflow_rule = $group_tag_to_funnel_dataflow_rule{$group_tag}) {
                    die "No funnel dataflow_rule defined for group '$group_tag'\n";
                }
            }

            my $heirs = $flow_into->{$branch_tag};
            $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first
            $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY'); # now force it into a hash if it wasn't

            while(my ($heir_url, $input_id_template_list) = each %$heirs) {

                unless ($heir_url =~ m{^\w*://}) {
                    my $heir_analysis = Bio::EnsEMBL::Hive::Analysis->collection()->find_one_by('logic_name', $heir_url)
                        or die "Could not find a local analysis named '$heir_url' (dataflow from analysis '".($analysis->logic_name)."')\n";
                }

                $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

                foreach my $input_id_template (@$input_id_template_list) {

                    my $df_rule = Bio::EnsEMBL::Hive::DataflowRule->add_new_or_update(
                        'from_analysis'             => $analysis,
                        'to_analysis_url'           => $heir_url,
                        'branch_code'               => $branch_name_or_code,
                        'funnel_dataflow_rule'      => $funnel_dataflow_rule,
                        'input_id_template'         => $input_id_template,
                    );

                    if($group_role eq 'funnel') {
                        if($group_tag_to_funnel_dataflow_rule{$group_tag}) {
                            die "More than one funnel dataflow_rule defined for group '$group_tag'\n";
                        } else {
                            $group_tag_to_funnel_dataflow_rule{$group_tag} = $df_rule;
                        }
                    }
                } # /for all templates
            } # /for all heirs
        } # /for all branch_tags
    } # /for all pipeline_analyses
    warn "Done.\n\n";
}


sub useful_commands_legend {
    my $self  = shift @_;

    my $pipeline_url    = $self->pipeline_url();
    my $pipeline_name   = $self->o('pipeline_name');
    my $extra_cmdline   = $self->beekeeper_extra_cmdline_options();

    my @output_lines = (
        '','',
        "# --------------------[Useful commands]--------------------------",
        '',
        " # It is convenient to store the pipeline url in a variable:",
        "\texport EHIVE_URL=$pipeline_url\t\t\t# bash version",
        "(OR)",
        "\tsetenv EHIVE_URL $pipeline_url\t\t\t# [t]csh version",
        '',
        " # Add a new job to the pipeline (usually done once before running, but pipeline can be \"topped-up\" at any time) :",
        "\tseed_pipeline.pl -url $pipeline_url -logic_name <analysis_name> -input_id <param_hash>",
        '',
        " # Synchronize the Hive (should be done before [re]starting a pipeline) :",
        "\tbeekeeper.pl -url $pipeline_url -sync",
        '',
        " # Run the pipeline (can be interrupted and restarted) :",
        "\tbeekeeper.pl -url $pipeline_url $extra_cmdline -loop\t\t# run in looped automatic mode (a scheduling step performed every minute)",
        "(OR)",
        "\tbeekeeper.pl -url $pipeline_url $extra_cmdline -run \t\t# run one scheduling step of the pipeline and exit (useful for debugging/learning)",
        "(OR)",
        "\trunWorker.pl -url $pipeline_url $extra_cmdline      \t\t# run exactly one Worker locally (useful for debugging/learning)",
        '',
        " # At any moment during or after execution you can request a pipeline diagram in an image file (desired format is set via extension) :",
        "\tgenerate_graph.pl -url $pipeline_url -out $pipeline_name.png",
        '',
        " # Depending on the Meadow the pipeline is running on, you may be able to collect actual resource usage statistics :",
        "\tload_resource_usage.pl -url $pipeline_url",
        '',
        " # After having run load_resource_usage.pl, you can request a resource usage timeline in an image file (desired format is set via extension) :",
        "\tgenerate_timeline.pl -url $pipeline_url -out timeline_$pipeline_name.png",
        '',
        " # Peek into your pipeline database with a database client (useful to have open while the pipeline is running) :",
        "\tdb_cmd.pl -url $pipeline_url",
        '',
    );

    return join("\n", @output_lines);
}

1;

