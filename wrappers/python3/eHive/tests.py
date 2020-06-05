
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
import sys
import traceback

from .params import ParamContainer
from .process import Job, CompleteEarlyException
from .utils import find_module

# The events that can be emitted during the execution of a job
WarningEvent = collections.namedtuple('WarningEvent', ['message', 'is_error'])
DataflowEvent = collections.namedtuple('DataflowEvent', ['output_ids', 'branch_name_or_code'])
CompleteEarlyEvent = collections.namedtuple('CompleteEarlyEvent', ['message'])
FailureEvent = collections.namedtuple('FailureEvent', ['exception', 'args'])


def testRunnable(runnable, inputParameters, refEvents, config=None):
    """Method to test a Runnable"""
    _RunnableTester(runnable, inputParameters, refEvents, config or {})

class _RunnableTester:

    def __init__(self, runnable, inputParameters, refEvents, config):
        if isinstance(runnable, str):
            runnable = find_module(runnable)
        # Build the Runnable
        # NOTE: not __init__ because we can't provide file descriptors, etc
        self.runnable = runnable.__new__(runnable)
        # Override API methods
        self.runnable.warning = self.warning
        self.runnable.dataflow = self.dataflow
        self.runnable.worker_temp_directory = self.worker_temp_directory

        # Initialise the tester's attributes
        self.refEvents = refEvents
        self.__created_worker_temp_directory = None

        # Build the parameter hash
        paramsDict = {}
        paramsDict.update(self.runnable.param_defaults())
        paramsDict.update(inputParameters)
        params = ParamContainer(paramsDict)
        self.runnable._BaseRunnable__params = params

        # Build the Job object
        is_retry = config.get('is_retry', 0)
        job = Job()
        job.dbID = None
        job.input_id = str(inputParameters)  # FIXME: this should be a Perl stringification, not a Python one
        job.retry_count = is_retry
        job.autoflow = True
        job.lethal_for_worker = False
        job.transient_error = True
        self.runnable.input_job = job

        # Which methods should be run
        steps = ['fetch_input', 'run']
        if is_retry:
            steps.insert(0, 'pre_cleanup')
        if config.get('execute_writes', 1):
            steps.append('write_output')
            steps.append('post_healthcheck')

        # The actual life-cycle
        try:
            for s in steps:
                self.__run_method_if_exists(self.runnable, s)
        except CompleteEarlyException as e:
            event = CompleteEarlyEvent(e.args[0] if e.args else None)
            self._compare_next_event(event)
        except Exception as e:
            self._handle_exception(e)

        try:
            self.__run_method_if_exists(self.runnable, 'post_cleanup')
        except Exception as e:
            self._handle_exception(e)

        if self.__created_worker_temp_directory:
            shutil.rmtree(self.__created_worker_temp_directory)

        if self.refEvents:
            msg = 'The job has now ended and {} events have not been emitted: {}'.format(len(self.refEvents), self.refEvents)
            raise AssertionError(msg)

        # Job attributes that the Runnable could have set
        for attr in ['autoflow', 'lethal_for_worker', 'transient_error']:
            tattr = "test_" + attr
            if tattr in config:
                assert getattr(job, attr) == config[tattr], '{} is {} but was expecting {}'.format(attr, getattr(job, attr), config[tattr])

    def __run_method_if_exists(self, runnable, method):
        """method is one of "pre_cleanup", "fetch_input", "run", "write_output", "post_cleanup".
        We only the call the method if it exists to save a trip to the database."""
        if hasattr(runnable, method):
            getattr(runnable, method)()

    def _handle_exception(self, e):
        (_, _, tb) = sys.exc_info()
        if any(f for f in traceback.extract_tb(tb) if f[2] == '_compare_next_event'):
            raise e
        else:
            # Job exception: check whether it is expected
            event = FailureEvent(type(e), e.args)
            self._compare_next_event(event)


    # Public BaseRunnable interface
    ################################

    def warning(self, message, is_error = False):
        """Test that the warning event generated is expected"""
        event = WarningEvent(message, is_error)
        self._compare_next_event(event)

    def dataflow(self, output_ids, branch_name_or_code = 1):
        """Test that the dataflow event generated is expected"""
        if branch_name_or_code == 1:
            self.input_job.autoflow = False
        event = DataflowEvent(output_ids, branch_name_or_code)
        self._compare_next_event(event)
        return []

    def worker_temp_directory(self):
        """Provide a temporary directory for the duration of the test"""
        if self.__created_worker_temp_directory is None:
            self.__created_worker_temp_directory = tempfile.mkdtemp()
        return self.__created_worker_temp_directory

    def _compare_next_event(self, event):
        if self.refEvents:
            refEvent = self.refEvents.pop(0)
            if type(event) == type(refEvent):
                print(event, refEvent)
                assert tuple(event) == tuple(refEvent), 'Correct event parameters: {} vs {}'.format(event, refEvent)
            else:
                raise AssertionError('Got a {} but was expected a {}'.format(type(event).__name__, type(refEvent).__name__))
        else:
            raise AssertionError('No more events are expected but {} was raised'.format(event))

