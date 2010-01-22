=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::JobFactory

=head1 DESCRIPTION

A generic module for creating batches of similar jobs.

=head1 USAGE EXAMPLES

cat <<EOF >/tmp/jf_test.txt
5
8
9
13
15
26
EOF

mysql --defaults-group-suffix=_compara1 -e 'DROP DATABASE job_factory_test'

mysql --defaults-group-suffix=_compara1 -e 'CREATE DATABASE job_factory_test'

mysql --defaults-group-suffix=_compara1 job_factory_test <~lg4/work/ensembl-hive/sql/tables.sql

mysql --defaults-group-suffix=_compara1 job_factory_test

INSERT INTO analysis (created, logic_name, module, parameters)
VALUES (NOW(), 'analysis_factory', 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
 "{ 'module' => 'Bio::EnsEMBL::Hive::RunnableDB::Test', 'eval' => 1, 'parameters' => { 'divisor' => 4 }, 'input_id' => { 'value' => '$RangeStart', 'time_running' => '$RangeCount*2'} }");

INSERT INTO analysis (created, logic_name, module, parameters)
VALUES (NOW(), 'factory_from_file', 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
 "{ 'module' => 'Bio::EnsEMBL::Hive::RunnableDB::Test', 'eval' => 1, 'parameters' => { 'divisor' => 13 }, 'input_id' => { 'value' => '$InputLine', 'time_running' => 2} }");


INSERT INTO analysis_job (analysis_id, input_id) VALUES (1, '{ start => 10, end => 47, step => 5, logic_name => "alpha_analysis", hive_capacity => 3}');

INSERT INTO analysis_job (analysis_id, input_id) VALUES (1, '{ start => 2, end => 7, logic_name => "beta_analysis", batch_size => 2}');

INSERT INTO analysis_job (analysis_id, input_id) VALUES (2, '{ inputfile => "/tmp/jf_test.txt", logic_name => "gamma_file", randomize =>1 }');

SELECT * FROM analysis; SELECT * FROM analysis_stats; SELECT * FROM analysis_job;

QUIT

beekeeper.pl -url mysql://ensadmin:ensembl@compara1/job_factory_test -sync

#runWorker.pl -url mysql://ensadmin:ensembl@compara1/job_factory_test
beekeeper.pl -url mysql://ensadmin:ensembl@compara1/job_factory_test -loop

mysql --defaults-group-suffix=_compara1 job_factory_test -e 'SELECT * FROM analysis'

mysql --defaults-group-suffix=_compara1 job_factory_test -e 'SELECT * FROM analysis_job'


NB: NB: NB: The documentation needs refreshing. There are now four modes (inputlist, inputfile, inputquery and inputrange) instead of two.

=cut

package Bio::EnsEMBL::Hive::RunnableDB::JobFactory;

use strict;

use Data::Dumper;  # NB: not for testing, but for actual data structure stringification

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub fetch_input {   # we have nothing to fetch, really
    my $self = shift @_;

    return 1;
}

sub run {
    my $self = shift @_;

    my $logic_name    = $self->param('logic_name')    || die "'logic_name' is an obligatory parameter";
    my $module        = $self->param('module')        || die "'module' is an obligatory parameter";
    my $parameters    = $self->param('parameters')    || {};
    my $batch_size    = $self->param('batch_size')    || undef;
    my $hive_capacity = $self->param('hive_capacity') || undef;

    my $analysis   = $self->db->get_AnalysisAdaptor()->fetch_by_logic_name($logic_name)
                    || $self->create_analysis_object($logic_name, $module, $parameters, $batch_size, $hive_capacity);
    my $input_hash = $self->param('input_id')         || die "'input_id' is an obligatory parameter";
    my $eval       = $self->param('eval')             || 0;
    my $randomize  = $self->param('randomize')        || 0;

    if(my $inputlist = $self->param('inputlist')) {

        $self->create_jobs_from_list( $inputlist , $randomize, $analysis, $input_hash, $eval);

    } elsif(my $inputfile = $self->param('inputfile')) {

        $self->create_jobs_from_list( $self->make_list_from_file($inputfile) , $randomize, $analysis, $input_hash, $eval);

    } elsif(my $inputquery = $self->param('inputquery')) {

        $self->create_jobs_from_list( $self->make_list_from_query($inputquery) , $randomize, $analysis, $input_hash, $eval);

    } elsif(defined(my $start = $self->param('start')) and defined(my $end = $self->param('end'))) {

        my $step = $self->param('step') || 1;
        $self->create_jobs_from_range($analysis, $input_hash, $eval, $start, $end, $step);
    }
}

