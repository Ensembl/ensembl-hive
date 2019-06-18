
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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

# standaloneJob.pl eHive.examples.TestRunnable -language python3

import os
import subprocess

import eHive

class TestRunnable(eHive.BaseRunnable):
    """Simple Runnable to test as a standaloneJob"""

    def param_defaults(self):
        return {
            'alpha' : 37,
            'beta' : 78
        }

    def fetch_input(self):
        self.warning("Fetch the world !")
        print("alpha is", self.param_required('alpha'))
        print("beta is", self.param_required('beta'))
        self.temp_dir = self.worker_temp_directory()
        print("my directory name is", self.temp_dir)

    def run(self):
        self.warning("Run the world !")
        s = self.param('alpha') + self.param('beta')
        print("set gamma to", s)
        self.param('gamma', s)
        self.greeting_path = os.path.join(self.temp_dir, "hello")
        subprocess.check_call(["touch", self.greeting_path])

    def write_output(self):
        self.warning("Write to the world !")
        print("gamma is", self.param('gamma'))
        self.dataflow( {'gamma': self.param('gamma')}, 2 )
        print("Greetings in place:", os.path.exists(self.greeting_path))

