#!/bin/bash

# List all running containers with names starting with 'rivalz_auto_'
containers=$(docker ps --filter "name=rivalz_auto_" --format "{{.Names}}")

# Check if any containers are found
if [ -z "$containers" ]; then
  echo "No running containers with name prefix 'rivalz_auto_' found."
  exit 1
fi

# Iterate through each container
for container in $containers; do
  echo "Processing container: $container"
  
  # Run the command in detached mode
  docker exec -d "$container" rivalz run
  
  # Check the exit status of the command
  if [ $? -eq 0 ]; then
    echo "Command executed successfully on $container."
  else
    echo "Command failed on $container."
  fi

  echo "Finished processing container: $container"
done

echo "All containers processed."
