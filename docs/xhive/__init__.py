
import json
import os.path
import subprocess
import sys


def setup_if_needed():
    if os.environ.get("READTHEDOCS", None) == "True":
        subprocess.call([os.environ["PWD"] + os.path.sep + "rtd_upgrade.sh"], stdout=sys.stdout, stderr=sys.stderr)
        os.environ["PERL5LIB"] = os.path.pathsep.join(os.path.join(os.environ["HOME"], "packages", _) for _ in ["usr/share/perl5/", "usr/lib/x86_64-linux-gnu/perl5/5.22/", "usr/lib/x86_64-linux-gnu/perl5/5.22/auto/"])
        os.environ["PATH"] = os.path.join(os.environ["HOME"], "packages", "usr/bin") + os.path.pathsep + os.environ["PATH"]
        os.environ["ENSEMBL_CVS_ROOT_DIR"] = os.environ["HOME"]
    else:
        os.environ["ENSEMBL_CVS_ROOT_DIR"]   # Will raise an error if missing
    os.environ["EHIVE_ROOT_DIR"] = os.path.join(os.environ["PWD"], os.path.pardir)
    os.environ["PERL5LIB"] = os.path.join(os.environ["EHIVE_ROOT_DIR"], "modules") + os.path.pathsep + os.environ["PERL5LIB"]
    mkdoc_path = os.path.join(os.environ["EHIVE_ROOT_DIR"], "scripts", "dev", "make_docs.pl")
    # Only run doxygen if it's missing
    doxygen_target = os.path.join(os.environ["EHIVE_ROOT_DIR"], "docs", "_build", "doxygen")
    if (os.environ.get("READTHEDOCS", None) == "True") or any(not os.path.exists(os.path.join(doxygen_target, _)) for _ in ["perl", "python3", "java"]):
        subprocess.call([mkdoc_path, "-no_script_docs", "-no_schema_desc"]) # i.e. run doxygen only
    # always run the rest
    subprocess.call([mkdoc_path, "-no_doxygen"]) # i.e. run everything but doxygen

