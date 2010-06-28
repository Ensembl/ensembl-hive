
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

    * default_options:              returns a hash of (possibly multilevel) defaults for the options on which depend the rest of the configuration

    * pipeline_create_commands:     returns a list of strings that will be executed as system commands needed to create and set up the pipeline database

    * pipeline_wide_parameters:     returns a hash of pipeline-wide parameter names and their values

    * resource_classes:             returns a hash of resource class definitions

    * pipeline_analyses:            returns a list of hash structures that define analysis objects bundled with definitions of corresponding jobs, rules and resources

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
use Getopt::Long;
use Bio::EnsEMBL::Utils::Argument;          # import 'rearrange()'
use Bio::EnsEMBL::Hive::Utils 'stringify';  # import 'stringify()'
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::Extensions;

# ---------------------------[the following methods will be overridden by specific pipelines]-------------------------

=head2 default_options

    Description : Interface method that should return a hash of option_name->default_option_value pairs.
                  Please see existing PipeConfig modules for examples.

=cut

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'hive_generic',

        'pipeline_db'   => {
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => $ENV{'USER'}.'_'.$self->o('pipeline_name'),  # example of a linked definition (resolved via saturation)
        },
    };
}

=head2 pipeline_create_commands

    Description : Interface method that should return a list of command lines to be run in order to create and set up the pipeline database.
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 0)." -e 'CREATE DATABASE ".$self->o('pipeline_db', '-dbname')."'",

            # standard eHive tables and procedures:
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/tables.sql',
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/procedures.sql',
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


# ---------------------------------[now comes the interfacing stuff - feel free to call but not to modify]--------------------

my $undef_const = '-=[UnDeFiNeD_VaLuE]=-';  # we don't use undef, as it cannot be detected as a part of a string

=head2 new

    Description : Just a trivial constructor for this type of objects.
    Caller      : init_pipeline.pl or any other script that will drive this module.

=cut

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;

    return $self;
}

=head2 o

    Description : This is the method you call in the interface methods when you need to substitute an option: $self->o('password') .
                  To reach down several levels of a multilevel option (such as $self->('pipeline_db') ) just list the keys down the desired path: $self->o('pipeline', '-user') .

=cut

