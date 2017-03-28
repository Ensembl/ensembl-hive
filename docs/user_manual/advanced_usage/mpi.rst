How to use MPI on eHive
=======================

With this tutorial, our goal is to give insights on how to set up the
Hive to run jobs using Shared Memory Parallelism (threads) and
Distributed Memory Parallelism (MPI).

First of all, your institution / compute-farm provider may have
documentation on this topic. Please refer to them for implementation
details (intranet-only links:
`EBI <http://www.ebi.ac.uk/systems-srv/public-wiki/index.php/EBI_Good_Computing_Guide>`__,
`Sanger
institute <http://mediawiki.internal.sanger.ac.uk/index.php/How_to_run_MPI_jobs_on_the_farm>`__)

We won't discuss the inner parts of the modules, but real examples can
be found in the
`ensembl-compara <https://github.com/Ensembl/ensembl-compara>`__
repository. It ships modules used for phylogenetic trees inference:
`RAxML <https://github.com/Ensembl/ensembl-compara/blob/release/77/modules/Bio/EnsEMBL/Compara/RunnableDB/ProteinTrees/RAxML.pm>`__
and
`ExaML <https://github.com/Ensembl/ensembl-compara/blob/feature/update_pipeline/modules/Bio/EnsEMBL/Compara/RunnableDB/ProteinTrees/ExaML.pm>`__.
They look very light-weight (only command-line definitions) because most
of the logic is in the base class (*GenericRunnable*), but nevertheless
show the command lines used and the parametrization of multi-core and
MPI runs.

--------------

How to setup a module using Shared Memory Parallelism (threads)
---------------------------------------------------------------

    If you have already compiled your code and know how to enable the
    use of multiple threads / cores, this case should be very
    straightforward. It basically consists in defining the proper
    resource class in your pipeline. We also include some tips on how to
    compile code under MPI environment, but be aware that will vary
    across systems.

1. You need to setup a resource class that encodes those requirements
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

2. You need to add the analysis to your pipeconfig:

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

Just with this basic configuration, the Hive is able to run Thread\_app
in 16 cores.

--------------

How to setup a module using Distributed Memory Parallelism (MPI)
----------------------------------------------------------------

    This case requires a bit more attention, so please be very careful
    in including / loading the right libraries / modules.

Tips for compiling for MPI
~~~~~~~~~~~~~~~~~~~~~~~~~~

MPI usually comes in two implementations: OpenMPI and mpich2. One of the
most common source of problems is to compile the code with one MPI
implementation and try to run it with another. You must compile and run
your code with the **same** MPI implementation. This can be easily taken
care by properly setting up your .bashrc to load the right modules.

If you have access to Intel compilers, we strongly recommend you to try
compiling your code with it and checking for performance improvements.

If your compute environment uses `Module <http://modules.sourceforge.net/>`__
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

*Module* provides configuration files (module-files) for the dynamic
modification of the user’s environment.

Here is how to list the modules that your system provides:

::

        module avail

And how to load one (OpenMPI in this example:

::

        module load openmpi-x86_64

Don't forget to put this line in your ``~/.bashrc`` so that it is
automatically loaded.

Otherwise, follow the recommended usage in your institute
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you don't have modules for the MPI environment available on your
system, please make sure you include the right libraries (PATH, and any
other environment variables)

The Hive bit
~~~~~~~~~~~~

Here again, once the environment is properly set up, we only have to
define the correct resource class and comand lines in Hive.

1. You need to setup a resource class that uses e.g. *64 cores and 16Gb
   of RAM*:

   ::

       sub resource_classes {
         my ($self) = @_;
         return {
           # ...
           '16Gb_64c_mpi' => {'LSF' => '-q mpi -a openmpi -n 64 -M16000 -R"select[mem>16000] rusage[mem=16000] same[model] span[ptile=4]"' },
           # ...
         };
       }

   The resource description is specific to our LSF environment, so adapt
   it to yours, but:

-  ``-q mpi -a openmpi`` is needed to tell LSF you will run a job in the
   MPI/OpenMPI environment
-  ``same[model]`` is needed to ensure that the selected compute nodes
   all have the same hardware. You may also need something like
   ``select[avx]`` to select the nodes that have the `AVX instruction
   set <http://en.wikipedia.org/wiki/Advanced_Vector_Extensions>`__
-  ``span[ptile=4]``, this option specifies the granularity in which LSF
   will split the jobs/per node. In this example we ask for at least 4
   jobs to be executed in the same machine. This might affect queuing
   times.

3. You need to add the analysis to your pipeconfig:

   ::

       {   -logic_name => 'MPI_app',
           -module     => 'Bio::EnsEMBL::Compara::RunnableDB::ProteinTrees::MPI_app',
           -parameters => {
               'mpi_exe'     => $self->o('mpi_exe'),
           },
           -rc_name => '16Gb_64c_mpi',
           # ...
       },

--------------

How to write a module that uses MPI
-----------------------------------

Here is an excerpt of Ensembl Compara's
`ExaML <https://github.com/Ensembl/ensembl-compara/blob/feature/update_pipeline/modules/Bio/EnsEMBL/Compara/RunnableDB/ProteinTrees/ExaML.pm>`__
MPI module. Note that LSF needs the MPI command to be run through
mpirun.lsf You can also run several single-threaded commands in the same
runnable.

::

        sub param_defaults {
          my $self = shift;
          return {
            %{ $self->SUPER::param_defaults },
            'cmd' => 'cmd 1 ; cmd  2 ; mpirun.lsf -np 64 -mca btl tcp,self #examl_exe# -examl_parameter_1 value1 -examl_parameter_2 value2',
          };
        }

!!!Temporary files!!!
~~~~~~~~~~~~~~~~~~~~~

Because Examl is using MPI, it has to be run in a shared directory Here
we override the eHive method to use #examl\_dir# instead

::

        sub worker_temp_directory_name {
          my $self = shift @_;
          my $username = $ENV{'USER'};
          my $worker_id = $self->worker ? $self->worker->dbID : "standalone.$$";
          return $self->param('examl_dir')."/worker_${username}.${worker_id}/";
        }

