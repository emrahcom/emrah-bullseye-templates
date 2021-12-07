# ------------------------------------------------------------------------------
# JVB.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="eb-jvb"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
DNS_RECORD=$(grep "address=/$MACH/" /etc/dnsmasq.d/eb-jvb | head -n1)
IP=${DNS_RECORD##*/}
SSH_PORT="30$(printf %03d ${IP##*.})"
echo JVB="$IP" >> $INSTALLER/000-source

# ------------------------------------------------------------------------------
# NFTABLES RULES
# ------------------------------------------------------------------------------
# the public ssh
nft delete element eb-nat tcp2ip { $SSH_PORT } 2>/dev/null || true
nft add element eb-nat tcp2ip { $SSH_PORT : $IP }
nft delete element eb-nat tcp2port { $SSH_PORT } 2>/dev/null || true
nft add element eb-nat tcp2port { $SSH_PORT : 22 }
# tcp/9090
nft delete element eb-nat tcp2ip { 9090 } 2>/dev/null || true
nft add element eb-nat tcp2ip { 9090 : $IP }
nft delete element eb-nat tcp2port { 9090 } 2>/dev/null || true
nft add element eb-nat tcp2port { 9090 : 9090 }
# udp/10000
nft delete element eb-nat udp2ip { 10000 } 2>/dev/null || true
nft add element eb-nat udp2ip { 10000 : $IP }
nft delete element eb-nat udp2port { 10000 } 2>/dev/null || true
nft add element eb-nat udp2port { 10000 : 10000 }

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_RUN_JVB" = true ]] && exit

echo
echo "-------------------------- $MACH --------------------------"

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

# the container config
rm -rf $ROOTFS/var/cache/apt/archives
mkdir -p $ROOTFS/var/cache/apt/archives
sed -i '/^lxc\.net\./d' /var/lib/lxc/$MACH/config
sed -i '/^# Network configuration/d' /var/lib/lxc/$MACH/config

cat >> /var/lib/lxc/$MACH/config <<EOF

# Network configuration
lxc.net.0.type = veth
lxc.net.0.link = $BRIDGE
lxc.net.0.name = eth0
lxc.net.0.flags = up
lxc.net.0.ipv4.address = $IP/24
lxc.net.0.ipv4.gateway = auto

# Start options
lxc.start.auto = 1
lxc.start.order = 301
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
sed -i 's/\(127.0.1.1\s*\).*$/\1$MACH/' /etc/hosts
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

# gnupg, ngrep, ncat, jq
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install gnupg
apt-get $APT_PROXY_OPTION -y install ngrep ncat jq
EOS

# jvb
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
    'jitsi-videobridge2 jitsi-videobridge/jvb-hostname string $JITSI_FQDN'

apt-get $APT_PROXY_OPTION -y --install-recommends install jitsi-videobridge2
EOS

# ------------------------------------------------------------------------------
# JVB
# ------------------------------------------------------------------------------
# disable the certificate check for prosody connection
cat >>$ROOTFS/etc/jitsi/videobridge/sip-communicator.properties <<EOF
org.jitsi.videobridge.xmpp.user.shard.DISABLE_CERTIFICATE_VERIFICATION=true
EOF

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

# restart
lxc-attach -n $MACH -- systemctl restart jitsi-videobridge2.service

# jvb-config
cp usr/local/sbin/jvb-config $ROOTFS/usr/local/sbin/
chmod 744 $ROOTFS/usr/local/sbin/jvb-config
cp etc/systemd/system/jvb-config.service $ROOTFS/etc/systemd/system/

lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl daemon-reload
systemctl enable jvb-config.service
EOS

# ------------------------------------------------------------------------------
# CONTAINER SERVICES
# ------------------------------------------------------------------------------
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING
