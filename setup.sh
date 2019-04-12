#!/bin/bash

PLATFORM=$(cat /etc/os-release|grep -e "^NAME=.*$"|sed -e "s/NAME=//g"|sed -e "s/\"//g")

sudo mkdir -p /etc/nginx/default.d/

if [[ ${PLATFORM} = "Debian GNU/Linux" ]]; then
    sudo apt-get update
    sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli
    sudo systemctl start docker
    sudo usermod -a -G docker `whoami`
    
    sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    sudo apt-get install -y nginx
    if [[ ! -e /etc/nginx/default.back ]]; then
        sudo cp /etc/nginx/sites-enabled/default /etc/nginx/default.back
    fi
    sudo sed -i -e "47i         include /etc/nginx/default.d/*.conf;" /etc/nginx/sites-enabled/default
    sudo systemctl start nginx
    sudo systemctl enable nginx
fi

if [[ ${PLATFORM} = "Ubuntu" ]]; then
    sudo apt-get update
    sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli
    sudo systemctl start docker
    sudo usermod -a -G docker `whoami`
    
    sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    sudo apt-get install -y nginx
    if [[ ! -e /etc/nginx/default.back ]]; then
        sudo cp /etc/nginx/sites-enabled/default /etc/nginx/default.back
    fi

    sudo sed -i -e "47i         include /etc/nginx/default.d/*.conf;" /etc/nginx/sites-enabled/default
    sudo systemctl start nginx
    sudo systemctl enable nginx
    
fi


if [[ ${PLATFORM} = "Amazon Linux" ]]; then
    sudo yum update -y
    sudo yum install -y docker
    sudo service docker start
    sudo usermod -a -G docker `whoami`
    
    sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo service nginx start
fi
