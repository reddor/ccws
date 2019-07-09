#!/bin/bash

DEFAULTPARAMS="-Mobjfpc -Fusrc/chakracore/src -Fusrc/chakracore/samples/HostSample -Fisrc/chakracore/src -Fusrc/synapse -Fisrc/synapse -FE. -FU./ppu"
DYNAMICPARAMS="-O3"

if [ ! -f src/ccws.lpr ] 
then
	echo "File not found or script not called in right directory"
	exit 1
fi

if [ ! -d ppu ]
then
	mkdir ppu
fi

if [ "$#" -eq 1 ]
then
	if [[ "$1" = "debug" ]]; then
		DYNAMICPARAMS="-O1 -g -gl -gh -B"
	elif [[ "$1" = "releasedbg" ]]; then
		DYNAMICPARAMS="-O3 -g -B"
	elif [[ "$1" = "clean" ]]; then
		echo "Cleaning..."
		rm -f ppu/*.o
		rm -f ppu/*.ppu
		exit 0
	elif [[ "$1" = "build" ]]; then
		DYNAMICPARAMS="-B"
	else
		echo "Valid commands: debug, clean"
		exit 1
	fi
fi

fpc $DEFAULTPARAMS $DYNAMICPARAMS src/ccws.lpr
exit $?