sub o {                 # descends the option hash structure (vivifying all encountered nodes) and returns the value if found
    my $self = shift @_;

    my $value = $self->{_pipe_option} ||= {};

    while(defined(my $option_syll = shift @_)) {

        if(exists($value->{$option_syll})
        and ((ref($value->{$option_syll}) eq 'HASH') or _completely_defined($value->{$option_syll}))
        ) {
            $value = $value->{$option_syll};            # just descend one level
        } elsif(@_) {
            $value = $value->{$option_syll} = {};       # force intermediate level vivification
        } else {
            $value = $value->{$option_syll} = $undef_const;    # force leaf level vivification
        }
    }
    return $value;
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

=head2 dbconn_2_url

    Description :  A convenience method used to stringify a connection-parameters hash into a 'url' that beekeeper.pl will undestand

=cut

sub dbconn_2_url {
    my ($self, $db_conn) = @_;

    return 'mysql://'.$self->o($db_conn,'-user').':'.$self->o($db_conn,'-pass').'@'.$self->o($db_conn,'-host').':'.$self->o($db_conn,'-port').'/'.$self->o($db_conn,'-dbname');
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
    my $self            = shift @_;

        # first, vivify all options in $self->o()
    $self->default_options();
    $self->pipeline_create_commands();
    $self->pipeline_wide_parameters();
    $self->resource_classes();
    $self->pipeline_analyses();
    $self->dbconn_2_url('pipeline_db'); # force vivification of the whole 'pipeline_db' structure (used in run() )

        # you can override parsing of commandline options if creating pipelines by a script - just provide the overriding hash
    my $cmdline_options = $self->{_cmdline_options} = shift @_ || $self->_load_cmdline_options();

    print "\nPipeline:\n\t".ref($self)."\n\n";

    if($cmdline_options->{'help'}) {

        my $all_needed_options = $self->_hash_undefs();

        $self->_saturated_merge_defaults_into_options();

        my $mandatory_options = $self->_hash_undefs();

        print "Available options:\n\n";
        foreach my $key (sort keys %$all_needed_options) {
            print "\t".$key.($mandatory_options->{$key} ? ' [mandatory]' : '')."\n";
        }
        print "\n";
        exit(0);

    } else {

        $self->_merge_into_options($cmdline_options);

        $self->_saturated_merge_defaults_into_options();

        my $undefined_options = $self->_hash_undefs();

        if(scalar(keys(%$undefined_options))) {
            print "Undefined options:\n\n";
            print join("\n", map { "\t$_" } keys %$undefined_options)."\n\n";
            print "To get the list of available options for ".ref($self)." pipeline please run:\n\n";
            print "\t$0 ".ref($self)." -help\n\n";
            exit(1);
        }
    }
    # by this point we have either exited or options are good
}

=head2 run

    Description : The method that uses the Hive/EnsEMBL API to actually create all the analyses, jobs, dataflow and control rules and resource descriptions.

    Caller      : init_pipeline.pl or any other script that will drive this module.

=cut

sub run {
    my $self  = shift @_;
    my $analysis_topup = $self->{_cmdline_options}{'analysis_topup'};
    my $job_topup      = $self->{_cmdline_options}{'job_topup'};

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

    foreach my $aha (@{$self->pipeline_analyses}) {
        my ($logic_name, $module, $parameters_hash, $input_ids, $program_file, $blocked, $batch_size, $hive_capacity, $failed_job_tolerance, $rc_id) =
             rearrange([qw(logic_name module parameters input_ids program_file blocked batch_size hive_capacity failed_job_tolerance rc_id)], %$aha);

        $parameters_hash ||= {};
        $input_ids       ||= [];

        if($analysis_topup and $analysis_adaptor->fetch_by_logic_name($logic_name)) {
            warn "Skipping already existing analysis '$logic_name'\n";
            next;
        }

        my $analysis;

        if($job_topup) {

            $analysis = $analysis_adaptor->fetch_by_logic_name($logic_name) || die "Could not fetch analysis '$logic_name'";

        } else {

            warn "Creating '$logic_name'...\n";

            $analysis = Bio::EnsEMBL::Analysis->new (
                -db              => '',
                -db_file         => '',
                -db_version      => '1',
                -logic_name      => $logic_name,
                -module          => $module,
                -parameters      => stringify($parameters_hash),    # have to stringify it here, because Analysis code is external wrt Hive code
                -program_file    => $program_file,
            );

            $analysis_adaptor->store($analysis);

            my $stats = $analysis->stats();
            $stats->batch_size( $batch_size )                       if(defined($batch_size));
            $stats->hive_capacity( $hive_capacity )                 if(defined($hive_capacity));
            $stats->failed_job_tolerance( $failed_job_tolerance )   if(defined($failed_job_tolerance));
            $stats->rc_id( $rc_id )                                 if(defined($rc_id));
            $stats->status($blocked ? 'BLOCKED' : 'READY');         #   (some analyses will be waiting for human intervention in blocked state)
            $stats->update();
        }

            # now create the corresponding jobs (if there are any):
        foreach my $input_id_hash (@$input_ids) {

            Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                -input_id       => $input_id_hash,  # input_ids are now centrally stringified in the AnalysisJobAdaptor
                -analysis       => $analysis,
                -input_job_id   => 0, # because these jobs are created by the initialization script, not by another job
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
                    warn "Created Control rule: $condition_url -| $logic_name\n";
                } else {
                    die "Could not fetch analysis '$condition_url' to create a control rule";
                }
            }

            $flow_into ||= {};
            $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

            foreach my $branch_code (sort {$a <=> $b} keys %$flow_into) {
                my $heirs = $flow_into->{$branch_code};

                $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first

                $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY'); # now force it into a hash if it wasn't

                while(my ($heir_url, $input_id_template) = each %$heirs) {

                    my $heir_analysis = $analysis_adaptor->fetch_by_logic_name_or_url($heir_url);

                    $dataflow_rule_adaptor->create_rule( $analysis, $heir_analysis || $heir_url, $branch_code, $input_id_template);

                    warn "Created DataFlow rule: [$branch_code] $logic_name -> $heir_url"
                        .($input_id_template ? ' WITH TEMPLATE: '.stringify($input_id_template) : '')."\n";
                }
            }
        }
    }

    my $url = $self->dbconn_2_url('pipeline_db');

    print "\n\n\tPlease run the following commands:\n\n";
    print "  beekeeper.pl -url $url -sync\t\t# (synchronize the Hive - should always be done before [re]starting a pipeline)\n\n";
    print "  beekeeper.pl -url $url -loop\t\t# (run the pipeline in automatic mode)\n";
    print "(OR)\n";
    print "  beekeeper.pl -url $url -run\t\t# (run one step of the pipeline - useful for debugging/learning)\n";

    print "\n\n\tTo connect to your pipeline database use the following line:\n\n";
    print "  mysql ".$self->dbconn_2_mysql('pipeline_db',1)."\n\n";
}


