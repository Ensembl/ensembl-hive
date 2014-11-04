
import eHive

import time

class DigitFactory(eHive.BaseRunnable):

    def param_defaults(self):
        return {
            'take_time' : 0
        }


    def fetch_input(self):
        b_multiplier = self.param_required('b_multiplier')
        sub_tasks = [ { 'digit': _ } for _ in str(b_multiplier) if _ not in '01' ]
        self.param('sub_tasks', sub_tasks)


    def run(self):
        time.sleep( self.param('take_time') )


    def write_output(self):
        sub_tasks = self.param('sub_tasks')
        self.dataflow(sub_tasks, 2)
        self.warning('{0} multiplication jobs have been created'.format(len(sub_tasks)))


