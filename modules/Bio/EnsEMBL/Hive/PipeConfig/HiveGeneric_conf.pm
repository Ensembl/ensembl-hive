## Generic configuration module for all Hive pipelines with loader functionality (all other Hive pipeline config modules should inherit from it)

package Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;

use strict;
use warnings;
use Getopt::Long;
use Bio::EnsEMBL::Utils::Argument;          # import 'rearrange()'
use Bio::EnsEMBL::Hive::Utils 'stringify';  # import 'stringify()'
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Extensions;

# ---------------------------[the following methods will be overridden by specific pipelines]-------------------------

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

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 0)." -e 'CREATE DATABASE ".$self->o('pipeline_db', '-dbname')."'",

            # standard eHive tables and procedures:
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/tables.sql',
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1).' <'.$self->o('ensembl_cvs_root_dir').'/ensembl-hive/sql/procedures.sql',
    ];
}

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        'pipeline_name'  => $self->o('pipeline_name'),       # name the pipeline to differentiate the submitted processes
    };
}

sub resource_classes {
    my ($self) = @_;
    return {
        0 => { -desc => 'default, 8h',      'LSF' => '' },
        1 => { -desc => 'urgent',           'LSF' => '-q yesterday' },
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
    ];
}


# ---------------------------------[now comes the interfacing stuff - feel free to call but not to modify]--------------------

my $undef_const = '-=[UnDeFiNeD_VaLuE]=-';  # we don't use undef, as it cannot be detected as a part of a string

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;

    return $self;
}

