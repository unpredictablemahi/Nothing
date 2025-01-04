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
  echo "Restarting container: $container"
  
  # Restart the container
  docker restart "$container"
  
  # Wait for the container to restart
  sleep 5

  echo "Attaching to container: $container"

  # Use tmux to attach, run command, and detach safely
  tmux new-session -d -s "$container-session" "docker attach $container"
  
  # Wait briefly to allow the session to start
  sleep 2

  # Send the command to the running tmux session
  tmux send-keys -t "$container-session" "rivalz run" Enter
  
  # Simulate Ctrl+p+q to detach
  sleep 2
  tmux send-keys -t "$container-session" " " Enter
  
  # Kill the tmux session
  tmux kill-session -t "$container-session"
  
  echo "Detached from container: $container"
done

echo "All containers processed."
