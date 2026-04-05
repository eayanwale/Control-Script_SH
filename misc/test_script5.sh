#!/bin/bash


num1=$1
num2=$2
add=$(expr $num1 + $num2)

if (( $add == 4 ))
then
	echo "correct"
else
	echo "wrong"
	exit 1
fi
