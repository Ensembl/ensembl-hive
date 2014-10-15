How to use MPI on eHive
=======================

---

In this tutorial we won't discuss the inner parts of the modules, our goal here is just to give you insights on how to set up the Hive to run jobs using Shared Memory Parallelism (threads) and Distributed Memory Parallelism (MPI).

If you have access to the EBI intranet this is a must read guide:

<http://www.ebi.ac.uk/systems-srv/public-wiki/index.php/EBI_Good_Computing_Guide>

Real examples can be found for the compara modules RAxML.pm and ExaML.pm, which are used for phylogenetic trees inference.

For running binaries we use the module Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::GenericRunnable, which gives us a good interface with the command line. Allowing us to submit different command lines and parsing/storing the results on the database. For more documentation on how to use the GenericRunnable please check the module documentation.


---

####Here it's an example on how to setup a module using Shared Memory Parallelism (threads):

>Given that you already compiled you code properly allowing it to use multiple threads/cores, this case should be very straightforward, the first thing you need to do is to add a new resource class to you pipeline. We also included some tips on how to compile code under MPI environment, but that will vary on different systems.


**1)** You need to setup a resource class that uses e.g. `16` cores and 16Gb of RAM:


	sub resource_classes {
    my ($self) = @_;
    return {
    	#...
		'16Gb_16_core_job' => { 'LSF' => '-q production-rh6 -n `16` -M16000  -R"select[mem>16000] span[hosts=1] rusage[mem=16000]"' },
    	#...
	}

**2)** You need to add the analysis to your pipeconfig:


	{   -logic_name => 'app_multi_core',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::ProteinTrees::Thread_app',
            -parameters => {
                'app_exe'                 => $self->o('app_pthreads_exe'),
                'cmd'                       => '#app_exe# -T `16` -input #alignment_file#',
            },
            -rc_name        => '16Gb_16_core_job',
	},


We would like to call your attention to the 'cmd' parameter, where we code the command line used to run Thread_app.
Note that in this case the parameter "-T" is set to `16` cores. This command line would vary for different programs.
You should check the documentation of the code you want to run.

With this basic configuration the Hive is already able to run Thread_app in 16 cores.  

---  

####Tips for compiling for Shared Memory Parallelism (OpenMP)

>This case will require a bit more attention, so please be very carefull by including/loading the right libraries/modules.
One of the most common source of problems is to compile the code with one MPI implementation and try to run it with another. This can be easily taken care by properly setting up your .bashrc to load the right modules.

**MPI Modules:**

You must compile and run your code with the same MPI implementation (openmpi or mpich2)

Most of the times you can load these modules by just using the command module, which provides packages for the dynamic modification of the user’s environment via modulefiles.

Here is how you could check if your system provides modules for the MPI implementations:

	module avail
	
	#if you have the openmpi module available, please load it:
	
	module load openmpi-x86_64


>If you don't have modules for the MPI environment available on your system, please make sure you include the right libraries.


**1)** Include the module on your .bashrc:
You must load the MPI module (or libraries) on your source file (e.g. ~/.bashrc). Otherwise your code won't run properlly.


**2)** You need to setup a resource class that uses e.g. `64` cores and 16Gb of RAM:

	sub resource_classes {
    my ($self) = @_;
    return {
     		# ...   
			'16Gb_64c_mpi' => {'LSF' => '-q mpi -n 64 -a openmpi -M16000 -R"select[mem>16000] rusage[mem=16000] same[model] span[ptile=4]"' },
  	 		# ...
  		};
	}
	
Nothe the option span[ptile=4], this option specifies the granularity in which LSF will split the jobs/per node. In this example we ask for at least 4 jobs to be executed in the same machine. This might affect queuing times. 

**3)** You need to add the analysis to your pipeconfig:

      {   -logic_name => 'MPI_app',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::ProteinTrees::MPI_app',
            -parameters => {
                'mpi_exe'        => $self->o('mpi_exe'),
            },
            -rc_name => '4Gb_64c_mpi',
            # ...       
      },


---

**In this section we will briefly describe how to create a module that uses MPI.**



Module:

	sub param_defaults {
    my $self = shift;
    return {
        %{ $self->SUPER::param_defaults },
        	# Note that Examl needs MPI and has to be run through mpirun.lsf
        	'cmd' => 'cmd 1 ; cmd  2 ; mpirun.lsf -np `64` -mca btl tcp,self #examl_exe# -examl_parameter_1 EX1 -examl_parameter_2 EX2',
   		};
	}

###**!!!tmp files!!!!**

	Because Examl is using MPI, it has to be run in a shared directory
	Here we override the eHive method to use #examl_dir# instead
	sub worker_temp_directory_name {
    my $self = shift @_;

        my $username = $ENV{'USER'};
        my $worker_id = $self->worker ? $self->worker->dbID : "standalone.$$";
        return $self->param('examl_dir')."/worker_${username}.${worker_id}/";
	}


>**Note: If you have access to Intel compilers, we strongly recommend you to try compiling your code with it and checking for performance improvements**