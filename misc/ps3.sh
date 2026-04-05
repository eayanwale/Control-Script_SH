#!/bin/bash

servers="serv1 serv2 serv3 serv4 quit"
ps3="Select a server: "

select server in ${servers}
do
    if [[ ${server} == "quit" ]]
    then
        break
    fi
    echo "Server name is ${server}"
done