sub o {                 # descends the option hash structure (vivifying all encountered nodes) and returns the value if found
    my $self = shift @_;

    my $value = $self->{_pipe_option} ||= {};

    while(defined(my $option_syll = shift @_)) {

        if(exists($value->{$option_syll})
        and ((ref($value->{$option_syll}) eq 'HASH') or completely_defined($value->{$option_syll}))
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

sub dbconn_2_mysql {    # will save you a lot of typing
    my ($self, $db_conn, $with_db) = @_;

    return '--host='.$self->o($db_conn,'-host').' '
          .'--port='.$self->o($db_conn,'-port').' '
          .'--user='.$self->o($db_conn,'-user').' '
          .'--pass='.$self->o($db_conn,'-pass').' '
          .($with_db ? ('--database='.$self->o($db_conn,'-dbname').' ') : '');
}

sub dbconn_2_url {
    my ($self, $db_conn) = @_;

    return 'mysql://'.$self->o($db_conn,'-user').':'.$self->o($db_conn,'-pass').'@'.$self->o($db_conn,'-host').':'.$self->o($db_conn,'-port').'/'.$self->o($db_conn,'-dbname');
}

sub process_options {
    my $self            = shift @_;

        # first, vivify all options in $self->o()
    $self->default_options();
    $self->pipeline_create_commands();
    $self->pipeline_wide_parameters();
    $self->pipeline_analyses();

        # you can override parsing of commandline options if creating pipelines by a script - just provide the overriding hash
    my $cmdline_options = $self->{_cmdline_options} = shift @_ || $self->load_cmdline_options();

    print "\nPipeline: ".ref($self)."\n";

    if($cmdline_options->{'help'}) {

        my $all_needed_options = $self->hash_undefs();

        $self->saturated_merge_defaults_into_options();

        my $mandatory_options = $self->hash_undefs();

        print "Available options:\n\n";
        foreach my $key (sort keys %$all_needed_options) {
            print "\t".$key.($mandatory_options->{$key} ? ' [mandatory]' : '')."\n";
        }
        print "\n";
        exit(0);

    } else {

        $self->merge_into_options($cmdline_options);

        $self->saturated_merge_defaults_into_options();

        my $undefined_options = $self->hash_undefs();

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

sub run {
    my $self       = shift @_;
    my $topup_flag = $self->{_cmdline_options}{topup};

    unless($topup_flag) {
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
    
    my $meta_container = $hive_dba->get_MetaContainer;
    warn "Loading pipeline-wide parameters ...\n";

    my $pipeline_wide_parameters = $self->pipeline_wide_parameters;
    while( my($meta_key, $meta_value) = each %$pipeline_wide_parameters ) {
        if($topup_flag) {
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

    my $analysis_adaptor             = $hive_dba->get_AnalysisAdaptor;

    foreach my $aha (@{$self->pipeline_analyses}) {
        my ($logic_name, $module, $parameters_hash, $input_ids, $program_file, $blocked, $batch_size, $hive_capacity, $failed_job_tolerance, $rc_id) =
             rearrange([qw(logic_name module parameters input_ids program_file blocked batch_size hive_capacity failed_job_tolerance rc_id)], %$aha);

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

            # now create the corresponding jobs (if there are any):
        foreach my $input_id_hash (@$input_ids) {

            Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                -input_id       => $input_id_hash,  # input_ids are now centrally stringified in the AnalysisJobAdaptor
                -analysis       => $analysis,
                -input_job_id   => 0, # because these jobs are created by the initialization script, not by another job
            );
        }
    }

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
        foreach my $condition_logic_name (@$wait_for) {
            if(my $condition_analysis = $analysis_adaptor->fetch_by_logic_name($condition_logic_name)) {
                $ctrl_rule_adaptor->create_rule( $condition_analysis, $analysis);
                warn "Created Control rule: $condition_logic_name -| $logic_name\n";
            } else {
                die "Could not fetch analysis '$condition_logic_name' to create a control rule";
            }
        }

        $flow_into ||= {};
        $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

        foreach my $branch_code (sort {$a <=> $b} keys %$flow_into) {
            my $heir_logic_names = $flow_into->{$branch_code};
            $heir_logic_names    = [ $heir_logic_names ] unless(ref($heir_logic_names) eq 'ARRAY'); # force scalar into an arrayref

            foreach my $heir_logic_name (@$heir_logic_names) {
                if(my $heir_analysis = $analysis_adaptor->fetch_by_logic_name($heir_logic_name)) {
                    $dataflow_rule_adaptor->create_rule( $analysis, $heir_analysis, $branch_code);
                    warn "Created DataFlow rule: [$branch_code] $logic_name -> $heir_logic_name\n";
                } else {
                    die "Could not fetch analysis '$heir_logic_name' to create a dataflow rule";
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
}


# -------------------------------[the rest are dirty implementation details]-------------------------------------

sub completely_defined {    # NB: not a method
    return (index(shift @_, $undef_const) == ($[-1) );  # i.e. $undef_const is not a substring
}

sub load_cmdline_options {
    my $self      = shift @_;

    my %cmdline_options = ();

    GetOptions( \%cmdline_options,
        'help!',
        'topup!',
        map { "$_=s".((ref($self->o($_)) eq 'HASH') ? '%' : '') } keys %{$self->o}
    );
    return \%cmdline_options;
}

sub merge_into_options {
    my $self      = shift @_;
    my $hash_from = shift @_;
    my $hash_to   = shift @_ || $self->o;

    my $subst_counter = 0;

    while(my($key, $value) = each %$hash_from) {
        if(exists($hash_to->{$key})) {  # simply ignore the unused options
            if(ref($value) eq 'HASH') {
                if(ref($hash_to->{$key}) eq 'HASH') {
                    $subst_counter += $self->merge_into_options($hash_from->{$key}, $hash_to->{$key});
                } else {
                    $hash_to->{$key} = { %$value };
                    $subst_counter += scalar(keys %$value);
                }
            } elsif(completely_defined($value) and !completely_defined($hash_to->{$key})) {
                $hash_to->{$key} = $value;
                $subst_counter++;
            }
        }
    }
    return $subst_counter;
}

sub saturated_merge_defaults_into_options {
    my $self      = shift @_;

        # Note: every time the $self->default_options() has to be called afresh, do not cache!
    while(my $res = $self->merge_into_options($self->default_options)) { }
}

sub hash_undefs {
    my $self      = shift @_;
    my $hash_to   = shift @_ || {};
    my $hash_from = shift @_ || $self->o;
    my $prefix    = shift @_ || '';

    while(my ($key, $value) = each %$hash_from) {
        my $new_prefix = $prefix ? $prefix.' -> '.$key : $key;

        if(ref($value) eq 'HASH') { # go deeper
            $self->hash_undefs($hash_to, $value, $new_prefix);
        } elsif(!completely_defined($value)) {
            $hash_to->{$new_prefix} = 1;
        }
    }
    return $hash_to;
}

1;
