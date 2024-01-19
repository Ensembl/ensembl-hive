Tips (cheat-sheet)
~~~~~~~~~~~~~~~~~~

In this section we perform tips from user experience that will allow you avoid many icebergs in eHive usage.

.. contents::

Quick "Rules" for writing hive pipelines
++++++++++++++++++++++++++++++++++++++++

Designing pipelines
===================

* Don't force users to edit the ``conf.pm`` file
	unless they want to do something complicated and esoteric
* Do as much database access as possible via a registry file
	and don't put default database connection parameters in a conf file
* If using a registry file, make it available to all workers by default
	although I'm not sure how this is different to setting a ``pipeline_wide_parameter``, or about the pros and cons of setting as a worker parameter, in the resources?
* Use ``pipeline_wide_parameters``
	so you don't need to pass the same variable to lots of modules
* Propagate parameters through your pipeline
	but remember that only output parameters are propagated
* Have a single starting module, i.e. only only with ``input_ids => [{}]``
	because anything else is counter-intuitive
* Use semaphores
	if you don't need semaphores in your pipeline, you probably don't need a pipeline
* Use semaphores for grouping modules
	because it makes the pipeline easier to understand
* Don't use `wait_for``
	it's not as efficient as a semaphore, and it goes against the grain of the pipeline (possible exception for pipelines that can be (re)seeded? example?)
* Use Dummy modules to structure the pipeline
	these are especially useful to break up complicated semaphore logic
* Put complicated conditionals in a module
	because maintenance of complicated structures in pipeconfig  is a pain
* Only use accumulators if you really need to
	because they are hard to configure and maintain, and are of limited usefulness
* Email a report when the pipeline is complete
	because you can't expect users to run their own queries to check the data

Writing modules
===============
* Use ``param_defaults()``, but don't rely on them
	all of the pipeline's parameters should be defined in the conf.pm file
* Use ``fetch_input()`` for housekeeping tasks
	e.g. parameter checking, instantiating parameters
* Use ``run()`` to do something useful
	Load all the parameters at the top of the method, for clarity
* Only flow from ``write_output()``
	because that is where people will look for dataflow configuration
* Use ``self->throw()`` and ``self->warning()``
	so that error messages are inserted into the log_message table of the hive db; do not import ``Bio::EnsEMBL::Utils::Exception`` because it will replace throw and warning, and eHive won't be able to report anything
* Use ``self->param_required()``
	so that you don't need to write your own parameter checks
* Use ``self->input_job->autoflow(0)`` sparingly
	because it's confusing when your pipeline does non-standard things

Debugging
+++++++++

run_Worker.pl
=============

First step is to use ``run_Worker.pl``, it is the ``test_RunnableDB`` of eHive. You may need to bsub it::

 run_Worker.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME  -reg_conf PATH_TO/registry.pm -job_id NNN

If the job is successful you can run ``beekeeer.pl``

beekeeper.pl
============
Getting more information
------------------------

If your workers are failing, you can use 2 options to understand what is really happening:

* *submit_log_dir <directory>: it will write the output of the bsub job as if you are using -o and -e, probably the most interesting*
* *hive_log_dir <directory>: it will write the output of the hive*

There is a third option, ``-debug <number>``, which should be used if you use any of the two option above.

Resetting DONE jobs
-------------------
You can reset done jobs quite easily but it seems that the input ids will be kept so they will be in a ready state which may not be what you want in some cases::

 perl beekeeper.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -reset_all_jobs 1 -analyses_pattern "havana_merge_list_%"

Manually set job done
---------------------
If you manually set some of your jobs done, you may need to set the semaphore count for the next analysis if the DONE'ed analysis is in a funnel. Otherwise the analysis will not start as it expect more jobs to finish::

 hive_pipeline_db> UPDATE job SET semaphore_count = 0 WHERE analysis_id = <analysis_id not starting>;

::

 perl beekeeper.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -balance_semaphores
 perl beekeeper.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -loop

Excluded analyses
=================

If too many of your jobs die, your analysis can be set in excluded state. This ususally happens if your module cannot compile for any reason. **VERSION/2.5** ::

 perl $HS/tweak_pipeline.pl -url $EHIVE_URL -SET 'analysis[process_assembly_info].is_excluded=0'

Team
====
If you still can't understand what is happening, it's probably better to talk to Brandon or Matthieu

