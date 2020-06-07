
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
    """Method to test a Runnable"""

    # Find the actual class (type)
    if isinstance(runnableClass, str):
        runnableClass = find_module(runnableClass)

    class RunnableTester(runnableClass):

        def runTests(self):
            self.__configure()
            self.__job_life_cycle()
            self.__final_tests()

        def __configure(self):

            self.__config = config or {}
            self.__refEvents = refEvents.copy()

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
            job.retry_count = self.__config.get('is_retry', 0)
            job.autoflow = True
            job.lethal_for_worker = False
            job.transient_error = True
            self.input_job = job

        def __job_life_cycle(self):

            # Which methods should be run
            steps = ['fetch_input', 'run']
            if self.input_job.retry_count:
                steps.insert(0, 'pre_cleanup')
            if self.__config.get('execute_writes', 1):
                steps.append('write_output')
                steps.append('post_healthcheck')

            self.__created_worker_temp_directory = None

            try:
                for s in steps:
                    self.__run_method_if_exists(s)
            except CompleteEarlyException as e:
                event = CompleteEarlyEvent(e.args[0] if e.args else None)
                self.__compare_next_event(event)
            except Exception as e:
                self.__handle_exception(e)

            try:
                self.__run_method_if_exists('post_cleanup')
            except Exception as e:
                self.__handle_exception(e)

            self.__cleanup_worker_temp_directory()

        def __run_method_if_exists(self, method):
            """method is one of "pre_cleanup", "fetch_input", "run", "write_output", "post_cleanup"."""
            if hasattr(self, method):
                getattr(self, method)()

        def __handle_exception(self, e):
            if any(f for f in traceback.extract_tb(e.__traceback__) if f[2] == '__compare_next_event'):
                raise e
            else:
                # Job exception: check whether it is expected
                event = FailureEvent(type(e), e.args)
                self.__compare_next_event(event)

        def __final_tests(self):
            testcase.assertFalse(self.__refEvents, msg='The job has now ended and {} events have not been emitted'.format(len(self.__refEvents)))

            # Job attributes that the Runnable could have set
            for attr in ['autoflow', 'lethal_for_worker', 'transient_error']:
                tattr = "test_" + attr
                if tattr in self.__config:
                    testcase.assertEqual(getattr(self.input_job, attr), self.__config[tattr], msg='Final value of {}'.format(attr))

        # Public BaseRunnable interface
        ################################

        def worker_temp_directory(self):
            """Provide a temporary directory for the duration of the test"""
            if self.__created_worker_temp_directory is None:
                self.__created_worker_temp_directory = tempfile.mkdtemp()
            return self.__created_worker_temp_directory

        def __cleanup_worker_temp_directory(self):
            """Provide a temporary directory for the duration of the test"""
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
            testcase.assertTrue(self.__refEvents, msg='No more events are expected but {} was raised'.format(event))
            testcase.assertEqual(event, self.__refEvents.pop(0))

    # Build the Runnable
    # NOTE: not __init__ because we can't provide file descriptors, etc
    runnable = RunnableTester.__new__(RunnableTester)
    runnable.runTests()
