
import Param

import os
import sys
import json
import time
import numbers
import warnings
import traceback

class Job(object):
    pass

class HiveJobException(Exception):
    pass
class CompleteEarlyException(HiveJobException):
    pass
class JobErrorException(HiveJobException):
    pass
class HiveJSONMessageException(Exception):
    pass


class Process(object):

    # Private Process interface
    ############################

    def __init__(self, read_fileno, write_fileno):
        # We need the binary mode to disable the buffering
        self.read_pipe = os.fdopen(read_fileno, mode='rb', buffering=0)
        self.write_pipe = os.fdopen(write_fileno, mode='wb', buffering=0)
        self.__send_message('PARAM_DEFAULTS', self.param_defaults())

    def __send_message(self, event, content):
        def default_json_encoder(self_encoder, o):
            print("Cannot serialize {0} in JSON".format(o))
            return 'UNSERIALIZABLE OBJECT'
        j = json.dumps({'event': event, 'content': content}, indent=None, default=default_json_encoder)
        print("PYTHON __send_message:", j)
        self.write_pipe.write(bytes(j+"\n", 'utf-8'))

    def __read_message(self):
        try:
            print("PYTHON __read_message ...")
            l = self.read_pipe.readline()
            print("PYTHON ... -> ", l.decode())
            return json.loads(l.decode())
        except ValueError as e:
            raise SystemExit(e)

    def __send_message_and_wait_for_OK(self, event, content):
        self.__send_message(event, content)
        response = self.__read_message()
        if response['response'] != 'OK':
            raise SystemExit(response)

    def life_cycle(self):

        print("PYTHON life_cycle", file=sys.stderr)
        config = self.__read_message()
        self.p = Param.Param(config['input_job']['parameters'])

        # Job attributes
        self.input_job = Job()
        for x in ['dbID', 'input_id', 'retry_count']:
            setattr(self.input_job, x, config['input_job'][x])
        self.input_job.autoflow = True

        # Worker attributes
        setattr(self, 'debug', config['debug'])

        # Which methods should be run
        steps = [ 'fetch_input', 'run' ]
        if self.input_job.retry_count > 0:
            steps.insert(0, 'pre_cleanup')
        if config['execute_writes']:
            steps.append('write_output')
        print("PYTHON steps to run:", steps, file=sys.stderr)

        # The actual life-cycle
        died_somewhere = False
        try:
            for s in steps:
                self.__run_method_if_exists(s)
        except CompleteEarlyException as e:
            self.warning(e.args[0] if len(e.args) else repr(e), False)
        except:
            died_somewhere = True
            self.warning(traceback.format_exc(), True)

        try:
            self.__run_method_if_exists('post_cleanup')
        except:
            died_somewhere = True
            self.warning(traceback.format_exc(), True)

        job_end_structure = {'complete' : not died_somewhere, 'autoflow': self.input_job.autoflow, 'params': {'substituted': self.p._param_hash, 'unsubstituted': self.p._unsubstituted_param_hash}}
        self.__send_message('JOB_END', job_end_structure)

    def __run_method_if_exists(self, method):
        if hasattr(self, method):
            self.__send_message_and_wait_for_OK('JOB_STATUS_UPDATE', method)
            #self.__send_message('JOB_STATUS_UPDATE', method)
            getattr(self, method)()


    # Public Process interface
    ###########################

    def warning(self, message, is_error = False):
        self.__send_message_and_wait_for_OK('WARNING', {'message': message, 'is_error': is_error})

    def datataflow(self, output_ids, branch_name_or_code = 1):
        self.__send_message('DATAFLOW', {'output_ids': output_ids, 'branch_name_or_code': branch_name_or_code})
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
        return self.p.get_param(param_name)

    def param(self, param_name, *args):
        # As a setter
        if len(args):
            return self.p.set_param(param_name, args[0])

        # As a getter
        try:
            return self.p.get_param(param_name)
        except KeyError as e:
            warnings.warn("parameter '{0}' cannot be initialized because {1} is not defined !\n".format(param_name, e), Param.ParamWarning, 2)
            return None

    def param_exists(self, param_name):
        return self.p.has_param(param_name)

    def param_is_defined(self, param_name):
        try:
            return self.p.get_param(param_name) is not None
        except KeyError:
            return False

