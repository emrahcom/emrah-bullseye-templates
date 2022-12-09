# ------------------------------------------------------------------------------
# JVB.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="$TAG-jvb"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
DNS_RECORD=$(grep "address=/$MACH/" /etc/dnsmasq.d/$TAG-jvb | head -n1)
IP=${DNS_RECORD##*/}
SSH_PORT="30$(printf %03d ${IP##*.})"
echo JVB="$IP" >> $INSTALLER/000-source

# ------------------------------------------------------------------------------
# NFTABLES RULES
# ------------------------------------------------------------------------------
# the public ssh
nft delete element $TAG-nat tcp2ip { $SSH_PORT } 2>/dev/null || true
nft add element $TAG-nat tcp2ip { $SSH_PORT : $IP }
nft delete element $TAG-nat tcp2port { $SSH_PORT } 2>/dev/null || true
nft add element $TAG-nat tcp2port { $SSH_PORT : 22 }
# tcp/9090
nft delete element $TAG-nat tcp2ip { 9090 } 2>/dev/null || true
nft add element $TAG-nat tcp2ip { 9090 : $IP }
nft delete element $TAG-nat tcp2port { 9090 } 2>/dev/null || true
nft add element $TAG-nat tcp2port { 9090 : 9090 }
# udp/10000
nft delete element $TAG-nat udp2ip { 10000 } 2>/dev/null || true
nft add element $TAG-nat udp2ip { 10000 : $IP }
nft delete element $TAG-nat udp2port { 10000 } 2>/dev/null || true
nft add element $TAG-nat udp2port { 10000 : 10000 }

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
lxc-stop -n $TAG-bullseye
lxc-wait -n $TAG-bullseye -s STOPPED
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
lxc-copy -n $TAG-bullseye -N $MACH -p /var/lib/lxc/

# the shared directories
mkdir -p $SHARED/cache

# the container config
rm -rf $ROOTFS/var/cache/apt/archives
mkdir -p $ROOTFS/var/cache/apt/archives

cat >> /var/lib/lxc/$MACH/config <<EOF

# Start options
lxc.start.auto = 1
lxc.start.order = 301
lxc.start.delay = 2
lxc.group = $TAG-group
lxc.group = onboot
EOF

# container network
cp $MACHINE_COMMON/etc/systemd/network/eth0.network $ROOTFS/etc/systemd/network/
sed -i "s/___IP___/$IP/" $ROOTFS/etc/systemd/network/eth0.network
sed -i "s/___GATEWAY___/$HOST/" $ROOTFS/etc/systemd/network/eth0.network

# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host.loc && break || true
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
apt-get $APT_PROXY -dy reinstall hostname
EOS

# update
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY update
apt-get $APT_PROXY -y dist-upgrade
EOS

# gnupg, ngrep, ncat, jq, ruby-hocon
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY -y install gnupg
apt-get $APT_PROXY -y install ngrep ncat jq
apt-get $APT_PROXY -y install ruby-hocon
apt-get $APT_PROXY -y install openjdk-11-jre-headless
EOS

# jvb
cp etc/apt/sources.list.d/jitsi-stable.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -T 30 -qO /tmp/jitsi.gpg.key https://download.jitsi.org/jitsi-key.gpg.key
cat /tmp/jitsi.gpg.key | gpg --dearmor >/usr/share/keyrings/jitsi.gpg
apt-get update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<< \
    'jitsi-videobridge2 jitsi-videobridge/jvb-hostname string $JITSI_FQDN'

[[ -z "$JVB_VERSION" ]] && \
    apt-get $APT_PROXY -y --install-recommends install jitsi-videobridge2 || \
    apt-get $APT_PROXY -y --install-recommends install \
        jitsi-videobridge2=$JVB_VERSION

apt-mark hold jitsi-videobridge2
EOS

# ------------------------------------------------------------------------------
# JVB
# ------------------------------------------------------------------------------
cp $ROOTFS/etc/jitsi/videobridge/config $ROOTFS/etc/jitsi/videobridge/config.org
cp $ROOTFS/etc/jitsi/videobridge/jvb.conf \
    $ROOTFS/etc/jitsi/videobridge/jvb.conf.org
cp $ROOTFS/etc/jitsi/videobridge/sip-communicator.properties \
    $ROOTFS/etc/jitsi/videobridge/sip-communicator.properties.org

# add the custom config
cat etc/jitsi/videobridge/config.custom >>$ROOTFS/etc/jitsi/videobridge/config

# colibri
lxc-attach -n $MACH -- zsh <<EOS
set -e
hocon -f /etc/jitsi/videobridge/jvb.conf \
    set videobridge.apis.rest.enabled true
hocon -f /etc/jitsi/videobridge/jvb.conf \
    set videobridge.ice.udp.port 10000
EOS

# cluster related
sed -i "s/shard.HOSTNAME=.*/shard.HOSTNAME=$JITSI_FQDN/" \
    $ROOTFS/etc/jitsi/videobridge/sip-communicator.properties
sed -i "s/shard.PASSWORD=.*/shard.PASSWORD=$JVB_SHARD_PASSWD/" \
    $ROOTFS/etc/jitsi/videobridge/sip-communicator.properties

# NAT harvester. these will be needed if this is an in-house server.
cat etc/jitsi/videobridge/sip-communicator.custom.properties \
    >>$ROOTFS/etc/jitsi/videobridge/sip-communicator.properties
sed -i "s/___PUBLIC_IP___/$IP/" \
    $ROOTFS/etc/jitsi/videobridge/sip-communicator.properties
sed -i "s/___REMOTE_IP___/$REMOTE_IP/" \
    $ROOTFS/etc/jitsi/videobridge/sip-communicator.properties

if [[ "$EXTERNAL_IP" != "$REMOTE_IP" ]]; then
    cat >>$ROOTFS/etc/jitsi/videobridge/sip-communicator.properties <<EOF
#org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS=$EXTERNAL_IP
EOF
fi

# jvb-config
cp usr/local/sbin/jvb-config $ROOTFS/usr/local/sbin/
chmod 744 $ROOTFS/usr/local/sbin/jvb-config
cp etc/systemd/system/jvb-config.service $ROOTFS/etc/systemd/system/

lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl daemon-reload
systemctl enable jvb-config.service
EOS

# restart
lxc-attach -n $MACH -- systemctl restart jitsi-videobridge2.service

# ------------------------------------------------------------------------------
# CONTAINER SERVICES
# ------------------------------------------------------------------------------
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host.loc && break || true
    sleep 1
done
