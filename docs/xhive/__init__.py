
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
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

# For python2 compatibility
from __future__ import print_function

import json
import os.path
import subprocess
import sys


def setup_if_needed(this_release, run_doxygen):
    build_path = os.path.join(os.environ["PWD"], "_build")

    # Check whether we are on the same version of eHive
    is_same = False
    release_holder = os.path.join(build_path, "LAST_BUILD")
    if os.path.isfile(release_holder):
        with open(release_holder, "r") as fh:
            previous_release = fh.read()
        if previous_release == this_release:
            is_same = True

    # Install packages and setup environment
    on_rtd = os.environ.get("READTHEDOCS", None) == "True"
    if on_rtd:
        upgrade_path = os.path.join(build_path, "rtd_upgrade")
        if not is_same:
            subprocess.check_call(["./rtd_upgrade.sh", upgrade_path], stdout=sys.stdout, stderr=sys.stderr)
        deb_install_path = os.path.join(upgrade_path, "root")
        os.environ["PERL5LIB"] = os.path.pathsep.join(os.path.join(deb_install_path, _) for _ in ["usr/share/perl5/", "usr/lib/x86_64-linux-gnu/perl5/5.26/", "usr/lib/x86_64-linux-gnu/perl5/5.26/auto/"])
        os.environ["PATH"] = os.path.join(deb_install_path, "usr/bin") + os.path.pathsep + os.environ["PATH"]
        os.environ["ENSEMBL_CVS_ROOT_DIR"] = upgrade_path
    else:
        os.environ["ENSEMBL_CVS_ROOT_DIR"]   # Will raise an error if missing
    os.environ["EHIVE_ROOT_DIR"] = os.path.join(os.environ["PWD"], os.path.pardir)
    os.environ["PERL5LIB"] = os.path.join(os.environ["EHIVE_ROOT_DIR"], "modules") + os.path.pathsep + os.environ["PERL5LIB"]

    # Doxygen
    mkdoxygen_path = os.path.join(os.environ["EHIVE_ROOT_DIR"], "scripts", "dev", "make_doxygen.pl")
    # Only run doxygen if it's missing
    doxygen_target = os.path.join(build_path, "doxygen")
    if (on_rtd and not is_same) or any(not os.path.exists(os.path.join(doxygen_target, _)) for _ in ["perl", "python3", "java"]):
        if run_doxygen:
            subprocess.check_call([mkdoxygen_path, doxygen_target])

    with open(release_holder, "w") as fh:
        print(this_release, end=' ', file=fh)

    return doxygen_target