Running a pipeline
++++++++++++++++++

Running a subset of analyses
============================

You can run a subset of analyses by using the -analyses_pattern. This can be done using wildcards or analysis id ranges::

 beekeeper.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -loop -analyses_pattern "havana_%"
 beekeeper.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -loop -analyses_pattern "1..5,7..10"

In particular, using analysis id ranges can be useful for running a pipeline up until a certain analysis. Be aware that analysis ids are assigned based on the order of the analyses in the config, so make sure that the ranges you use only encompass the analyses of interest.

Topping up a pipeline
=====================
You may want to add analyses to your pipeline. You can do it the hard way by populating the analysis_base, analysis_stats, dataflow_rule, job, analysis_ctrl_rule, resource_class, resource_description. Or you can simply edit your configuration file then run the init script::

 perl init_pipeline.pl HiveRNASeq_conf -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -hive_no_init 1

To add input ids you can you the seed_pipeline.pl script::

 perl seed_pipeline.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -logic_name create_ccode_config -input_id '{filename => "merged.bam"}'

Writing a RunnableDB
++++++++++++++++++++

Introduction
============
In eHive as in the old pipeline, RunnableDBs run your analysis. Each system has a script/module which will call 3 methods in this order:

#. fetch_input
#. run
#. write_output

There is a base module which simply implements these 3 methods. **Every module should inherits from Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveBaseRunnable.** If you want to do more complicated stuff you will need to override any of these 3 methods.

Normally you should not override the run method because you should create a Runnable which will run the analysis and the base run method should be enough.

Never ever use warning or throw from Bio::EnsEMBL::Utils::Exception
===================================================================
::

 If you use Bio::EnsEMBL::Utils::Exception in your RunnableDB you will loose all the information from your throw/warning to /dev/null

Database connections
====================

hrdb_get_dba
------------

DBAdaptor cache
***************

When you are using ``hrdb_get_dba``, the DBAdaptor is cached on the worker until the worker dies or if the worker respecializes and run a job from a different analysis.

Working with non Core DBAdaptor
*******************************

When calling ``hrdb_get_dba`` you can specify the type of adaptor you want as long as it's in your PERL5LIB:
 * Compara
 * Variation
 * Funcgen

::

 my $funcgen_db = $self->hrdb_get_dba($self->param('funcgen_db'), undef, 'Funcgen');

Difference between disconnect_if_idle and disconnect_when_inactive
------------------------------------------------------------------

``disconnect_if_idle`` will simply disconnect from the server. But if your need to connect to the server again, it will stay connected.
``disconnect_when_inactive`` is checked each time the API wants to call ``disconnect_if_idle`` and disconnect if the value is 1.

When do I need to disconnect from the server
--------------------------------------------

By default, there is a latency between the moment you free a port and the moment you can reuse this port to connect, which is around 1 minute.
When running a 5 hours long program like BWA the module should not be connected to a server. You should disconnect from all the server that you don't use if the time between connections is bigger than minutes. Hive uses its own DBAdaptor but it's using some feature of the Core API if it is in your PERL5LIB
To disconnect the worker from the database::

 $self->dbc->disconnect_if_idle() if ($self->param('disconnect_jobs'));

Hive will reconnect to the database when it's needed without having to ask for it.
To disconnect the RunnableDB from your input database::

 $self->hrdb_get_dba($self->param('output_db'))->dbc->disconnect_when_inactive(1) if ($self->param('disconnect_jobs'));

When you are writing the output to the database you may want to keep the connection. This means that when you are writing your write_output method,  you may want to set disconnect_when_inactive to 0.

Choosing when to disconnect
***************************
A parameter in HiveBaseRunnableDB allows you to easily disconnect from the database when you know the job will be long, like if you are submitting on the long queue... *: disconnect_jobs*. It is set to 0 by default

I don't want my job to run for too long
=======================================

Do not use -W from LSF
----------------------

If you use -W in your resources, Hive sees TERM_RUNLIMIT it will send the job to the -2 branch which may not be what you want. If your jobs started one minute before the limit it doesn't mean it will take more than your run limit to run.

