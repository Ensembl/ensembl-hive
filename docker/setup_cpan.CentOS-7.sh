#!/bin/bash

set -e

yum groupinstall 'Development Tools'

for arg
do
	cpanm --installdeps --with-recommends "$arg"
done

