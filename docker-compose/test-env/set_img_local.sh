#!/bin/bash

set -e 

sed -i 's/^\(.*\)=docker\.io\/omnileads\/\([^:]*\):.*/\1=\2:latest/' .env
sed -i 's/^\(.*\)=docker\.io\/freetechsolutions\/\([^:]*\):.*/\1=\2:latest/' .env