Use execute_with_timer
----------------------
Instead of calling execute_with_wait or system in your runnable, use execute_with_timer and specify your run limit. It will kill the job and you will be able to use a branch to redirect your job.execute_with_timer uses execute_with_wait to make sure that LSF will get the TERM_MEMLIMIT or TERM_RUNLIMIT::

 use Bio::EnsEMBL::Analysis::Tools::Utilities qw(execute_with_timer);

 my $command = "blastp -in $infile -db $uniprotfile -out $outfile";
 execute_with_timer($command, '1h');

At the moment execute_with_timer throws if you don't give a time. This behaviour might change in the future.

What if it's only Perl?
-----------------------

Your code should not take that long...

fetch_input
===========
This is the method that fetch all your data, file names,... It should check if the file exists, the program you want to use exists and prepare your data. The best would be to create a Runnable at the end of the method and to store it with ``$self->runnable``.
You will also need to create your output database Adaptor and store them with ``hrdb_set_con/hrdb_get_con`` ::

 my $dba = $self->get_database_by_name('output_db');
 $self->hrdb_set_con($dba, 'output_db');

If you have no data to work on you can tell eHive that you're stopping now, it's OK and you can also decide to stop the flow::

 $self->complete_early('Nothing to do');

or::

 $self->input_job->autoflow(0);
 $self->complete_early('No genes to process');

Using $self->input_id
---------------------

If you are using 'iid' in your Hive input_id parameters, you can fetch this value by calling ``$self->input_id``.
You can modify this by having a _input_id_name parameter for your analysis which will set the name of the parameter to use::

 sub param_defaults {
     my $self = shift;
     return {
         %{$self->SUPER::param_defaults},
         _input_id_name => 'filename',
     }
 }

run
===

This is the method that runs the analysis. If you need to override this method, your code should throw exceptions only if it relates to the execution of the code. Otherwise you can simply call $runnable->run.

write_output
============

This is the method that write the output to your database or a file. It can be empty if the program you execute has already written the output file and you will not post process. This is also the moment when you can flow some data to the pipeline like the name of the file created.::

 $dba = $self->hrdb_get_con('output_db');
 $dba->dbc->disconnect_when_inactive(0);

throw/warning
=============
When you want to call throw, please use $self->throw. The advantage of doing this is that we can override the call in a "Base" module so we don't have to change every module later
pre_process
===========

eHive has a pre_preprocess method which is run when you start a failed job. This could be usefull for deleting empty gene/transcript.

post_cleanup
============
eHive has a post_cleanup method which can be used when your job failed and you catched it with eval like writing genes.

Simple example
==============
::

 use strict;
 use warnings;
 use Bio::EnsEMBL::Analysis::Runnable::ProcessGenes;
 use parent (Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveBaseRunnableDB);

 sub fetch_input {
   my $self = shift;

   my $dna_db = $self->get_database_by_name('dna_db');
   my $dba = $self->get_database_by_name('input_db', $dna_db);
   my $slice = $dba->get_SliceAdaptor->fetch_by_name($self->input_id);
   my $genes = $slice->fetch_all_Genes;
   $dba->dbc->disconnect_when_inactive(1);
   my $out_dba = $self->get_database_by_name('output_db', $dna_db);
   $self->hrdb_set_con($out_dba, 'out_db');
   my $runnable = Bio::EnsEMBL::Analysis::Runnable::ProcessGenes->new(
     -genes => $genes,
     -target_file => $self->param('genome_file'),
     );
   $self->runnable($runnable);
 }

 sub run {
   my $self = shift;

   $self->dbc->disconnect_if_idle();
   foreach my $runnable (@{$self->runnable}) {
     $runnable->run;
     $self->ouptut($runnable->output);
   }
 }

 sub write_output {
  my $self = shift;

  my @gene_ids;
  my $dba = $self->hrdb_get_con('out_db');
  my $gene_adaptor = $dba->get_GeneAdaptor;
  $gene_adaptor->dbc->disconnect_when_inactive(0);
  foreach my $gene (@{$self->output}) {
    eval {
      empty_Gene($gene);
      $gene_adaptor->store($gene);
      push(@gene_ids, $gene->dbID);
    };
    if ($@) {
      $self->param('fail_delete_features', \@gene_ids);
      $self->throw($@);
    }
   }
  }

 sub post_cleanup {
  my $self = shift;

  if ($self->param_is_defined('fail_delete_features')) {
    my $dba = $self->hrdb_get_con('out_db');
    my $gene_adaptor = $dba->get_GeneAdaptor;
    foreach my $gene (@{$self->param('fail_delete_features')}) {
      eval {
         $gene_adaptor->remove($gene);
      };
      if ($@) {
        $self->throw('Could not cleanup the mess for these dbIDs: '.join(', ', @{$self->param('fail_delete_features')}));
      }
    }
  }
 }