# -------------------------------[the rest are dirty implementation details]-------------------------------------

=head2 _completely_defined

    Description : a private function (not a method) that checks whether a certain string is clean from undefined options

=cut

sub _completely_defined {
    return (index(shift @_, $undef_const) == ($[-1) );  # i.e. $undef_const is not a substring
}

=head2 _load_cmdline_options

    Description : a private method that deals with parsing of the command line (currently it drives GetOptions that has some limitations)

=cut

sub _load_cmdline_options {
    my $self      = shift @_;

    my %cmdline_options = ();

    GetOptions( \%cmdline_options,
        'help!',
        'analysis_topup!',
        'job_topup!',
        map { "$_=s".((ref($self->o($_)) eq 'HASH') ? '%' : '') } keys %{$self->o}
    );
    return \%cmdline_options;
}

=head2 _merge_into_options

    Description : a private method to merge one options-containing structure into another

=cut

sub _merge_into_options {
    my $self      = shift @_;
    my $hash_from = shift @_;
    my $hash_to   = shift @_ || $self->o;

    my $subst_counter = 0;

    while(my($key, $value) = each %$hash_from) {
        if(exists($hash_to->{$key})) {  # simply ignore the unused options
            if(ref($value) eq 'HASH') {
                if(ref($hash_to->{$key}) eq 'HASH') {
                    $subst_counter += $self->_merge_into_options($hash_from->{$key}, $hash_to->{$key});
                } else {
                    $hash_to->{$key} = { %$value };
                    $subst_counter += scalar(keys %$value);
                }
            } elsif(_completely_defined($value) and !_completely_defined($hash_to->{$key})) {
                $hash_to->{$key} = $value;
                $subst_counter++;
            }
        }
    }
    return $subst_counter;
}

=head2 _saturated_merge_defaults_into_options

    Description : a private method to merge defaults into options as many times as required to resolve the dependencies.
                  Use with caution, as it doesn't check for loops!

=cut

sub _saturated_merge_defaults_into_options {
    my $self      = shift @_;

        # Note: every time the $self->default_options() has to be called afresh, do not cache!
    while(my $res = $self->_merge_into_options($self->default_options)) { }
}

=head2 _hash_undefs

    Description : a private method that collects all the options that are undefined at the moment
                  (used at different stages to find 'all_options', 'mandatory_options' and 'undefined_options').

=cut

sub _hash_undefs {
    my $self      = shift @_;
    my $hash_to   = shift @_ || {};
    my $hash_from = shift @_ || $self->o;
    my $prefix    = shift @_ || '';

    while(my ($key, $value) = each %$hash_from) {
        my $new_prefix = $prefix ? $prefix.' -> '.$key : $key;

        if(ref($value) eq 'HASH') { # go deeper
            $self->_hash_undefs($hash_to, $value, $new_prefix);
        } elsif(!_completely_defined($value)) {
            $hash_to->{$new_prefix} = 1;
        }
    }
    return $hash_to;
}

1;
