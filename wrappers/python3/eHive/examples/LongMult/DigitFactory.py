
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

import eHive

import time

class DigitFactory(eHive.BaseRunnable):
    """Factory that creates 1 job per digit found in the decimal representation of 'b_multiplier'"""

    def param_defaults(self):
        return {
            'take_time' : 0
        }


    def fetch_input(self):
        b_multiplier = self.param_required('b_multiplier')
        sub_tasks = [ { 'digit': _ } for _ in set(str(b_multiplier)).difference('01') ]
        self.param('sub_tasks', sub_tasks)


    def run(self):
        time.sleep( self.param('take_time') )


    def write_output(self):
        sub_tasks = self.param('sub_tasks')
        self.dataflow(sub_tasks, 2)
        self.warning('{0} multiplication jobs have been created'.format(len(sub_tasks)))


