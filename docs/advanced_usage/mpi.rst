
.. _howto-mpi:

How to use MPI
==============

.. note::
        With this tutorial, our goal is to give insights on how to set up
        eHive to run Jobs using Shared Memory Parallelism (threads) and
        Distributed Memory Parallelism (MPI).


First of all, your institution / compute-farm provider may have
documentation on this topic. Please refer to them for implementation
details (intranet-only links:
`EBI <http://www.ebi.ac.uk/systems-srv/public-wiki/index.php/EBI_Good_Computing_Guide_new>`__,
`Sanger
Institute <http://mediawiki.internal.sanger.ac.uk/index.php/How_to_run_MPI_jobs_on_the_farm>`__)

You can find real examples in the
`ensembl-compara <https://github.com/Ensembl/ensembl-compara>`__
repository. It ships Runnables used for phylogenetic trees inference:
`RAxML <https://github.com/Ensembl/ensembl-compara/blob/HEAD/modules/Bio/EnsEMBL/Compara/RunnableDB/ProteinTrees/RAxML.pm>`__
and
`ExaML <https://github.com/Ensembl/ensembl-compara/blob/HEAD/modules/Bio/EnsEMBL/Compara/RunnableDB/ProteinTrees/ExaML.pm>`__.
They look very light-weight (only command-line definitions) because most
of the logic is in the base class (*GenericRunnable*), but nevertheless
show the command lines used and the parametrisation of multi-core and
MPI runs.

.. The default language is set to perl. Non-perl code-blocks have to define
   their own language setting
.. highlight:: perl

How to setup a module using Shared Memory Parallelism (threads)
---------------------------------------------------------------

If you have already compiled your code and know how to enable the
use of multiple threads / cores, this case should be very
straightforward. It basically consists in defining the proper
Resource Class in your pipeline.

1. You need to setup a Resource Class that encodes those requirements
   e.g. *16 cores and 24Gb of RAM*:

   ::

       sub resource_classes {
         my ($self) = @_;
         return {
           #...
           '24Gb_16_core_job' => { 'LSF' => '-n 16 -M24000  -R"select[mem>24000] span[hosts=1] rusage[mem=24000]"' },
           #...
         }
       }

2. You need to add the Analysis to your PipeConfig:

   ::

       {   -logic_name => 'app_multi_core',
           -module     => 'Namespace::Of::Thread_app',
           -parameters => {
                   'app_exe'    => $self->o('app_pthreads_exe'),
                   'cmd'        => '#app_exe# -T 16 -input #alignment_file#',
           },
           -rc_name    => '24Gb_16_core_job',
       },

   We would like to call your attention to the ``cmd`` parameter, where
   we define the command line used to run Thread\_app. Note that the
   actual command line would vary between different programs, but in
   this case, the parameter ``-T`` is set to 16 cores. You should check
   the documentation of the code you want to run to find out how to
   define the number of threads it will use.

Just with this basic configuration, eHive is able to run Thread\_app
in 16 cores.


How to setup a module using Distributed Memory Parallelism (MPI)
----------------------------------------------------------------

This case requires a bit more attention, so please be very careful
in including / loading the right libraries / modules.
The instructions below may not apply to your system. In doubt, contact your
systems administrators.

Tips for compiling for MPI
~~~~~~~~~~~~~~~~~~~~~~~~~~

MPI usually comes in two implementations: OpenMPI and MPICH. A
common source of problems is to compile the code with one MPI
implementation and try to run it with another. You must compile and run
your code with the **same** MPI implementation. This can be easily taken
care by properly setting up your .bashrc.

If you have access to Intel compilers, we strongly recommend you to try
compiling your code with it and checking for performance improvements.

If your compute environment uses `Module <http://modules.sourceforge.net/>`__
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

*Module* provides configuration files (module-files) for the dynamic
modification of your environment.

Here is how to list the modules that your system provides:

.. code-block:: none

        module avail

And how to load one (mpich3 in this example):

.. code-block:: none

        module load mpich3/mpich3-3.1-icc

Don't forget to put this line in your ``~/.bashrc`` so that it is
automatically loaded.

Otherwise, follow the recommended usage in your institute
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you don't have modules for the MPI environment available on your
system, please make sure you include the right libraries (PATH, and any
other environment variables).

The eHive bit
~~~~~~~~~~~~~

Here again, once the environment is properly set up, we only have to
define the correct Resource Class and command lines in eHive.

1. You need to setup a Resource Class that uses e.g. *64 cores and 16Gb
   of RAM*:

   ::

       sub resource_classes {
         my ($self) = @_;
         return {
           # ...
           '16Gb_64c_mpi' => {'LSF' => '-q mpi-rh7 -n 64 -M16000 -R"select[mem>16000] rusage[mem=16000] same[model] span[ptile=4]"' },
           # ...
         };
       }

   The Resource description is specific to our LSF environment, so adapt
   it to yours, but:

   -  ``-q mpi-rh7`` is needed to tell LSF you will run a job (Worker) in the
      MPI environment. Note that some LSF installations will require you
      to use an additional ``-a`` option.
   -  ``same[model]`` is needed to ensure that the selected compute nodes
      all have the same hardware. You may also need something like
      ``select[avx]`` to select the nodes that have the `AVX instruction
      set <https://en.wikipedia.org/wiki/Advanced_Vector_Extensions>`__
   -  ``span[ptile=4]``, this option specifies the granularity in which LSF
      will split the jobs/per node. In this example we ask for each machine
      to be allocated a multiple of four cores. This might affect queuing
      times. The memory requested is allocated for each _ptile_ (so
      64/4*16GB=256GB in total in the example).

2. You need to add the Analysis to your PipeConfig:

   ::

       {   -logic_name => 'MPI_app',
           -module     => 'Bio::EnsEMBL::Compara::RunnableDB::ProteinTrees::MPI_app',
           -parameters => {
               'mpi_exe'     => $self->o('mpi_exe'),
           },
           -rc_name => '16Gb_64c_mpi',
           # ...
       },


How to write a module that uses MPI
-----------------------------------

Here is an excerpt of Ensembl Compara's
`ExaML <https://github.com/Ensembl/ensembl-compara/blob/HEAD/modules/Bio/EnsEMBL/Compara/RunnableDB/ProteinTrees/ExaML.pm>`__
MPI module. Note that LSF needs the MPI command to be run through
*mpirun*. You can also run several single-threaded commands in the same
Runnable.

::

    sub param_defaults {
        my $self = shift;
        return {
            %{ $self->SUPER::param_defaults },
            'cmd' => 'cmd 1 ; cmd  2 ; #mpirun_exe# #examl_exe# -examl_parameter_1 value1 -examl_parameter_2 value2',
        };
    }

.. _worker_temp_directory_name-mpi:

Temporary files
~~~~~~~~~~~~~~~

In our case, Examl uses MPI and wants to share data via the filesystem too.
In this specific Runnable, Examl is set to run in eHive's managed temporary
directory, which by default is under /tmp which is not shared across nodes on
our compute cluster.
We have to override the eHive method to use a shared directory (``$self->o('examl_dir')``) instead.

This can be done at the resource class level, by adding
``"-worker_base_tmp_dir ".$self->o('examl_dir')`` to the
``worker_cmd_args`` attribute of the resource-class

