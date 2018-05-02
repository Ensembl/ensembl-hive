#!/bin/bash

set -e

yum groupinstall -y 'Development Tools'

for arg
do
	cpanm --installdeps --with-recommends "$arg"
done