Writing a Runnable
++++++++++++++++++

A Runnable is the module containing your algorithm. A Runnable should not try to connect to a database. Three methods are important:
 * new
    * create your object
    * set the parameters
    * throw if something is wrong
 * run
    * this method is called by the RunnableDBs
    * contains your algorithm
    * stores the result in output
    * can call as many methods as you want
 * output
    * it stores the data as an arrayref

Creating your own input ids
+++++++++++++++++++++++++++

You can easily create input ids three different ways:
 #. Use Bio::EnsEMBL::Hive::JobFactory
 #. Use Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveSubmitAnalysis
 #. Create your own module which inherits from Bio::EnsEMBL::Hive::JobFactory

Creating your module
====================

It is quite easy to create your own module. You just need to inherit from ``Bio::EnsEMBL::Hive::JobFactory`` and you just have to create a method ``fetch_input``. You will need to populate to parameters with arrayrefs, ``inputlist`` and ``column_names`` ::

 use parent ('Bio::EnsEMBL::Hive::RunnableDB::JobFactory');
 sub fetch_input {
  my $self = shift;
  my @output_ids;
  <your code to create input ids as a list of arrayref stored in @output_ids>
  $self->param('inputlist', \@output_ids);
  $self->param('column_names', [<list with the names of your parameters>]);
 }

Dataflow betweeen analyses
++++++++++++++++++++++++++

Using branches
==============

 * ``1``  : Autoflow is activated by default, you want to use this channel between analysis working on the same input_ids
 * ``2``  : You want to use this channel when you are creating input_ids with a ``Bio::EnsEMBL::Hive::JobFactory`` for example
 * ``-1`` : If your job fails because of memory it will be redirected to this channel if you have an analysis linked to it. Otherwise it will simply fail. You may need to explicitly create the flow.
 * ``-2`` : If your job fails because of runtime it will be redirected to this channel if you have an analysis linked to it. Otherwise it will simply fail. You may need to explicitly create the flow.
 * ``-3`` : If your job fails for a known reason and it is supported by the RunnableDB (ensembl-analysis only)
 * Any other channel can be used

Which branch to choose?
=======================
When creating your pipeline you want to mostly use channel #1 when passing on the same information to one/multiple analyses or channel #2 when creating new input ids or if you don't have a 1-to-1 relationship between the analyses in term of jobs/input_id.

Autoflow
========

Unless you disabled autoflow in your module, all analyses will pass on whatever data it received from upstream channel(s) to channel #1. If your code is explicitly flowing data to channel #1 but there is nothing to flow, Hive will not overwrite channel #1 and it will autoflow the data received from upstream channel(s).

Disable outflow
---------------

::

 $self->input_job->autoflow(0);

Using semaphore (funnels)
+++++++++++++++++++++++++

A semaphore is a way of saying, as long as analysis B and its children are not successfully done, do not start analysis C. You can use any fan in the declaration of the analyses, it doesn't matter for the blocking. In guiHive, they are represented by boxes with different shades of blue. You can have multiple blocking analysis, but there can be only one blocked analysis. ::

 {
      -logic_name => 'create_toplevel_slices',
      -module     => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveSubmitAnalysis',
      -parameters => {
                       target_db => $self->o('reference_db'),
                       coord_system_name => 'toplevel',
                       slice => 1,
                       include_non_reference => 0,
                       top_level => 1,
                       slice_size => 1000000,  # this is for the size of the slice
                       },
      -flow_into => {
                       '2->A' => ['Hive_LincRNARemoveDuplicateGenes']
                       'A->1' => ['Hive_LincRNAEvaluator'],
                      },
        -rc_name    => 'default',
 },

