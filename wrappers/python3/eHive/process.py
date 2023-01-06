
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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
This module mainly implements python's counterpart of GuestProcess. Read
the later for more information about the JSON protocol used to communicate.
"""

import json
import os
import sys
import traceback
import unittest
import warnings

from . import params

__version__ = "5.0"


class Job:
    """Dummy class to hold job-related information"""
    pass

class CompleteEarlyException(Exception):
    """Can be raised by a derived class of BaseRunnable to indicate an early successful termination"""
    pass
class JobFailedException(Exception):
    """Can be raised by a derived class of BaseRunnable to indicate an early unsuccessful termination"""
    pass
class HiveJSONMessageException(Exception):
    """Raised when we could not parse the JSON message coming from GuestProcess"""
    pass
class LostHiveConnectionException(Exception):
    """Raised when the process has lost the communication pipe with the Perl side"""
    pass


class BaseRunnable:
    """This is the counterpart of GuestProcess. Note that most of the methods
    are private to be hidden in the derived classes.

    This class can be used as a base-class for people to redefine fetch_input(),
    run() and/or write_output() (and/or pre_cleanup(), post_cleanup()).
    Jobs are supposed to raise CompleteEarlyException in case they complete before
    reaching. They can also raise JobFailedException to indicate a general failure
    """

    # Private BaseRunnable interface
    #################################

    def __init__(self, read_fileno, write_fileno, debug):
        # We need the binary mode to disable the buffering
        self.__read_pipe = os.fdopen(read_fileno, mode='rb', buffering=0)
        self.__write_pipe = os.fdopen(write_fileno, mode='wb', buffering=0)
        self.__pid = os.getpid()
        self.debug = debug
        self.__process_life_cycle()

    def __print_debug(self, *args):
        if self.debug > 1:
            print("PYTHON {0}".format(self.__pid), *args, file=sys.stderr)

    # FIXME: we can probably merge __send_message and __send_response

    def __send_message(self, event, content):
        """seralizes the message in JSON and send it to the parent process"""
        def default_json_encoder(o):
            self.__print_debug("Cannot serialize {0} (type {1}) in JSON".format(o, type(o)))
            return 'UNSERIALIZABLE OBJECT'
        j = json.dumps({'event': event, 'content': content}, indent=None, default=default_json_encoder)
        self.__print_debug('__send_message:', j)
        # UTF8 encoding has never been tested. Just hope it works :)
        try:
            self.__write_pipe.write(bytes(j+"\n", 'utf-8'))
        except BrokenPipeError:
            raise LostHiveConnectionException("__write_pipe") from None

    def __send_response(self, response):
        """Sends a response message to the parent process"""
        self.__print_debug('__send_response:', response)
        # Like above, UTF8 encoding has never been tested. Just hope it works :)
        try:
            self.__write_pipe.write(bytes('{"response": "' + str(response) + '"}\n', 'utf-8'))
        except BrokenPipeError:
            raise LostHiveConnectionException("__write_pipe") from None

    def __read_message(self):
        """Read a message from the parent and parse it"""
        try:
            self.__print_debug("__read_message ...")
            l = self.__read_pipe.readline()
            self.__print_debug(" ... -> ", l[:-1].decode())
            return json.loads(l.decode())
        except BrokenPipeError:
            raise LostHiveConnectionException("__read_pipe") from None
        except ValueError as e:
            # HiveJSONMessageException is a more meaningful name than ValueError
            raise HiveJSONMessageException from e

    def __send_message_and_wait_for_OK(self, event, content):
        """Send a message and expects a response to be 'OK'"""
        self.__send_message(event, content)
        response = self.__read_message()
        if response['response'] != 'OK':
            raise HiveJSONMessageException("Received '{0}' instead of OK".format(response))

    def __process_life_cycle(self):
        """Simple loop: wait for job parameters, do the job's life-cycle"""
        self.__send_message_and_wait_for_OK('VERSION', __version__)
        self.__send_message_and_wait_for_OK('PARAM_DEFAULTS', self.param_defaults())
        self.__created_worker_temp_directory = None
        while True:
            self.__print_debug("waiting for instructions")
            config = self.__read_message()
            if 'input_job' not in config:
                self.__print_debug("no params, this is the end of the wrapper")
                return
            self.__job_life_cycle(config)

    def __job_life_cycle(self, config):
        """Job's life-cycle. See GuestProcess for a description of the protocol to communicate with the parent"""
        self.__print_debug("__life_cycle")

        # Parameters
        self.__params = params.ParamContainer(config['input_job']['parameters'], self.debug > 1)

        # Job attributes
        self.input_job = Job()
        for x in ['dbID', 'input_id', 'retry_count']:
            setattr(self.input_job, x, config['input_job'][x])
        self.input_job.autoflow = True
        self.input_job.lethal_for_worker = False
        self.input_job.transient_error = True

        # Worker attributes
        self.debug = config['debug']

        # Which methods should be run
        steps = [ 'fetch_input', 'run' ]
        if self.input_job.retry_count > 0:
            steps.insert(0, 'pre_cleanup')
        if config['execute_writes']:
            steps.append('write_output')
            steps.append('post_healthcheck')
        self.__print_debug("steps to run:", steps)
        self.__send_response('OK')

        # The actual life-cycle
        died_somewhere = False
        try:
            for s in steps:
                self.__run_method_if_exists(s)
        except CompleteEarlyException as e:
            self.warning(e.args[0] if len(e.args) else repr(e), False)
        except LostHiveConnectionException as e:
            # Mothing we can do, let's just exit
            raise
        except Exception as e:
            died_somewhere = True
            self.warning( self.__traceback(e, 2), True)

        try:
            self.__run_method_if_exists('post_cleanup')
        except LostHiveConnectionException as e:
            # Mothing we can do, let's just exit
            raise
        except Exception as e:
            died_somewhere = True
            self.warning( self.__traceback(e, 2), True)

        job_end_structure = {'complete' : not died_somewhere, 'job': {}, 'params': {'substituted': self.__params.param_hash, 'unsubstituted': self.__params.unsubstituted_param_hash}}
        for x in [ 'autoflow', 'lethal_for_worker', 'transient_error' ]:
            job_end_structure['job'][x] = getattr(self.input_job, x)
        self.__send_message_and_wait_for_OK('JOB_END', job_end_structure)

    def __run_method_if_exists(self, method):
        """method is one of "pre_cleanup", "fetch_input", "run", "write_output", "post_cleanup".
        We only the call the method if it exists to save a trip to the database."""
        if hasattr(self, method):
            self.__send_message_and_wait_for_OK('JOB_STATUS_UPDATE', method)
            getattr(self, method)()

    def __traceback(self, exception, skipped_traces):
        """Remove "skipped_traces" lines from the stack trace (the eHive part)"""
        s1 = traceback.format_exception_only(type(exception), exception)
        l = traceback.extract_tb(exception.__traceback__)[skipped_traces:]
        s2 = traceback.format_list(l)
        return "".join(s1+s2)


    # Public BaseRunnable interface
    ################################

    def warning(self, message, is_error = False):
        """Store a message in the log_message table with is_error indicating whether the warning is actually an error or not"""
        self.__send_message_and_wait_for_OK('WARNING', {'message': message, 'is_error': is_error})

    def dataflow(self, output_ids, branch_name_or_code = 1):
        """Dataflows the output_id(s) on a given branch (default 1). Returns whatever the Perl side returns"""
        if branch_name_or_code == 1:
            self.input_job.autoflow = False
        self.__send_message('DATAFLOW', {'output_ids': output_ids, 'branch_name_or_code': branch_name_or_code, 'params': {'substituted': self.__params.param_hash, 'unsubstituted': self.__params.unsubstituted_param_hash}})
        return self.__read_message()['response']

    def worker_temp_directory(self):
        """Returns the full path of the temporary directory created by the worker.
        """
        if self.__created_worker_temp_directory is None:
            self.__send_message('WORKER_TEMP_DIRECTORY', None)
            self.__created_worker_temp_directory = self.__read_message()['response']
        return self.__created_worker_temp_directory

    # Param interface
    ##################

    def param_defaults(self):
        """Returns the defaults parameters for this runnable"""
        return {}

    def param_required(self, param_name):
        """Returns the value of the parameter "param_name" or raises an exception
        if anything wrong happens or the value is None. The exception is
        marked as non-transient."""
        t = self.input_job.transient_error
        self.input_job.transient_error = False
        v = self.__params.get_param(param_name)
        if v is None:
            raise params.NullParamException(param_name)
        self.input_job.transient_error = t
        return v

    def param(self, param_name, *args):
        """When called as a setter: sets the value of the parameter "param_name".
        When called as a getter: returns the value of the parameter "param_name".
        It does not raise an exception if the parameter (or another one in the
        substitution stack) is undefined"""
        # As a setter
        if len(args):
            return self.__params.set_param(param_name, args[0])

        # As a getter
        try:
            return self.__params.get_param(param_name)
        except KeyError as e:
            warnings.warn("parameter '{0}' cannot be initialized because {1} is missing !".format(param_name, e), params.ParamWarning, 2)
            return None

    def param_exists(self, param_name):
        """Returns True if the parameter exists and can be successfully
        substituted, None if the substitution fails, False if it is missing"""
        if not self.__params.has_param(param_name):
            return False
        try:
            self.__params.get_param(param_name)
            return True
        except KeyError:
            return None

    def param_is_defined(self, param_name):
        """Returns True if the parameter exists and can be successfully
        substituted to a defined value, None if the substitution fails,
        False if it is missing or evaluates as None"""
        e = self.param_exists(param_name)
        if not e:
            # False or None
            return e
        try:
            return self.__params.get_param(param_name) is not None
        except KeyError:
            return False

