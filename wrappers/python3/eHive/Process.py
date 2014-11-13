
import eHive.Params

import os
import sys
import json
import numbers
import warnings
import traceback


__doc__ = """
This module mainly implements python's counterpart of ForeignProcess. Read
the later for more information about the JSON protocol used to communicate.
"""

class Job(object):
    """Dummy class to hold job-related information"""
    pass

class CompleteEarlyException(Exception):
    """Can be raised by a derived class of BaseRunnable to indicate an early successful termination"""
    pass
class JobFailedException(Exception):
    """Can be raised by a derived class of BaseRunnable to indicate an early unsuccessful termination"""
    pass
class HiveJSONMessageException(Exception):
    """Raised when we could not parse the JSON message coming from ForeignProcess"""
    pass


class BaseRunnable(object):

    # Private BaseRunnable interface
    #################################

    def __init__(self, read_fileno, write_fileno):
        # We need the binary mode to disable the buffering
        self.read_pipe = os.fdopen(read_fileno, mode='rb', buffering=0)
        self.write_pipe = os.fdopen(write_fileno, mode='wb', buffering=0)
        self.pid = os.getpid()
        self.debug = 0
        self.__process_life_cycle()

    def __print_debug(self, *args):
        if self.debug > 1:
            print("PYTHON {0}".format(self.pid), *args, file=sys.stderr)

    def __send_message(self, event, content):
        def default_json_encoder(o):
            self.__print_debug("Cannot serialize {0} (type {1}) in JSON".format(o, type(o)))
            return 'UNSERIALIZABLE OBJECT'
        j = json.dumps({'event': event, 'content': content}, indent=None, default=default_json_encoder)
        self.__print_debug('__send_message:', j)
        self.write_pipe.write(bytes(j+"\n", 'utf-8'))

    def __read_message(self):
        try:
            self.__print_debug("__read_message ...")
            l = self.read_pipe.readline()
            self.__print_debug(" ... -> ", l[:-1].decode())
            return json.loads(l.decode())
        except ValueError as e:
            raise HiveJSONMessageException from e

    def __send_message_and_wait_for_OK(self, event, content):
        self.__send_message(event, content)
        response = self.__read_message()
        if response['response'] != 'OK':
            raise HiveJSONMessageException("Received '{0}' instead of OK".format(response))

    def __process_life_cycle(self):
        self.__send_message_and_wait_for_OK('PARAM_DEFAULTS', self.param_defaults())
        while True:
            self.__print_debug("waiting for instructions")
            config = self.__read_message()
            if 'input_job' not in config:
                self.__print_debug("no params")
                return
            self.__job_life_cycle(config)

    def __job_life_cycle(self, config):

        self.__print_debug("__life_cycle")

        # Params
        self.p = eHive.Params.ParamContainer(config['input_job']['parameters'])

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
        self.__print_debug("steps to run:", steps)

        # The actual life-cycle
        died_somewhere = False
        try:
            for s in steps:
                self.__run_method_if_exists(s)
        except CompleteEarlyException as e:
            self.warning(e.args[0] if len(e.args) else repr(e), False)
        except:
            died_somewhere = True
            self.warning( self.__traceback(2), True)

        try:
            self.__run_method_if_exists('post_cleanup')
        except:
            died_somewhere = True
            self.warning( self.__traceback(2), True)

        job_end_structure = {'complete' : not died_somewhere, 'job': {}, 'params': {'substituted': self.p._param_hash, 'unsubstituted': self.p._unsubstituted_param_hash}}
        for x in [ 'autoflow', 'lethal_for_worker', 'transient_error' ]:
            job_end_structure['job'][x] = getattr(self.input_job, x)
        self.__send_message_and_wait_for_OK('JOB_END', job_end_structure)

    def __run_method_if_exists(self, method):
        if hasattr(self, method):
            self.__send_message_and_wait_for_OK('JOB_STATUS_UPDATE', method)
            getattr(self, method)()

    def __traceback(self, skipped_traces):
        """Remove "skipped_traces" lines from the stack trace (the eHive part)"""
        (etype, value, tb) = sys.exc_info()
        s1 = traceback.format_exception_only(etype, value)
        l = traceback.extract_tb(tb)[skipped_traces:]
        s2 = traceback.format_list(l)
        return "".join(s1+s2)


    # Public BaseRunnable interface
    ################################

    def warning(self, message, is_error = False):
        self.__send_message_and_wait_for_OK('WARNING', {'message': message, 'is_error': is_error})

    def dataflow(self, output_ids, branch_name_or_code = 1):
        self.__send_message('DATAFLOW', {'output_ids': output_ids, 'branch_name_or_code': branch_name_or_code, 'params': {'substituted': self.p._param_hash, 'unsubstituted': self.p._unsubstituted_param_hash}})
        return self.__read_message()

    def worker_temp_directory(self):
        if not hasattr(self, '_created_worker_temp_directory'):
            template_name = self.worker_temp_directory_name() if hasattr(self, 'worker_temp_directory_name') else None
            self.__send_message('WORKER_TEMP_DIRECTORY', template_name)
            self._created_worker_temp_directory = self.__read_message()
        return self._created_worker_temp_directory

    # Param interface
    ##################

    def param_defaults(self):
        return {}

    def param_required(self, param_name):
        """Returns the value of the parameter "param_name" or raises an exception if anything wrong happens. The exception is marked as non-transient."""
        t = self.input_job.transient_error
        self.input_job.transient_error = False
        v = self.p.get_param(param_name)
        self.input_job.transient_error = t
        return v

    def param(self, param_name, *args):
        """When called as a setter: sets the value of the parameter "param_name".
        When called as a getter: returns the value of the parameter "param_name".
        It does not raise an exception if the parameter (or another one in the substitution stack) is undefined"""
        # As a setter
        if len(args):
            return self.p.set_param(param_name, args[0])

        # As a getter
        try:
            return self.p.get_param(param_name)
        except KeyError as e:
            warnings.warn("parameter '{0}' cannot be initialized because {1} is not defined !\n".format(param_name, e), Params.ParamWarning, 2)
            return None

    def param_exists(self, param_name):
        return self.p.has_param(param_name)

    def param_is_defined(self, param_name):
        if not self.param_exists(param_name):
            return False
        try:
            return self.p.get_param(param_name) is not None
        except KeyError:
            return False

