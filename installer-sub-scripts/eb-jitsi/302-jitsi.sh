# ------------------------------------------------------------------------------
# JITSI.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="eb-jitsi"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
DNS_RECORD=$(grep "address=/$MACH/" /etc/dnsmasq.d/eb-jitsi | head -n1)
IP=${DNS_RECORD##*/}
SSH_PORT="30$(printf %03d ${IP##*.})"
echo JITSI="$IP" >> $INSTALLER/000-source

# ------------------------------------------------------------------------------
# NFTABLES RULES
# ------------------------------------------------------------------------------
# the public ssh
nft delete element eb-nat tcp2ip { $SSH_PORT } 2>/dev/null || true
nft add element eb-nat tcp2ip { $SSH_PORT : $IP }
nft delete element eb-nat tcp2port { $SSH_PORT } 2>/dev/null || true
nft add element eb-nat tcp2port { $SSH_PORT : 22 }
# http
nft delete element eb-nat tcp2ip { 80 } 2>/dev/null || true
nft add element eb-nat tcp2ip { 80 : $IP }
nft delete element eb-nat tcp2port { 80 } 2>/dev/null || true
nft add element eb-nat tcp2port { 80 : 80 }
# https
nft delete element eb-nat tcp2ip { 443 } 2>/dev/null || true
nft add element eb-nat tcp2ip { 443 : $IP }
nft delete element eb-nat tcp2port { 443 } 2>/dev/null || true
nft add element eb-nat tcp2port { 443 : 443 }
# tcp/5222
nft delete element eb-nat tcp2ip { 5222 } 2>/dev/null || true
nft add element eb-nat tcp2ip { 5222 : $IP }
nft delete element eb-nat tcp2port { 5222 } 2>/dev/null || true
nft add element eb-nat tcp2port { 5222 : 5222 }
# udp/10000
nft delete element eb-nat udp2ip { 10000 } 2>/dev/null || true
nft add element eb-nat udp2ip { 10000 : $IP }
nft delete element eb-nat udp2port { 10000 } 2>/dev/null || true
nft add element eb-nat udp2port { 10000 : 10000 }

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_RUN_JITSI" = true ]] && exit

echo
echo "-------------------------- $MACH --------------------------"

# ------------------------------------------------------------------------------
# REINSTALL_IF_EXISTS
# ------------------------------------------------------------------------------
EXISTS=$(lxc-info -n $MACH | egrep '^State' || true)
if [[ -n "$EXISTS" ]] && [[ "$REINSTALL_JITSI_IF_EXISTS" != true ]]; then
    echo JITSI_SKIPPED=true >> $INSTALLER/000-source

    echo "Already installed. Skipped..."
    echo
    echo "Please set REINSTALL_JITSI_IF_EXISTS in $APP_CONFIG"
    echo "if you want to reinstall this container"
    exit
fi

# ------------------------------------------------------------------------------
# CONTAINER SETUP
# ------------------------------------------------------------------------------
# stop the template container if it's running
set +e
lxc-stop -n eb-bullseye
lxc-wait -n eb-bullseye -s STOPPED
set -e

# remove the old container if exists
set +e
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
lxc-destroy -n $MACH
rm -rf /var/lib/lxc/$MACH
sleep 1
set -e

# create the new one
lxc-copy -n eb-bullseye -N $MACH -p /var/lib/lxc/

# the shared directories
mkdir -p $SHARED/cache
mkdir -p $SHARED/recordings

# the container config
rm -rf $ROOTFS/var/cache/apt/archives
mkdir -p $ROOTFS/var/cache/apt/archives
rm -rf $ROOTFS/usr/local/eb/recordings
mkdir -p $ROOTFS/usr/local/eb/recordings
sed -i '/^lxc\.net\./d' /var/lib/lxc/$MACH/config
sed -i '/^# Network configuration/d' /var/lib/lxc/$MACH/config

cat >> /var/lib/lxc/$MACH/config <<EOF
lxc.mount.entry = $SHARED/recordings usr/local/eb/recordings none bind 0 0

# Network configuration
lxc.net.0.type = veth
lxc.net.0.link = $BRIDGE
lxc.net.0.name = eth0
lxc.net.0.flags = up
lxc.net.0.ipv4.address = $IP/24
lxc.net.0.ipv4.gateway = auto

# Start options
lxc.start.auto = 1
lxc.start.order = 302
lxc.start.delay = 2
lxc.group = eb-group
lxc.group = onboot
EOF

# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host && break || true
    sleep 1
done

# ------------------------------------------------------------------------------
# HOSTNAME
# ------------------------------------------------------------------------------
lxc-attach -n $MACH -- zsh <<EOS
set -e
echo $MACH > /etc/hostname
sed -i 's/\(127.0.1.1\s*\).*$/\1$JITSI_FQDN $MACH/' /etc/hosts
hostname $MACH
EOS

# ------------------------------------------------------------------------------
# PACKAGES
# ------------------------------------------------------------------------------
# fake install
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -dy reinstall hostname
EOS

# update
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION update
apt-get $APT_PROXY_OPTION -y dist-upgrade
EOS

# gnupg, ngrep, ncat, jq, ruby-hocon
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install gnupg
apt-get $APT_PROXY_OPTION -y install ngrep ncat jq
apt-get $APT_PROXY_OPTION -y install ruby-hocon
EOS

# ssl packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install ssl-cert certbot
EOS

# jitsi
cp etc/apt/sources.list.d/jitsi-stable.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -qO /tmp/jitsi.gpg.key https://download.jitsi.org/jitsi-key.gpg.key
cat /tmp/jitsi.gpg.key | gpg --dearmor >/usr/share/keyrings/jitsi.gpg
apt-get update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<< \
    'jicofo jitsi-videobridge/jvb-hostname string $JITSI_FQDN'
debconf-set-selections <<< \
    'jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate (You will later get a chance to obtain a Let'\''s encrypt certificate)'

