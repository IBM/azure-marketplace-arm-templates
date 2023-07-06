#!/bin/bash

# Set values
NODE1_IP="10.0.0.6"
NODE2_IP="10.0.0.5"
NODE3_IP="10.0.0.4"

ADMINUSER="azureuser"

# On node 1

ssh $ADMINUSER@$NODE2_IP << EOF
sudo mkdir -p /tmp/iris
sudo chown $ADMINUSER:$ADMINUSER /tmp/iris
EOF

ssh $ADMINUSER@$NODE3_IP << EOF
sudo mkdir -p /tmp/iris
sudo chown $ADMINUSER:$ADMINUSER /tmp/iris
EOF

scp /instancePath/cfg/cluster.iris $ADMINUSER@$NODE2_IP:/tmp/iris/
scp /instancePath/cfg/cluster.iris $ADMINUSER@$NODE3_IP:/tmp/iris/
scp /instancePath/cfg/settings.iris $ADMINUSER@$NODE2_IP:/tmp/iris/
scp /instancePath/cfg/settings.iris $ADMINUSER@$NODE3_IP:/tmp/iris/
scp /instancePath/cfg/inbound* $ADMINUSER@$NODE2_IP:/tmp/iris/
scp /instancePath/cfg/inbound* $ADMINUSER@$NODE3_IP:/tmp/iris/

# Shutdown instances
sudo killall iris
ssh $ADMINUSER@$NODE2_IP 'sudo killall iris'
ssh $ADMINUSER@$NODE3_IP 'sudo killall iris'

# Copy files into place

ssh $ADMINUSER@$NODE2_IP << EOF
sudo cp /tmp/iris/cluster.iris /instancePath/cfg/
sudo cp /tmp/iris/settings.iris /instancePath/cfg/
sudo cp /tmp/iris/inbound* /instancePath/cfg/
sudo rm /instancePath/fli/*
EOF

ssh $ADMINUSER@$NODE3_IP << EOF
sudo cp /tmp/iris/cluster.iris /instancePath/cfg/
sudo cp /tmp/iris/settings.iris /instancePath/cfg/
sudo cp /tmp/iris/inbound* /instancePath/cfg/
sudo rm /instancePath/fli/*
EOF

# Start service

ssh $ADMINUSER@$NODE2_IP 'cd /instancePath/cfg && sudo -u SPUser iris console id=2 &' &
ssh $ADMINUSER@$NODE3_IP 'cd /instancePath/cfg && sudo -u SPUser iris console id=3 &' &
sudo -u SPUser iris console id=1
