
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
All testing functions, e.g. how to test a Runnable
"""

import collections
import tempfile
import shutil
import traceback

from .params import ParamContainer
from .process import Job, CompleteEarlyException
from .utils import find_module

# The events that can be emitted during the execution of a job
WarningEvent = collections.namedtuple('WarningEvent', ['message', 'is_error'])
DataflowEvent = collections.namedtuple('DataflowEvent', ['output_ids', 'branch_name_or_code'])
CompleteEarlyEvent = collections.namedtuple('CompleteEarlyEvent', ['message'])
FailureEvent = collections.namedtuple('FailureEvent', ['exception', 'args'])


def testRunnable(testcase, runnableClass, inputParameters, refEvents, config=None):
    """Method to test a Runnable

    Args:
        testcase: instance of unittest.TestCase, which is used to do the actual tests.
        runnableClass: Runnable being tested. Can be a string of the actual type.
        inputParameters: dictionary of input parameters. Will override the Runnable's
                         param_defaults() dictionary.
        refEvents: list of "events" the Runnable is expected to raise (in the right
                   order). Accepted events are
                   - WarningEvent.
                   - DataflowEvent.
                   - CompleteEarlyEvent.
                   - FailureEvent.
        config: extra configuration options, given as a dictionary. Accepted keys are
                - is_retry: bool or int, default False.
                            whether the job is considered a retry (i.e.  whether
                            pre_cleanup should run).
                - no_write: bool, default False.
                            whether write_output is skipped.
                - no_cleanup: bool, default False.
                              whether the temporary directory is removed at the end
                              of the run.
                - test_autoflow: bool, default not set.
                                 when set, check that this is the final value of the
                                 job's autoflow attribute.
                - test_lethal_for_worker: bool, default not set.
                                          when set, check that this is the final value
                                          of the job's lethal_for_worker attribute.
                - test_transient_error: bool, default not set.
                                        when set, check that this is the final value
                                        of the job's lethal_for_worker attribute.
    """

    # Find the actual class (type)
    if isinstance(runnableClass, str):
        runnableClass = find_module(runnableClass)

    class RunnableTester(runnableClass):
        """Helper class to provide a test-enabled version of the requested Runnable"""

        def runTests(self):
            """Entry point of RunnableTester. Run everything in order"""
            self.__configure()
            self.__job_life_cycle()
            self.__final_tests()

        def __configure(self):
            """Initialise all the parameters the Runnable may need"""

            # Copy all the input parameters in the class instance itself
            self.__config = config or {}
            self.__refEvents = refEvents.copy()  # Don't modify the original list

            # Build the parameter hash
            paramsDict = {}
            paramsDict.update(runnable.param_defaults())
            paramsDict.update(inputParameters)
            params = ParamContainer(paramsDict)
            self._BaseRunnable__params = params

            # Build the Job object
            job = Job()
            job.dbID = None
            job.input_id = str(inputParameters)  # FIXME: this should be a Perl stringification, not a Python one
            job.retry_count = int(self.__config.get('is_retry', False))
            job.autoflow = True
            job.lethal_for_worker = False
            job.transient_error = True
            self.input_job = job

        def __job_life_cycle(self):
            """Run the job's life cycle. This must match BaseRunnable.__job_life_cycle"""

            # Which methods should be run
            steps = ['fetch_input', 'run']
            if self.input_job.retry_count:
                steps.insert(0, 'pre_cleanup')
            if not self.__config.get('no_write'):
                steps.append('write_output')
                steps.append('post_healthcheck')

            # We need to manager the temp directory since GuestProcess/Worker are not around
            self.__created_worker_temp_directory = None

            try:
                for s in steps:
                    self.__run_method_if_exists(s)
            except CompleteEarlyException as e:
                # CompleteEarlyException must be declared in the test plan
                event = CompleteEarlyEvent(e.args[0] if e.args else None)
                self.__compare_next_event(event)
            except Exception as e:
                self.__handle_exception(e)

            try:
                self.__run_method_if_exists('post_cleanup')
            except Exception as e:
                self.__handle_exception(e)

            if not self.__config.get('no_cleanup'):
                self.__cleanup_worker_temp_directory()

        def __run_method_if_exists(self, method):
            """Run the method (one of "fetch_input", "run", "write_output",
            etc) if defined in the Runnable."""
            if hasattr(self, method):
                getattr(self, method)()

        def __handle_exception(self, e):
            """Capture and check the Runnable's own exceptions whilst letting
            the testcase's exceptions pass through"""
            if any(f for f in traceback.extract_tb(e.__traceback__) if f[2] == '__compare_next_event'):
                raise e
            else:
                # Job exception: check whether it is expected
                event = FailureEvent(type(e), e.args)
                self.__compare_next_event(event)

        def __final_tests(self):
            """Extra tests once the job has ended"""
            testcase.assertFalse(self.__refEvents, msg='The job has now ended and {} events have not been emitted'.format(len(self.__refEvents)))

            # Job attributes that the Runnable could have set and we want to test
            for attr in ['autoflow', 'lethal_for_worker', 'transient_error']:
                tattr = "test_" + attr
                if tattr in self.__config:
                    testcase.assertEqual(getattr(self.input_job, attr), self.__config[tattr], msg='Final value of {}'.format(attr))

        # Overridden BaseRunnable interface
        ###################################

        def worker_temp_directory(self):
            """Provide a temporary directory for the duration of the test.
            This functionality was handled by the Perl side (via GuestProcess
            but has to be reimplemented."""
            if self.__created_worker_temp_directory is None:
                self.__created_worker_temp_directory = tempfile.mkdtemp()
            return self.__created_worker_temp_directory

        def __cleanup_worker_temp_directory(self):
            """Remove the temporary directory created by worker_temp_directory.
            Again, this was handled by the Perl side but has to be
            reimplemented."""
            if self.__created_worker_temp_directory:
                shutil.rmtree(self.__created_worker_temp_directory)

        def warning(self, message, is_error=False):
            """Test that the warning event generated is expected"""
            event = WarningEvent(message, is_error)
            self.__compare_next_event(event)

        def dataflow(self, output_ids, branch_name_or_code=1):
            """Test that the dataflow event generated is expected"""
            if branch_name_or_code == 1:
                self.input_job.autoflow = False
            event = DataflowEvent(output_ids, branch_name_or_code)
            self.__compare_next_event(event)
            return [1]

        def __compare_next_event(self, event):
            """Helper method for warning and dataflow.
            Check that the event that has been generated is expected."""
            testcase.assertTrue(self.__refEvents, msg='No more events are expected but {} was raised'.format(event))
            testcase.assertEqual(event, self.__refEvents.pop(0))

    # Build the Runnable
    # NOTE: not __init__ because we can't provide file descriptors, etc
    runnable = RunnableTester.__new__(RunnableTester)
    runnable.runTests()
