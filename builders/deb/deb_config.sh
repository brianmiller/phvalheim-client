#!/bin/bash

# define our roots
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
gitRoot=$(echo $scriptRoot/|rev|cut -d "/" -f4-|rev)
debRoot=$(echo $scriptRoot/|rev|cut -d "/" -f2-|rev)


# tell us about this system
echo
echo "## PhValheim Client Debian packager ##"
echo
echo "Now: `date`"
echo
echo "This build system hostname: `hostname`"
echo "This build system kernel: `uname -r`"
echo
echo "Git root directory: $gitRoot"
echo "Deb root directory: $debRoot"
echo


# build logs
if [ ! -d $debRoot/logs ]; then
	mkdir $debRoot/logs
else
	rm -f $debRoot/logs/*
fi


############################## BEGIN: Functions ##############################

############################## END: Functions ##############################


