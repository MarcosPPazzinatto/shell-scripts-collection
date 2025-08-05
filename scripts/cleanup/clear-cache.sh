#!/bin/bash
# Clear system cache (Linux only)

echo "Cleaning system cache..."
sync; echo 3 > /proc/sys/vm/drop_caches
echo "Cache cleared!"

