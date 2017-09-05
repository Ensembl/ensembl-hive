#!/usr/bin/env python3
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2017] EMBL-European Bioinformatics Institute
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

##
## Minimalistic init system required for Docker containers
##

# Docker doesn't come with an "init" process, meaning that when beekeeper
# submits LOCAL workers and exits (beekeeper -run), the workers will be
# killed by docker.

# This pseudo-init script addresses this issue by waiting for all the child
# processes (and daemons) to exit.  This is different from other
# Docker-tailored init systems such as dumb-init
# (https://github.com/Yelp/dumb-init) and my_init
# (https://github.com/phusion/baseimage-docker/blob/master/image/bin/my_init)
# because it doesn't handle signals, and doesn't kill the children

import errno
import os
import subprocess
import sys


def wait_for_all_processes():
    child_errors = False
    while True:
        try:
            # Wait for any child
            child_pid, child_status = os.waitpid(-1, 0)
            #print("ripped a child", child_pid, child_status)
            # Check its status
            if child_status != 0:
                child_errors = True
        except OSError as e:
            if e.errno == errno.ECHILD:
                # No more child found
                return child_errors
            else:
                # Other errors
                raise



# Run the command
#print("Executing", sys.argv[1:])
cmd_ret = subprocess.call( sys.argv[1:] )

# Wait for all the processes to end
child_errors = wait_for_all_processes()

# Return an approriate exit code
if cmd_ret == 0:
    cmd_ret = 1 if child_errors else 0
sys.exit(cmd_ret)