You can also use the accu structure to give a list of parameters from the blocking analysis to the blocked analysis. ::

 {
  -logic_name => 'create_toplevel_slices',
  -module     => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveSubmitAnalysis',
  -parameters => {
                  target_db => $self->o('reference_db'),
                  coord_system_name => 'toplevel',
                  slice => 1,
                  include_non_reference => 0,
                  top_level => 1,
                  slice_size => 1000000,  # this is for the size of the slice
  },
  -flow_into => {
                 '2->A' => ['Hive_LincRNARemoveDuplicateGenes']
                 'A->1' => ['Hive_LincRNAEvaluator'],
  },
  -rc_name    => 'default',
 },
 {
  -logic_name => 'Hive_LincRNARemoveDuplicateGenes',
  -module     => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRemoveDuplicateGenes',
  -parameters => {
                  target_db => $self->o('source_db'),
  },
  -flow_into => {
                 1 => [':////accu?iid=[]'],
  },
  -rc_name    => 'default',
 },

Creating a pipeline configuration
+++++++++++++++++++++++++++++++++

Creating a configuration file
=============================

This has been implemented on the dev/hive_master branch. But it will be change for all the pipelines as we need to have a base config whith helper methods like creating lsf requirements.
Your config should inherit from ``Bio::EnsEMBL::Analysis::Hive::Config::HiveBaseConfig_conf`` which inherits from ``HiveGeneric_conf``. Of course in few cases like pipeline which does not use Ensembl APIs such as the UniProt database creation pipeline, your config will inherit from ``HiveGeneric_conf``.

Parameters and methods in the base config
-----------------------------------------

Parameters
**********

All these parameters needs to be set in your pipeline configuration. They should be NOT changed in the base configuration.

 * user : this will be the user with write access
 * port : the port will be used for all databases
 * password : password for the user with write access
 * user_r : user with read only access
 * use_tokens: default is 1 as we need tokens on the sanger farm, will be set to 0 when we move to EBI
 * pipe_dbname : name of your pipeline database, "pipeline_db"
 * pipe_db_server : name of the server where the pipeline database is
 * dna_dbname : name of your DNA database, "dna_db"
 * dna_db_server : name of the server where the DNA database is
 * databases_to_delete : a list of databases to delete if you specify -drop_databases 1 in the command line

Default parameters
******************

::

 use_tokens => 0,
 drop_databases => 0, # This should never be changed in any config file, only use it on the commandline
 databases_to_delete => [], # example: ['blast_db', 'refine_db', 'rough_db'],
 password_r => undef,

 enscode_root_dir => $ENV{ENSCODE},
 software_base_path => $ENV{LINUXBREW_HOME},
 binary_base => catdir($self->o('software_base_path'), 'bin'),
 clone_db_script_path => catfile($self->o('enscode_root_dir'), 'ensembl-analysis', 'scripts', 'clone_database.ksh'),

 data_dbs_server => $self->o('host'),
 data_dbs_port => $self->o('port'),
 data_dbs_user => $self->o('user'),
 data_dbs_password => $self->o('password'),

 dna_db_port => $self->o('port'),
 dna_db_user => $self->o('user_r'),
 dna_db_password => $self->o('password_r'),
 dna_db_driver => $self->o('hive_driver'),

 pipe_dbname => $self->o('dbowner').'_'.$self->o('pipeline_name').'_pipe',
 pipe_db_port => $self->o('port'),
 pipe_db_user => $self->o('user'),
 pipe_db_password => $self->o('password'),
 pipe_db_driver => $self->o('hive_driver'),

 'pipeline_db' => {
     -dbname => $self->o('pipe_dbname'),
     -host   => $self->o('pipe_db_server'),
     -port   => $self->o('pipe_db_port'),
     -user   => $self->o('pipe_db_user'),
     -pass   => $self->o('pipe_db_password'),
     -driver => $self->o('pipe_db_driver'),
 },

 'dna_db' => {
     -dbname => $self->o('dna_dbname'),
     -host   => $self->o('dna_db_server'),
     -port   => $self->o('dna_db_port'),
     -user   => $self->o('dna_db_user'),
     -pass   => $self->o('dna_db_password'),
     -driver => $self->o('dna_db_driver'),
 },

Methods
*******

If you think a method can/should be used by everyone, add it to the base configuration file
 * *lsf_resource_builder* : create the memory requirements, tokens, number of cpus, queue and extra parameters. Defaults are "normal" queue, 1 cpu, 10 tokens for each server specified in the parameters

Parameters and command line
===========================

