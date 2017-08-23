
import json
import os.path
import subprocess
import sys


def setup_if_needed():
    build_path = os.path.join(os.environ["PWD"], "_build")

    # Install packages and setup environment
    on_rtd = os.environ.get("READTHEDOCS", None) == "True"
    if on_rtd:
        subprocess.check_call([os.environ["PWD"] + os.path.sep + "rtd_upgrade.sh"], stdout=sys.stdout, stderr=sys.stderr)
        upgrade_path = os.environ["HOME"]
        deb_install_path = os.path.join(upgrade_path, "packages")
        os.environ["PERL5LIB"] = os.path.pathsep.join(os.path.join(deb_install_path, _) for _ in ["usr/share/perl5/", "usr/lib/x86_64-linux-gnu/perl5/5.22/", "usr/lib/x86_64-linux-gnu/perl5/5.22/auto/"])
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
    if on_rtd or any(not os.path.exists(os.path.join(doxygen_target, _)) for _ in ["perl", "python3", "java"]):
        subprocess.check_call([mkdoxygen_path, doxygen_target])

    return doxygen_target

