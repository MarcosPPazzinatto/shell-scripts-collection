#!/bin/bash

########################################################################
# Author: Marcos Paulo Pazzinatto                                      #
# Description:                                                         #
# This script provides basic system resource monitoring information.   #
# It displays CPU usage, memory usage, and disk space usage.           #
########################################################################

echo "========== System Resource Monitor =========="

# Show top 5 processes by CPU usage
echo -e "\n>> Top 5 processes by CPU usage:"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6

# Show memory usage
echo -e "\n>> Memory usage:"
free -h

# Show disk usage
echo -e "\n>> Disk usage:"
df -h

# Show CPU load
echo -e "\n>> CPU load (1, 5, 15 min):"
uptime | awk -F'load average:' '{ print $2 }'

# Show current logged-in users
echo -e "\n>> Logged-in users:"
who

echo "============================================="