apt-get $APT_PROXY_OPTION -y --install-recommends install jitsi-meet
EOS

# jitsi-meet-tokens related packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install luarocks liblua5.2-dev
apt-get $APT_PROXY_OPTION -y install gcc git
EOS

# ------------------------------------------------------------------------------
# EXTERNAL IP
# ------------------------------------------------------------------------------
EXTERNAL_IP=$(dig -4 +short myip.opendns.com a @resolver1.opendns.com) || true
echo EXTERNAL_IP="$EXTERNAL_IP" >> $INSTALLER/000-source

# ------------------------------------------------------------------------------
# JMS SSH KEY
# ------------------------------------------------------------------------------
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cp $MACHINES/eb-jitsi-host/root/.ssh/jms-config /root/.ssh/

# create ssh key if not exists
if [[ ! -f /root/.ssh/jms ]] || [[ ! -f /root/.ssh/jms.pub ]]; then
    rm -f /root/.ssh/jms{,.pub}
    ssh-keygen -qP '' -t rsa -b 2048 -f /root/.ssh/jms
fi

# copy the public key to a downloadable place
cp /root/.ssh/jms.pub $ROOTFS/usr/share/jitsi-meet/static/

# ------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# ------------------------------------------------------------------------------
# certificates
cp /root/eb-ssl/eb-CA.pem $ROOTFS/usr/local/share/ca-certificates/jms-CA.crt
cp /root/eb-ssl/eb-CA.pem $ROOTFS/usr/share/jitsi-meet/static/jms-CA.crt
cp /root/eb-ssl/eb-jitsi.key $ROOTFS/etc/ssl/private/eb-cert.key
cp /root/eb-ssl/eb-jitsi.pem $ROOTFS/etc/ssl/certs/eb-cert.pem

lxc-attach -n $MACH -- zsh <<EOS
set -e
update-ca-certificates

chmod 640 /etc/ssl/private/eb-cert.key
chown root:ssl-cert /etc/ssl/private/eb-cert.key

rm /etc/jitsi/meet/$JITSI_FQDN.key
rm /etc/jitsi/meet/$JITSI_FQDN.crt
ln -s /etc/ssl/private/eb-cert.key /etc/jitsi/meet/$JITSI_FQDN.key
ln -s /etc/ssl/certs/eb-cert.pem /etc/jitsi/meet/$JITSI_FQDN.crt
EOS

# set-letsencrypt-cert
cp $MACHINES/common/usr/local/sbin/set-letsencrypt-cert $ROOTFS/usr/local/sbin/
chmod 744 $ROOTFS/usr/local/sbin/set-letsencrypt-cert

# certbot service
mkdir -p $ROOTFS/etc/systemd/system/certbot.service.d
cp $MACHINES/common/etc/systemd/system/certbot.service.d/override.conf \
    $ROOTFS/etc/systemd/system/certbot.service.d/
echo 'ExecStartPost=systemctl restart coturn.service' >> \
    $ROOTFS/etc/systemd/system/certbot.service.d/override.conf
lxc-attach -n $MACH -- systemctl daemon-reload

# coturn
cat >>$ROOTFS/etc/turnserver.conf <<EOF

# the following lines added by eb-jitsi
listening-ip=$IP
allowed-peer-ip=$IP
no-udp
EOF

lxc-attach -n $MACH -- zsh <<EOS
set -e
adduser turnserver ssl-cert
systemctl restart coturn.service
EOS

# prosody
mkdir -p $ROOTFS/etc/systemd/system/prosody.service.d
cp etc/systemd/system/prosody.service.d/override.conf \
    $ROOTFS/etc/systemd/system/prosody.service.d/
cp etc/prosody/conf.avail/network.cfg.lua $ROOTFS/etc/prosody/conf.avail/
ln -s ../conf.avail/network.cfg.lua $ROOTFS/etc/prosody/conf.d/
sed -i "/rate *=.*kb.s/  s/[0-9]*kb/1024kb/" \
    $ROOTFS/etc/prosody/prosody.cfg.lua
sed -i "s/^-- \(https_ports = { };\)/\1/" \
    $ROOTFS/etc/prosody/conf.avail/$JITSI_FQDN.cfg.lua