Any parameter from your config which is called with ``$self->o('myparam')`` can be used in the commandline

Deleting databases you create in your pipeline
==============================================

If you populate the databases_to_delete array in you config and if these databases have -driver set in their hash, the databases will be deleted when you specify -drop_databases 1 on the commandline. It is best to set the driver to $self->o('hive_driver').

Naming your databases
=====================

The easiest way to name your database is to use the parameter dbowner, pipeline_name and another value(s) you concatenate.
dbowner is set as your linux USER value unless you set a EHIVE_USER or a dbowner value on the commandline ::

 exonerate_dbname => $self->o('dbowner').'_'.$self->o('pipeline_name').'_exonerate',

Getting blast parameters
========================
We use the same parameters for some analyses using the same programs like blast or exonerate. At the beginning, a master_config has been created but it means that people have to copy/paste between pipeline config...

Accessing config hash
---------------------

Here is the example if you want to use some blast parameters. In your pipeline config file::

 use Bio::EnsEMBL::Analysis::Tools::Utilities qw(get_analysis_settings);

``get_analysis_settings`` takes a least two arguments:
 * name of the package to load
 * name of the hash to retrieve from the configuration file loaded

The third one is a hashref to overwrite any parameter or to add new ones.
First ``get_analysis_settings`` will get the default hash, then it will overwrite any value by the values in the called hash and finally it will overwrite any values by the values contained in the hash given in third position. ::

 {
   -logic_name => 'blast_rnaseq',
   -module     => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveBlastRNASeqPep',
   -parameters => {
       input_db => $self->o('refine_output_db'),
       output_db => $self->o('blast_output_db'),
       dna_db => $self->o('dna_db'),
       # path to index to fetch the sequence of the blast hit to calculate % coverage
       indicate_index => $self->o('uniprotindex'),
       uniprot_index => [$self->o('uniprotdb')],
       blast_program => $self->o('blastp'),
       %{get_analysis_settings('Bio::EnsEMBL::Analysis::Hive::Config::BlastStatic','BlastGenscanPep', {BLAST_PARAMS => {-type => $self- >o('blast_type')}})},
       commandline_params => $self->o('blast_type') eq 'wu' ? '-cpus='.$self->default_options->{'use_threads'}.' -hitdist=40' : '-p blastp -W 40',
                },
   -rc_name => '2GB_blast',
   -wait_for => ['create_blast_output_db'],
 },

In this case, we will be able to access BLAST_PARAMS using $self->param('BLAST_PARAMS')

Creating a new config hash
--------------------------

These config hash must be stable. If you think that you need new parameters for you analysis like different thresholds, you have too choice:

 * use the third argument to overwrite the value returned by get_analysis_settings, good for debugging
 * add a new hash with a unique name, this is the preferred method unless you need to change values on the fly

::

 BlastStringentPep => {
        PARSER_PARAMS => {
                           -regex => '^(\w+\W\d+)',
                           -query_type => 'pep',
                           -database_type => 'pep',
                           -threshold_type => 'PVALUE',
                           -threshold => 0.00000001,
                         },
        BLAST_FILTER => 'Bio::EnsEMBL::Analysis::Tools::FeatureFilter',
        FILTER_PARAMS => {
                           -min_score => 300,
                           -prune => 1,
                         },
      },

Create a new config file
------------------------

 #. The package should be name Bio::EnsEMBL::Analysis::Hive::Config::<software>Static
 #. It should inherit from Bio::EnsEMBL::Analysis::Hive::Config::BaseStatic
 #. One method needs to be created: _master_config and it should return a hashref
 #. One key must be named "default" and should contain the default values

Generating the pipeline diagram
===============================

It can be useful to know how you pipeline should look like. Many format can be used but the best in our case would be SVG as it is a text format and all web browser should be able to read the file. ::

 ensembl-hive/scripts/generate_graph.pl -url mysql://RW_USER:PASSW@genebuildX:3306/DB_NAME -out HiveRNASeq_conf.svg

The extension determines the format or you can use the -f option. The best is to name the file like your configuration file. You can also change the description of the pipeline to be more interesting than the name of your Hive database.

Worker lifespan
===============

