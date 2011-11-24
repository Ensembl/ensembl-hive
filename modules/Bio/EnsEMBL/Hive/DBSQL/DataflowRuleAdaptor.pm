=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor 

=head1 SYNOPSIS

  $dataflow_rule_adaptor = $db_adaptor->get_DataflowRuleAdaptor;
  $dataflow_rule_adaptor = $dataflowRuleObj->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class DataflowRule.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use strict;
use Bio::EnsEMBL::Hive::DataflowRule;
use Bio::EnsEMBL::Hive::Utils ('stringify');  # import 'stringify()'

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'dataflow_rule';
}


sub default_insertion_method {
    return 'INSERT';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::DataflowRule';
}




=head2 branch_name_2_code

Description: encodes a branch mnemonic name into numeric code

=cut

sub branch_name_2_code {
    my $branch_name_or_code = pop @_;   # NB: we take the *last* arg, so it works both as a method and a subroutine

    return 1 unless(defined($branch_name_or_code));

    my $branch_code = ($branch_name_or_code=~/^\-?\d+$/)
        ? $branch_name_or_code
        : {
            'MAIN'          =>  1,

            'ANYFAILURE'    =>  0,
            'MEMLIMIT'      => -1,
            'RUNLIMIT'      => -2,
        }->{$branch_name_or_code};
    return defined($branch_code) ? $branch_code : die "Could not map the branch_name '$branch_name_or_code' to the internal code";
}

=head2 fetch_all_by_from_analysis_id_and_branch_code

  Args       : unsigned int $analysis_id, unsigned int $branch_code
  Example    : my @rules = @{$ruleAdaptor->fetch_all_by_from_analysis_id_and_branch_code($analysis_id, $branch_code)};
  Description: searches database for rules with given from_analysis_id and branch_code
               and returns all such rules in a list (by reference)
  Returntype : reference to list of Bio::EnsEMBL::Hive::DataflowRule objects
  Exceptions : none
  Caller     : Bio::EnsEMBL::Hive::AnalysisJob::dataflow_output_id

=cut

sub fetch_all_by_from_analysis_id_and_branch_code {
    my ($self, $analysis_id, $branch_name_or_code) = @_;

    return [] unless($analysis_id);

    my $branch_code = $self->branch_name_2_code($branch_name_or_code);

    my $constraint = "from_analysis_id=${analysis_id} AND branch_code=${branch_code}";

    return $self->fetch_all($constraint);
}


=head2 create_rule

  Title   : create_rule
  Usage   : $self->create_rule( $from_analysis, $to_analysis, $branch_code );
  Function: Creates and stores a new rule in the DB.
  Returns : Bio::EnsEMBL::Hive::DataflowRule
  Args[1] : Bio::EnsEMBL::Analysis $from_analysis
  Args[2] : Bio::EnsEMBL::Analysis OR a hive-style URL  $to_analysis_or_url
  Args[3] : (optional) int $branch_code
  Args[4] : (optional) (Perl structure or string) $input_id_template

=cut

sub create_rule {
    my ($self, $from_analysis, $to_analysis_or_url, $branch_name_or_code, $input_id_template, $funnel_branch_name_or_code) = @_;

    return unless($from_analysis and $to_analysis_or_url);

    my $rule = Bio::EnsEMBL::Hive::DataflowRule->new(
        -from_analysis      =>  $from_analysis,

        ref($to_analysis_or_url)
            ? ( -to_analysis     => $to_analysis_or_url )
            : ( -to_analysis_url => $to_analysis_or_url ),

        -branch_code        =>  defined($branch_name_or_code) ? $self->branch_name_2_code($branch_name_or_code) : 1,
        -input_id_template  =>  (ref($input_id_template) ? stringify($input_id_template) : $input_id_template),
        -funnel_branch_code =>  $self->branch_name_2_code($funnel_branch_name_or_code),
    );

    return $self->store($rule, 1);  # avoid redundancy
}


1;