sed -i "/turns.*tcp/ s/host\s*=[^,]*/host = \"$TURN_FQDN\"/" \
    $ROOTFS/etc/prosody/conf.avail/$JITSI_FQDN.cfg.lua
sed -i "/turns.*tcp/ s/5349/443/" \
    $ROOTFS/etc/prosody/conf.avail/$JITSI_FQDN.cfg.lua
cp usr/share/jitsi-meet/prosody-plugins/*.lua \
    $ROOTFS/usr/share/jitsi-meet/prosody-plugins/
lxc-attach -n $MACH -- systemctl daemon-reload
lxc-attach -n $MACH -- systemctl restart prosody.service

# jicofo
sed -i '/^JICOFO_AUTH_PASSWORD=/a \
\
# set the maximum memory for the jicofo daemon\
JICOFO_MAX_MEMORY=3072m' \
    $ROOTFS/etc/jitsi/jicofo/config

lxc-attach -n $MACH -- zsh <<EOS
set -e
hocon -f /etc/jitsi/jicofo/jicofo.conf \
    set jicofo.conference.enable-auto-owner true
EOS

lxc-attach -n $MACH -- systemctl restart jicofo.service

# nginx
mkdir -p $ROOTFS/etc/systemd/system/nginx.service.d
cp etc/systemd/system/nginx.service.d/override.conf \
    $ROOTFS/etc/systemd/system/nginx.service.d/
cp $ROOTFS/etc/nginx/nginx.conf $ROOTFS/etc/nginx/nginx.conf.old
sed -i "/worker_connections/ s/\\S*;/8192;/" \
    $ROOTFS/etc/nginx/nginx.conf
mkdir -p $ROOTFS/usr/local/share/nginx/modules-available
cp usr/local/share/nginx/modules-available/jitsi-meet.conf \
    $ROOTFS/usr/local/share/nginx/modules-available/
sed -i "s/___LOCAL_IP___/$IP/" \
    $ROOTFS/usr/local/share/nginx/modules-available/jitsi-meet.conf
sed -i "s/___TURN_FQDN___/$TURN_FQDN/" \
    $ROOTFS/usr/local/share/nginx/modules-available/jitsi-meet.conf
mv $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN.conf \
    $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN.conf.old
cp etc/nginx/sites-available/jms.conf \
    $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN.conf
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/" \
    $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN.conf
sed -i "s/___TURN_FQDN___/$TURN_FQDN/" \
    $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN.conf

lxc-attach -n $MACH -- zsh <<EOS
ln -s /usr/local/share/nginx/modules-available/jitsi-meet.conf \
    /etc/nginx/modules-enabled/99-jitsi-meet-custom.conf
rm /etc/nginx/sites-enabled/default
rm -rf /var/www/html
ln -s /usr/share/jitsi-meet /var/www/html
EOS

lxc-attach -n $MACH -- systemctl daemon-reload
lxc-attach -n $MACH -- systemctl stop nginx.service
lxc-attach -n $MACH -- systemctl start nginx.service

# ------------------------------------------------------------------------------
# JVB
# ------------------------------------------------------------------------------
# default memory limit
sed -i '/^JVB_SECRET=/a \
\
# set the maximum memory for the JVB daemon\
VIDEOBRIDGE_MAX_MEMORY=3072m' \
    $ROOTFS/etc/jitsi/videobridge/config

# colibri
lxc-attach -n $MACH -- zsh <<EOS
set -e
hocon -f /etc/jitsi/videobridge/jvb.conf \
    set videobridge.apis.rest.enabled true
hocon -f /etc/jitsi/videobridge/jvb.conf \
    set videobridge.ice.udp.port 10000
EOS

# NAT harvester. these will be needed if this is an in-house server.
cat >>$ROOTFS/etc/jitsi/videobridge/sip-communicator.properties <<EOF
#org.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS=$IP
#org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=$REMOTE_IP
EOF

if [[ "$EXTERNAL_IP" != "$REMOTE_IP" ]]; then
    cat >>$ROOTFS/etc/jitsi/videobridge/sip-communicator.properties <<EOF
#org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=$EXTERNAL_IP
EOF
fi

# restart
lxc-attach -n $MACH -- systemctl restart jitsi-videobridge2.service

# ------------------------------------------------------------------------------
# TOOLS & SCRIPTS
# ------------------------------------------------------------------------------
# jicofo-log-analyzer
cp usr/local/bin/jicofo-log-analyzer $ROOTFS/usr/local/bin/
chmod 755 $ROOTFS/usr/local/bin/jicofo-log-analyzer

# ------------------------------------------------------------------------------
# CONTAINER SERVICES
# ------------------------------------------------------------------------------
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# ------------------------------------------------------------------------------
# HOST CUSTOMIZATION FOR JITSI
# ------------------------------------------------------------------------------
# jitsi tools
cp $MACHINES/eb-jitsi-host/usr/local/sbin/add-jvb-node /usr/local/sbin/
cp $MACHINES/eb-jitsi-host/usr/local/sbin/set-letsencrypt-cert /usr/local/sbin/
chmod 744 /usr/local/sbin/add-jvb-node
chmod 744 /usr/local/sbin/set-letsencrypt-cert
