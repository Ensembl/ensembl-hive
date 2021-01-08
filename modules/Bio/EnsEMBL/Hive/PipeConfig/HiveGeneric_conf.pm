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

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

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

use Exporter 'import';
our @EXPORT = qw(WHEN ELSE INPUT_PLUS);

use Scalar::Util qw(looks_like_number);

use Bio::EnsEMBL::Hive;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'join_command_args', 'whoami');
use Bio::EnsEMBL::Hive::Utils::PCL;
use Bio::EnsEMBL::Hive::Utils::URL;
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
        'dbowner'               => $ENV{'EHIVE_USER'} || whoami() || $self->o('dbowner'),       # although it is very unlikely that the current user has no name

        'hive_use_triggers'                 => 0,       # there have been a few cases of big pipelines misbehaving with triggers on, let's keep the default off.
        'hive_use_param_stack'              => 0,       # do not reconstruct the calling stack of parameters by default (yet)
        'hive_auto_rebalance_semaphores'    => 0,       # do not attempt to rebalance semaphores periodically by default
        'hive_default_max_retry_count'      => 3,       # default value for the max_retry_count parameter of each analysis
        'hive_force_init'                   => 0,       # setting it to 1 will drop the database prior to creation (use with care!)
        'hive_no_init'                      => 0,       # setting it to 1 will skip pipeline_create_commands (useful for topping up)
        'hive_debug_init'                   => 0,       # setting it to 1 will make init_pipeline.pl tell everything it's doing

        'pipeline_name'                     => $self->default_pipeline_name(),

        'pipeline_db'   => {
            -driver => $self->o('hive_driver'),
            -host   => $self->o('host'),
            -port   => $self->o('port'),
            -user   => $self->o('user'),
            -pass   => $self->o('password'),
            -dbname => $self->o('dbowner').'_'.$self->o('pipeline_name'),
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
    my $second_pass     = $pipeline_url!~ /^#:subst/;

    my $parsed_url      = $second_pass && (Bio::EnsEMBL::Hive::Utils::URL::parse( $pipeline_url ) || die "Could not parse the '$pipeline_url' as the database URL");
    my $driver          = $second_pass ? $parsed_url->{'driver'} : '';
    my $hive_force_init = $self->o('hive_force_init');

    # Will insert two keys: "hive_all_base_tables" and "hive_all_views"
    my $hive_tables_sql = 'INSERT INTO hive_meta SELECT CONCAT("hive_all_", REPLACE(LOWER(TABLE_TYPE), " ", "_"), "s"), GROUP_CONCAT(TABLE_NAME) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = "%s" GROUP BY TABLE_TYPE';

    return [
            $hive_force_init ? $self->db_cmd('DROP DATABASE IF EXISTS') : (),
            $self->db_cmd('CREATE DATABASE'),

                # we got table definitions for all drivers:
            $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/tables.'.$driver,

                # auto-sync'ing triggers are off by default:
            $self->o('hive_use_triggers') ? ( $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/triggers.'.$driver ) : (),

                # FOREIGN KEY constraints cannot be defined in sqlite separately from table definitions, so they are off there:
                                             ($driver ne 'sqlite') ? ( $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/foreign_keys.sql' ) : (),

                # we got procedure definitions for all drivers:
            $self->db_cmd().' <'.$self->o('hive_root_dir').'/sql/procedures.'.$driver,

                # list of all tables and views (MySQL only)
            ($driver eq 'mysql' ? ($self->db_cmd(sprintf($hive_tables_sql, $parsed_url->{'dbname'}))) : ()),

                # when the database was created
            $self->db_cmd(q{INSERT INTO hive_meta (meta_key, meta_value) VALUES ('creation_timestamp', CURRENT_TIMESTAMP)}),
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
        'hive_sql_schema_version'           => Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version(),
        'hive_pipeline_name'                => $self->o('pipeline_name'),
        'hive_use_param_stack'              => $self->o('hive_use_param_stack'),
        'hive_auto_rebalance_semaphores'    => $self->o('hive_auto_rebalance_semaphores'),
        'hive_default_max_retry_count'      => $self->o('hive_default_max_retry_count'),
    };
}

sub pre_options {
    my $self = shift @_;

    return {
        'help!' => '',
        'pipeline_url' => '',
        'pipeline_name' => '',
    };
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
    $sql_command =~ s/'/'\\''/g if $sql_command;
    return "$db_cmd_path -url '$db_url'".($sql_command ? " -sql '$sql_command'" : '');
}


sub print_debug {
    my $self = shift;
    print @_ if $self->o('hive_debug_init');
}


sub process_pipeline_name {
    my ($self, $ppn) = @_;

    $ppn=~s/([[:lower:]])([[:upper:]])/${1}_${2}/g;   # CamelCase into Camel_Case
    $ppn=~s/[\s\/]/_/g;                               # remove all spaces and other annoying characters
    $ppn = lc($ppn);

    return $ppn;
}


sub default_pipeline_name {
    my $self            = shift @_;

    my  $dpn = ref($self);        # get the original class name
        $dpn=~s/^.*:://;          # trim the leading classpath prefix
        $dpn=~s/_conf$//;         # trim the optional _conf from the end

    return $dpn;
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
    $self->root()->{'pipeline_url'}     = $self->{'_extra_options'}{'pipeline_url'};

    my @use_cases = ( 'pipeline_wide_parameters', 'resource_classes', 'pipeline_analyses', 'beekeeper_extra_cmdline_options', 'hive_meta_table', 'print_debug' );
    if($include_pcc_use_case) {
        unshift @use_cases, 'overridable_pipeline_create_commands';
        push @use_cases, 'useful_commands_legend';
    }
    $self->use_cases( \@use_cases );

    $self->SUPER::process_options();

        # post-processing:
    $self->root()->{'pipeline_name'}            = $self->process_pipeline_name( $self->root()->{'pipeline_name'} );
    $self->root()->{'pipeline_db'}{'-dbname'} &&= $self->process_pipeline_name( $self->root()->{'pipeline_db'}{'-dbname'} );    # may be used to construct $self->pipeline_url()
}


sub overridable_pipeline_create_commands {
    my $self                        = shift @_;
    my $pipeline_create_commands    = $self->pipeline_create_commands();

    return $self->o('hive_no_init') ? [] : $pipeline_create_commands;
}


sub is_analysis_topup {
    my $self                        = shift @_;

    return $self->o('hive_no_init');
}


sub run_pipeline_create_commands {
    my $self            = shift @_;

    foreach my $cmd (@{$self->overridable_pipeline_create_commands}) {
        # We allow commands to be given as an arrayref, but we join the
        # array elements anyway
        (my $dummy,$cmd) = join_command_args($cmd);
        $self->print_debug( "$cmd\n" );
        if(my $retval = system($cmd)) {
            die "Return value = $retval, possibly an error running $cmd\n";
        }
    }
    $self->print_debug( "\n" );
}


=head2 add_objects_from_config

    Description : The method that uses the Hive/EnsEMBL API to actually create all the analyses, jobs, dataflow and control rules and resource descriptions.

    Caller      : init_pipeline.pl or any other script that will drive this module.

=cut

sub add_objects_from_config {
    my $self        = shift @_;
    my $pipeline    = shift @_;

    $self->print_debug( "Adding hive_meta table entries ...\n" );
    my $new_meta_entries = $self->hive_meta_table();
    while( my ($meta_key, $meta_value) = each %$new_meta_entries ) {
        $pipeline->add_new_or_update( 'MetaParameters', $self->o('hive_debug_init'),
            'meta_key'      => $meta_key,
            'meta_value'    => $meta_value,
        );
    }
    $self->print_debug( "Done.\n\n" );

    $self->print_debug( "Adding pipeline-wide parameters ...\n" );
    my $new_pwp_entries = $self->pipeline_wide_parameters();
    while( my ($param_name, $param_value) = each %$new_pwp_entries ) {
        $pipeline->add_new_or_update( 'PipelineWideParameters', $self->o('hive_debug_init'),
            'param_name'    => $param_name,
            'param_value'   => stringify($param_value),
        );
    }
    $self->print_debug( "Done.\n\n" );

    $self->print_debug( "Adding Resources ...\n" );
    my $resource_classes_hash = $self->resource_classes;
    unless( exists $resource_classes_hash->{'default'} ) {
        warn "\tNB:'default' resource class is not in the database (did you forget to inherit from SUPER::resource_classes ?) - creating it for you\n";
        $resource_classes_hash->{'default'} = {};
    }
    my @resource_classes_order = sort { ($b eq 'default') or -($a eq 'default') or ($a cmp $b) } keys %$resource_classes_hash; # put 'default' to the front
    my %cached_resource_classes = map {$_->name => $_} $pipeline->collection_of('ResourceClass')->list();
    foreach my $rc_name (@resource_classes_order) {
        if($rc_name=~/^\d+$/) {
            die "-rc_id syntax is no longer supported, please use the new resource notation (-rc_name)";
        }

        my ($resource_class) = $pipeline->add_new_or_update( 'ResourceClass',   # NB: add_new_or_update returns a list
            'name'  => $rc_name,
        );
        $cached_resource_classes{$rc_name} = $resource_class;

        while( my($meadow_type, $resource_param_list) = each %{ $resource_classes_hash->{$rc_name} } ) {
            $resource_param_list = [ $resource_param_list ] unless(ref($resource_param_list));  # expecting either a scalar or a 2-element array

            my ($resource_description) = $pipeline->add_new_or_update( 'ResourceDescription', $self->o('hive_debug_init'),   # NB: add_new_or_update returns a list
                'resource_class'        => $resource_class,
                'meadow_type'           => $meadow_type,
                'submission_cmd_args'   => $resource_param_list->[0],
                'worker_cmd_args'       => $resource_param_list->[1],
            );

        }
    }
    $self->print_debug( "Done.\n\n" );


    my $amh = Bio::EnsEMBL::Hive::Valley->new()->available_meadow_hash();

    my %seen_logic_name = ();
    my %analyses_by_logic_name = map {$_->logic_name => $_} $pipeline->collection_of('Analysis')->list();

    $self->print_debug( "Adding Analyses ...\n" );
    foreach my $aha (@{$self->pipeline_analyses}) {
        my %aha_copy = %$aha;
        my ($logic_name, $module, $parameters_hash, $comment, $tags, $input_ids, $blocked, $batch_size, $hive_capacity, $failed_job_tolerance,
                $max_retry_count, $can_be_empty, $rc_id, $rc_name, $priority, $meadow_type, $analysis_capacity, $language, $wait_for, $flow_into)
         = delete @aha_copy{qw(-logic_name -module -parameters -comment -tags -input_ids -blocked -batch_size -hive_capacity -failed_job_tolerance
                 -max_retry_count -can_be_empty -rc_id -rc_name -priority -meadow_type -analysis_capacity -language -wait_for -flow_into)};   # slicing a hash reference

         my @unparsed_attribs = keys %aha_copy;
         if(@unparsed_attribs) {
             die "Could not parse the following analysis attributes: ".join(', ',@unparsed_attribs);
         }

        if( not $logic_name ) {
            die "'-logic_name' must be defined in every analysis";
        } elsif( $logic_name =~ /[+\-\%\.,]/ ) {
            die "Characters + - % . , are no longer allowed to be a part of an Analysis name. Please rename Analysis '$logic_name' and try again.\n";
        } elsif( looks_like_number($logic_name) ) {
            die "Numeric Analysis names are not allowed because they may clash with dbIDs. Please rename Analysis '$logic_name' and try again.\n";
        }

        if($seen_logic_name{$logic_name}++) {
            die "an entry with -logic_name '$logic_name' appears at least twice in the same configuration file, probably a typo";
        }

        if($rc_id) {
            die "(-rc_id => $rc_id) syntax is deprecated, please use (-rc_name => 'your_resource_class_name')";
        }

        my $analysis = $analyses_by_logic_name{$logic_name};  # the analysis with this logic_name may have already been stored in the db
        my $stats;
        if( $analysis ) {

            warn "Skipping creation of already existing analysis '$logic_name'.\n";
            next;

        } else {

            $rc_name ||= 'default';
            my $resource_class = $cached_resource_classes{$rc_name}
                or die "Could not find local resource with name '$rc_name', please check that resource_classes() method of your PipeConfig either contains or inherits it from the parent class";

            if ($meadow_type and not exists $amh->{$meadow_type}) {
                warn "The meadow '$meadow_type' is currently not registered (analysis '$logic_name')\n";
            }

            $parameters_hash ||= {};    # in case nothing was given
            die "'-parameters' has to be a hash" unless(ref($parameters_hash) eq 'HASH');

            ($analysis) = $pipeline->add_new_or_update( 'Analysis', $self->o('hive_debug_init'),   # NB: add_new_or_update returns a list
                'logic_name'            => $logic_name,
                'module'                => $module,
                'language'              => $language,
                'parameters'            => $parameters_hash,
                'comment'               => $comment,
                'tags'                  => ( (ref($tags) eq 'ARRAY') ? join(',', @$tags) : $tags ),
                'resource_class'        => $resource_class,
                'failed_job_tolerance'  => $failed_job_tolerance,
                'max_retry_count'       => $max_retry_count,
                'can_be_empty'          => $can_be_empty,
                'priority'              => $priority,
                'meadow_type'           => $meadow_type,
                'analysis_capacity'     => $analysis_capacity,
                'hive_capacity'         => $hive_capacity,
                'batch_size'            => $batch_size,
            );
            $analysis->get_compiled_module_name();  # check if it compiles and is named correctly

            ($stats) = $pipeline->add_new_or_update( 'AnalysisStats', $self->o('hive_debug_init'),   # NB: add_new_or_update returns a list
                'analysis'              => $analysis,
                'status'                => $blocked ? 'BLOCKED' : 'EMPTY',  # be careful, as this "soft" way of blocking may be accidentally unblocked by deep sync
                'total_job_count'       => 0,
                'semaphored_job_count'  => 0,
                'ready_job_count'       => 0,
                'done_job_count'        => 0,
                'failed_job_count'      => 0,
                'num_running_workers'   => 0,
                'sync_lock'             => 0,
            );
        }

            # Keep a link to the analysis object to speed up the creation of control and dataflow rules
        $analyses_by_logic_name{$logic_name} = $analysis;

            # now create the corresponding jobs (if there are any):
        if($input_ids) {
            push @{ $analysis->jobs_collection }, map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                'prev_job'      => undef,           # these jobs are created by the initialization script, not by another job
                'analysis'      => $analysis,
                'input_id'      => $_,              # input_ids are now centrally stringified in the AnalysisJob itself
            ) } @$input_ids;

            unless( $pipeline->hive_use_triggers() ) {
                $stats->recalculate_from_job_counts( { 'READY' => scalar(@$input_ids) } );
            }
        }
    }
    $self->print_debug( "Done.\n\n" );

    $self->print_debug( "Adding Control and Dataflow Rules ...\n" );
    foreach my $aha (@{$self->pipeline_analyses}) {

        my ($logic_name, $wait_for, $flow_into)
             = @{$aha}{qw(-logic_name -wait_for -flow_into)};   # slicing a hash reference

        my $analysis = $analyses_by_logic_name{$logic_name};

        if($wait_for) {
            Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($pipeline, $analysis, $wait_for, $self->o('hive_debug_init'));
        }

        if($flow_into) {
            Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis, $flow_into, $self->o('hive_debug_init'));
        }

    }
    $self->print_debug( "Done.\n\n" );

    # Block the analyses that should be blocked
    $self->print_debug( "Blocking the analyses that should be ...\n" );
    foreach my $stats ($pipeline->collection_of('AnalysisStats')->list()) {
        $stats->check_blocking_control_rules('no_die');
        $stats->determine_status();
    }
    $self->print_debug( "Done.\n\n" );
}


