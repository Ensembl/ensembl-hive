#!/bin/bash

set -e

# We should probably install some build packages

for arg
do
	cpanm --installdeps --with-recommends "$arg"
done

