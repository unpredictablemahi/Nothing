#!/bin/bash

# Ask how many containers the user wants to create
read -p "How many containers do you want to create? " container_count

# Check if the proxy file exists
if [ ! -f "proxy.txt" ]; then
    echo "Error: proxy.txt file not found!"
    exit 1
fi

# Read proxies from proxy.txt
mapfile -t proxies < proxy.txt

# Check if there are enough proxies for the number of containers
if [ ${#proxies[@]} -lt $container_count ]; then
    echo "Error: Not enough proxies in proxy.txt. You need at least $container_count proxies."
    exit 1
fi

# Base image name
base_image="rivalz_base_image"

# Create a base Docker image if not exists
if ! docker images | grep -q "$base_image"; then
    echo "Building the base Docker image..."
    cat <<EOL > Dockerfile
FROM ubuntu:latest
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y curl redsocks iptables iproute2 jq nano

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs
RUN npm install -g npm && npm install -g rivalz-node-cli@3.0.1

CMD ["/bin/bash"]
EOL
    docker build -t $base_image .
    rm Dockerfile
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

    # Create container-specific configuration
    config_dir="container_configs/$container_name"
    mkdir -p $config_dir

    # Generate redsocks.conf
    cat <<EOL > $config_dir/redsocks.conf
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
    if [ "$auth_required" = "yes" ]; then
        echo "    login = \"$proxy_user\";" >> $config_dir/redsocks.conf
        echo "    password = \"$proxy_pass\";" >> $config_dir/redsocks.conf
    fi
    echo "}" >> $config_dir/redsocks.conf

    # Generate entrypoint.sh
    cat <<EOL > $config_dir/entrypoint.sh
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
    chmod +x $config_dir/entrypoint.sh

    # Create Docker container
    echo -e "\e[32mStarting container $container_name...\e[0m"
    docker run -it --cap-add=NET_ADMIN --name $container_name \
        -v "$(pwd)/$config_dir/redsocks.conf:/etc/redsocks.conf" \
        -v "$(pwd)/$config_dir/entrypoint.sh:/usr/local/bin/entrypoint.sh" \
        $base_image /usr/local/bin/entrypoint.sh

    echo -e "\e[33mExited container $container_name. Proceeding to the next container...\e[0m"
done

echo "All containers have been created and run interactively."