sub useful_commands_legend {
    my $self  = shift @_;

    my $pipeline_url = $self->pipeline_url();
    unless ($pipeline_url =~ /^[\'\"]/) {
        $pipeline_url   = '"' . $pipeline_url . '"';
    }
    my $pipeline_name   = $self->o('pipeline_name');
    my $extra_cmdline   = $self->beekeeper_extra_cmdline_options();

    my @output_lines = (
        '','',
        '# ' . '-' x 22 . '[Useful commands]' . '-' x 22,
        '',
        " # It is convenient to store the pipeline url in a variable:",
        "\texport EHIVE_URL=$pipeline_url\t\t\t# bash version",
        "(OR)",
        "\tsetenv EHIVE_URL $pipeline_url\t\t\t# [t]csh version",
        '',
        " # Add a new job to the pipeline (usually done once before running, but pipeline can be \"topped-up\" at any time) :",
        "\tseed_pipeline.pl -url $pipeline_url -logic_name <analysis_name> -input_id <param_hash>",
        '',
        " # At any moment during or after execution you can request a pipeline diagram in an image file (desired format is set via extension) :",
        "\tgenerate_graph.pl -url $pipeline_url -out $pipeline_name.png",
        '',
        " # Synchronize the Hive (to display fresh statistics about all analyses):",
        "\tbeekeeper.pl -url $pipeline_url -sync",
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
        " # Run the pipeline (can be interrupted and restarted) :",
        "\tbeekeeper.pl -url $pipeline_url $extra_cmdline -loop\t\t# run in looped automatic mode (a scheduling step performed every minute)",
        "(OR)",
        "\tbeekeeper.pl -url $pipeline_url $extra_cmdline -run \t\t# run one scheduling step of the pipeline and exit (useful for debugging/learning)",
        "(OR)",
        "\trunWorker.pl -url $pipeline_url $extra_cmdline      \t\t# run exactly one Worker locally (useful for debugging/learning)",
        '',
    );

    return join("\n", @output_lines);
}

1;

