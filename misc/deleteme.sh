#!/bin/bash

AUTO_CONFIRM=${AUTO_CONFIRM=false}
for arg in "$@"
do
	if [[ ${arg} == "IM_A_G" ]]
	then
		AUTO_CONFIRM=true
	fi
done

PROMPT()
{
	local message=$1
	local varname=$2
	if [[ "${AUTO_CONFIRM}" == true ]]
	then
		echo "${message} [AUTO:Y]"
		eval "$varname=Y"
	else
		read -p "${message}" "${varname}" < /dev/tty
	fi
}

PROMPT "Are you Enoch? " NAME
PROMPT "Are you 22? " AGE

echo "${NAME}, ${AGE}"
