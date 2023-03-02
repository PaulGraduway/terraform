#!/bin/bash
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y rsync
sudo locale-gen
sleep 1
curl -sL https://deb.nodesource.com/setup_16.x | sudo bash -
sudo apt -y install nodejs
