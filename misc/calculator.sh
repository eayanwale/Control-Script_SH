#!/bin/bash

#Addition function
ADD() 
{
    expr ${NUM1} + ${NUM2}
    if (( $? != 0 ))
    then
      echo "Exit status is $?...exiting"
      exit 1
    fi
#	 echo "Answer:"
 #   echo ${ADD_ANS}
}

#Subtraction function
SUBTRACT()
{
    expr ${NUM1} - ${NUM2}
    if (( $? != 0 ))
    then
      echo "Exit status is $?...exiting"
      exit 1
    fi
}

#Multiplication function
MULTIPLY()
{
    expr ${NUM1} \* ${NUM2}
    if (( $? != 0 ))
    then
      echo "Exit status is $?...exiting"
      exit 1
    fi
}

#Division function
DIVIDE()
{
    expr ${NUM1} / ${NUM2}
	 if (( $? != 0 ))
	 then
	 	echo "Exit status is $?...exiting"
	   exit 1
	 fi
}

#Variable asignments
NUM1=$1
FUNC=$2
NUM2=$3

#Utilization check
if (( $# != 3 ))
then
	echo "You did not run this calculator properly."
	echo "USAGE: num1 function num2"
	echo "e.g. 7 plus 5"
	echo "..."
  
	read -p "Do you need help? " ANSWER
	if [[ ${ANSWER^^} == 'Y' ]]
	then
		echo "Let's help you out..."
		read -p "Enter first number: " NUM1
		read -p "Enter function: " FUNC
		read -p "Enter second number: " NUM2
	else
		exit 1
	fi
fi

#Function calling
case ${FUNC} in
plus)
    echo "Adding ${NUM1} and ${NUM2}..."
	 result="$(ADD ${NUM1} ${NUM2})"
	 echo "Answer is: ${result}"
    ;;
minus)
    echo "Subtracting ${NUM1} and ${NUM2}..."
    result="$(SUBTRACT ${NUM1} ${NUM2})"
    echo "Answer is: ${result}"
    ;;
times)  
    echo "Multiplying ${NUM1} and ${NUM2}..."
    result="$(MULTIPLY ${NUM1} ${NUM2})"
    echo "Answer is: ${result}"
    ;;
divides)		
	 echo "Dividing ${NUM1} and ${NUM2}..."
    result="$(DIVIDE ${NUM1} ${NUM2})"
    echo "Answer is: ${result}"
    ;;
*)
    echo "That function does not exist in this code. Try again."
    ;;
esac