class BaseRunnableTestCase(unittest.TestCase):
    def test_job_param(self):
        class FakeRunnableWithParams(BaseRunnable):
            def __init__(self, d):
                self._BaseRunnable__params = params.ParamContainer(d)
                self.input_job = Job()
                self.input_job.transient_error = True
        j = FakeRunnableWithParams({
            'a': 3,
            'b': None,
            'c': '#other#',
            'e': '#e#'
        })

        # param_exists
        self.assertIs( j.param_exists('a'), True, '"a" exists' )
        self.assertIs( j.param_exists('b'), True, '"b" exists' )
        self.assertIs( j.param_exists('c'), None, '"c"\'s existence is unclear' )
        self.assertIs( j.param_exists('d'), False, '"d" doesn\'t exist' )
        with self.assertRaises(params.ParamInfiniteLoopException):
            j.param_exists('e')

        # param_is_defined
        self.assertIs( j.param_is_defined('a'), True, '"a" is defined' )
        self.assertIs( j.param_is_defined('b'), False, '"b" is not defined' )
        self.assertIs( j.param_is_defined('c'), None, '"c"\'s defined-ness is unclear' )
        self.assertIs( j.param_is_defined('d'), False, '"d" is not defined (it doesn\'t exist)' )
        with self.assertRaises(params.ParamInfiniteLoopException):
            j.param_is_defined('e')

        # param
        self.assertIs( j.param('a'), 3, '"a" is 3' )
        self.assertIs( j.param('b'), None, '"b" is None' )
        with self.assertWarns(params.ParamWarning):
            self.assertIs( j.param('c'), None, '"c"\'s value is unclear' )
        with self.assertWarns(params.ParamWarning):
            self.assertIs( j.param('d'), None, '"d" is not defined (it doesn\'t exist)' )
        with self.assertRaises(params.ParamInfiniteLoopException):
            j.param('e')

        # param_required
        self.assertIs( j.param_required('a'), 3, '"a" is 3' )
        with self.assertRaises(params.NullParamException):
            j.param_required('b')
        with self.assertRaises(KeyError):
            j.param_required('c')
        with self.assertRaises(KeyError):
            j.param_required('d')
        with self.assertRaises(params.ParamInfiniteLoopException):
            j.param_required('e')

