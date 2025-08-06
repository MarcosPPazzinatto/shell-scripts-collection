#!/bin/bash

# ping-check.sh
# Simple script to check if a host is reachable

# Usage: ./ping-check.sh <hostname or IP>

if [ -z "$1" ]; then
  echo "Usage: $0 <hostname or IP>"
  exit 1
fi

HOST=$1
COUNT=4

echo "Pinging $HOST with $COUNT packets..."
echo

ping -c $COUNT $HOST

if [ $? -eq 0 ]; then
  echo
  echo "Host $HOST is reachable."
else
  echo
  echo "Host $HOST is not reachable."
fi

