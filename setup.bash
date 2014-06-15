#!/bin/bash

SOURCEDIR=/root


# update apt repositories
apt-get update

#user iface choice
apt-get -y install python-pip gcc python-dev
pip install netifaces
wget https://raw.github.com/rarosalion/honeypot-setup-script/master/scripts/iface-choice.py -O /tmp/iface-choice.py
python /tmp/iface-choice.py
iface=$(<~/.honey_iface)

# Move SSH server from Port 22 to Port 66522
sed -i 's:Port 22:Port 65522:g' /etc/ssh/sshd_config
service ssh reload

# dependency for add-apt-repository
apt-get install -y python-software-properties

## install dionaea ##

#add dionaea repo
add-apt-repository -y ppa:honeynet/nightly
apt-get update
apt-get install -y dionaea


# Set file permissions

chown -R nobody:nogroup /opt/dionaea/var/dionaea
chown -R nobody:nogroup /opt/dionaea/var/log


#edit config
wget https://raw.github.com/rarosalion/honeypot-setup-script/master/templates/dionaea.conf.tmpl -O /etc/dionaea/dionaea.conf
#note that we try and strip :0 and the like from interface here
sed -i "s|%%IFACE%%|${iface%:*}|g" /etc/dionaea/dionaea.conf




## install kippo - we want the latest so we have to grab the source ##

#kippo dependencies
apt-get install -y subversion python-dev openssl python-openssl python-pyasn1 python-twisted iptables

#install kippo to /opt/kippo
mkdir /opt/kippo/
svn checkout http://kippo.googlecode.com/svn/trunk/ /opt/kippo/

wget https://raw.github.com/rarosalion/honeypot-setup-script/master/templates/kippo.cfg.tmpl -O /opt/kippo/kippo.cfg

#add kippo user that can't login
useradd -r -s /bin/false kippo

#set up log dirs
mkdir -p /var/kippo/dl
mkdir -p /var/kippo/log/tty
mkdir -p /var/run/kippo

#delete old dirs to prevent confusion
rm -rf /opt/kippo/dl
rm -rf /opt/kippo/log

#set up permissions
chown -R kippo:kippo /opt/kippo/
chown -R kippo:kippo /var/kippo/
chown -R kippo:kippo /var/run/kippo/

#point port 22 at port 2222 
#we should have -i $iface here but it was breaking things with virtual interfaces
iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222

#persist iptables config
iptables-save > /etc/iptables.rules

#setup iptables restore script
echo '#!/bin/sh' >> /etc/network/if-up.d/iptablesload 
echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-up.d/iptablesload 
echo 'exit 0' >> /etc/network/if-up.d/iptablesload 
#enable restore script
chmod +x /etc/network/if-up.d/iptablesload 


# Setup logrotate

cat > /etc/logrotate.d/dionaea <<END
# logrotate requires dionaea to be started with a pidfile
# in this case -p /opt/dionaea/var/run/dionaea.pid
# adjust the path to your needs
/opt/dionaea/var/log/dionaea*.log {
        notifempty
        missingok
        rotate 28
        daily
        delaycompress
        compress
        create 660 nobody nogroup
        dateext
        postrotate
                kill -HUP `cat /opt/dionaea/var/dionaea.pid`
        endscript
}
END




#download init files and install them
wget https://raw.github.com/rarosalion/honeypot-setup-script/master/init/p0f -O /etc/init.d/p0f
wget https://raw.github.com/rarosalion/honeypot-setup-script/master/init/dionaea -O /etc/init.d/dionaea
wget https://raw.github.com/rarosalion/honeypot-setup-script/master/init/kippo -O /etc/init.d/kippo


#install system services
chmod +x /etc/init.d/p0f
chmod +x /etc/init.d/dionaea
chmod +x /etc/init.d/kippo

update-rc.d p0f defaults
update-rc.d dionaea defaults
update-rc.d kippo defaults

#start the honeypot software
/etc/init.d/kippo start
/etc/init.d/p0f start
/etc/init.d/dionaea start