By default all workers have a lifespan of 1H. If your job is longer than the lifespan, it lets the job finish then kill the job with the exit code 0 or LSF kills your job based on the RUNLIMIT. You can change this behaviour in the resource_classes of your configuration file. The unit is the minute.::

 sub resource_classes {
  my $self = shift;
  return {
    %{ $self->SUPER::resource_classes() },  # inherit other stuff from the base class
    'default' => { LSF => [$self->lsf_resource_builder('normal', 1000, [$self->default_options->{'pipe_db_server'}]), 7*60]},
  };
 }

input id template
=================

You can create a template for input ids for the next analysis if for example you are using -1 and -2 branch with funnels (accu). You need to give all the parameters you need as it will overwrite the autoflow data. ::

 -flow_into => {
  -1 => {logic_5GB => {iid => '#iid#', param1 => '#param1#', filename => '#filename#'}},
 },

Pipeline wide parameters
========================

If you are using pipelinewide parameters, using a prefix could help other people understand when it is a "local" parameters and when it's not. For the RNASeq pipeline Thibaut Hourlier used 'wide\_'. We can change it to something different but we need to have one prefix for all our pipeline.

Input ids
=========

It is prefered to use ``Bio::EnsEMBL::Hive::JobFactory`` to create input_ids or to inherits from this module. If you call your input id iid it can be easily linked to other modules

SystemCmd
=========

If you want to run simple commands, you can just use this module.
Options to use in -parameters:

 #. cmd : it is imply the command(s) you want to run
 #. return_codes_2_branches **VERSION/2.3** : if your command returns a value different than 0 if it's successful, you can specify it there and use a different branch to process the result. Usefull for grep as it returns 1 if it could not find the word. return_codes_2_branches => {'<exit code>' => <branch number>}

Substitution
============

You can use substitution in your configuration. You need to call an option or a parameter you are "flowing" or a pipeline wide parameter ::

 'cmd' => 'mkdir -p #output_dir#'

Crazy substitution with #expr()expr#
====================================

If you need to access a a key from a hash you have in a parameters, you still can use substitution but you will need to use #expr()exp#. You can put any perl code between the brackets but you may need to trick perl sometimes. Of course it has to be between simple quotes.

Accessing a value in a hash
---------------------------

::

 '#expr(#target_db#->{-dbname})expr#'

Accessing values from the accu table
------------------------------------

::

 '#expr(join(" ", @{#filename#}))expr#'

Substitution of a parameter
---------------------------

::

 use 5.014000;

 '#expr(#filename# =~ s/.fa$//r)expr#'

You need to use perl version 5.14 or higher. The r modifier returns a modified string instead of modifying the lvalue string

Using customised tables
=======================

 1. In your configuration file, add a call to $self->db_cmd('CREATE TABLE ...')
 2. To insert data using a module

  ::

   my $table_adaptor = $self->db->get_NakedTableAdaptor();
   $table_adaptor->table_name('uniprot_sequences');
   my $db_row = [{ 'accession'  => $header,
                'source_db'  => $database,
                'pe_level'   => $pe_level,
                'biotype'    => $biotype,
                'group_name' => $group,
                'seq'        => $seq,
             }];
   $table_adaptor->store($db_row);

 3. To retrieve data from the table

    - use fetch_by_dbID (it uses the primary key column)::

       my $table_adaptor = $self->db->get_NakedTableAdaptor();
       $table_adaptor->table_name('uniprot_sequences');
       my $db_row = $table_adaptor->fetch_by_dbID($accession);

    - use fetch_all($constraint, $one_per_key, $key_list, $value_column)::

       my $table_adaptor = $self->db->get_NakedTableAdaptor();
       $table_adaptor->table_name('uniprot_sequences');

    - use a JobFactory module for you analysis, using this in the parameters hash::

       inputquery => 'SELECT accession FROM uniprot_sequence WHERE pe_level = #pe_level#',
       column_name => ['accession'],

Required parameters
===================
If you have a parameter which has to be set for your pipeline to work can be check with $self->param_required('myparam'). Hive will throw an exception if the check fails and returns the value if it is set.

Checking the parameter is defined
=================================

The method $self->param_is_defined('myparam') can be useful but be careful it is similar to using 'exists' on a hash. It returns 1 even if:
 * value is undef
 * value is ''

GuiHive
+++++++
The default colours are a bit strange the first time as green means ready and blue means successully done
READY DONE
Changing values
Change the values for the resource/parameters/...
Press the '+' button to validate the change
