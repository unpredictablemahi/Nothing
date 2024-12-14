#!/bin/bash

# Ask how many containers the user wants to create
read -p "How many containers do you want to create? " container_count

# Check if the proxy file exists
if [ ! -f "proxy.txt" ]; then
    echo "proxy.txt file not found!"
    exit 1
fi

# Read proxies from proxy.txt
mapfile -t proxies < proxy.txt

# Check if there are enough proxies for the number of containers
if [ ${#proxies[@]} -lt $container_count ]; then
    echo "Not enough proxies in proxy.txt. You need at least $container_count proxies."
    exit 1
fi

# Loop to create the specified number of containers
for i in $(seq 1 $container_count); do
    proxy="${proxies[$((i - 1))]}" # Get the i-th proxy from the list

    # Parse proxy details: Handle all formats (IP:PORT, IP:PORT:USER:PWD)
    proxy_ip=$(echo $proxy | cut -d ':' -f 1)
    proxy_port=$(echo $proxy | cut -d ':' -f 2)
    proxy_user=$(echo $proxy | cut -d ':' -f 3)
    proxy_pass=$(echo $proxy | cut -d ':' -f 4)

    # Determine if authentication is required
    if [ -n "$proxy_user" ] && [ -n "$proxy_pass" ]; then
        auth_required="yes"
    else
        auth_required="no"
    fi

    # Set the container name
    container_name="rivalz_auto_$i"

    # Check if the container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
        echo "Container $container_name already exists. Skipping..."
        continue
    fi

    # Create or replace the Dockerfile
    cat <<EOL > Dockerfile
FROM ubuntu:latest
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl redsocks iptables iproute2 jq nano

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs
RUN npm install -g npm && npm install -g rivalz-node-cli@latest
EOL

    # Add redsocks configuration file based on authentication
    cat <<EOL > redsocks.conf
base {
    log_debug = off;
    log_info = on;
    log = "file:/var/log/redsocks.log";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = $proxy_ip;
    port = $proxy_port;
    type = http-connect;
EOL

    # Append authentication info if required
    if [ "$auth_required" = "yes" ]; then
        echo "    login = \"$proxy_user\";" >> redsocks.conf
        echo "    password = \"$proxy_pass\";" >> redsocks.conf
    fi
    echo "}" >> redsocks.conf

    # Create the entrypoint script
    cat <<EOL > entrypoint.sh
#!/bin/sh

echo "Starting redsocks..."
redsocks -c /etc/redsocks.conf &
sleep 5

echo "Configuring iptables..."
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 12345

echo "Starting bash shell..."
exec /bin/bash
EOL

    chmod +x entrypoint.sh

    # Build the Docker image
    docker build -t $container_name .

    # Run the Docker container interactively
    echo -e "\e[32mStarting container $container_name...\e[0m"
    docker run -it --cap-add=NET_ADMIN --name $container_name \
        -v "$(pwd)/redsocks.conf:/etc/redsocks.conf" \
        -v "$(pwd)/entrypoint.sh:/usr/local/bin/entrypoint.sh" \
        $container_name

    echo -e "\e[33mExited container $container_name. Proceeding to the next container...\e[0m"
done

echo "All containers have been created and run interactively."