sub write_output {  # and we have nothing to write out
    my $self = shift @_;

    return 1;
}

################################### main functionality starts here ###################

sub create_analysis_object {
    my ($self, $logic_name, $module, $parameters, $batch_size, $hive_capacity) = @_;

    my $dba = $self->db;

    $Data::Dumper::Indent = 0;  # we want everything on one line
    $Data::Dumper::Terse = 1;   # and we want it without dummy variable names

    my $analysis = Bio::EnsEMBL::Analysis->new (
        -db              => '',
        -db_file         => '',
        -db_version      => '1',
        -logic_name      => $logic_name,
        -module          => $module,
        -parameters      => Dumper($parameters),
    );

    $dba->get_AnalysisAdaptor()->store($analysis);

    my $stats = $analysis->stats();

    $stats->batch_size( $batch_size )       if(defined($batch_size));
    $stats->hive_capacity( $hive_capacity ) if(defined($hive_capacity));

    $stats->status('READY');
    $stats->update();

    return $analysis;
}

sub make_list_from_file {
    my ($self, $inputfile) = @_;

    open(FILE, $inputfile) or die $!;
    my @lines = <FILE>;
    chomp @lines;
    close(FILE);

    return \@lines;
}

sub make_list_from_query {
    my ($self, $inputquery) = @_;

    my @ids = ();

    my $sth = $self->db->dbc()->prepare($inputquery);
    $sth->execute();
    while (my ($id)=$sth->fetchrow_array()) {
        push @ids, $id;
    }
    $sth->finish();

    return \@ids;
}

sub create_jobs_from_list {
    my ($self, $list, $randomize, $analysis, $input_hash, $eval) = @_;

    if($randomize) {
        fisher_yates_shuffle_in_place($list);
    }

    foreach my $line (@$list) {

        my %resolved_hash = (); # has to be a fresh hash every time
        while( my ($key,$value) = each %$input_hash) {

                # evaluate Perl-expressions after substitutions:
            if($key=~s/\$InputLine/$line/g) {
                if($eval) {
                    $key = eval($key);
                }
            }
            if($value=~s/\$InputLine/$line/g) {
                if($eval) {
                    $value = eval($value);
                }
            }

            $resolved_hash{$key} = $value;
        }
        $self->create_one_job($analysis, \%resolved_hash);
    }
}

sub create_jobs_from_range {
    my ($self, $analysis, $input_hash, $eval, $start, $end, $step) = @_;

    my @full_list = $start..$end;
    while(@full_list) {
        my ($from, $to);
        my $batch_cnt = 1;
        for($from = $to = shift @full_list; $batch_cnt<$step && @full_list; $batch_cnt++) {
            $to = shift @full_list;
        }

        my %resolved_hash = (); # has to be a fresh hash every time
        while( my ($key,$value) = each %$input_hash) {

                # evaluate Perl-expressions after substitutions:
            if($key=~/\$Range/) {
                $key=~s/\$RangeStart/$from/g;
                $key=~s/\$RangeEnd/$to/g;
                $key=~s/\$RangeCount/$batch_cnt/g;

                if($eval) {
                    $key = eval($key);
                }
            }
            if($value=~/\$Range/) {
                $value=~s/\$RangeStart/$from/g; 
                $value=~s/\$RangeEnd/$to/g; 
                $value=~s/\$RangeCount/$batch_cnt/g; 

                if($eval) {
                    $value = eval($value);
                }
            }

            $resolved_hash{$key} = $value;
        }
        $self->create_one_job($analysis, \%resolved_hash);
    }
}

sub create_one_job {
    my ($self, $analysis, $resolved_hash) = @_;

    $Data::Dumper::Indent = 0;  # we want everything on one line
    $Data::Dumper::Terse = 1;   # and we want it without dummy variable names

    Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
        -input_id       => Dumper($resolved_hash),
        -analysis       => $analysis,
        -input_job_id   => $self->input_job->dbID(),
    );
}

sub fisher_yates_shuffle_in_place {
    my $array = shift @_;

    for(my $upper=scalar(@$array);--$upper;) {
        my $lower=int(rand($upper+1));
        next if $lower == $upper;
        @$array[$lower,$upper] = @$array[$upper,$lower];
    }
}


1;
