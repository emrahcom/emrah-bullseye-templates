# -----------------------------------------------------------------------------
# REVERSE-PROXY.SH
# -----------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
MACH="eb-reverse-proxy"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
DNS_RECORD=$(grep "address=/$MACH/" /etc/dnsmasq.d/eb-kratos | head -n1)
IP=${DNS_RECORD##*/}
SSH_PORT="30$(printf %03d ${IP##*.})"
echo REVERSE_PROXY="$IP" >> $INSTALLER/000-source

# -----------------------------------------------------------------------------
# NFTABLES RULES
# -----------------------------------------------------------------------------
# the public ssh
nft delete element eb-nat tcp2ip { $SSH_PORT } 2>/dev/null || true
nft add element eb-nat tcp2ip { $SSH_PORT : $IP }
nft delete element eb-nat tcp2port { $SSH_PORT } 2>/dev/null || true
nft add element eb-nat tcp2port { $SSH_PORT : 22 }
# the public http
nft delete element eb-nat tcp2ip { 80 } 2>/dev/null || true
nft add element eb-nat tcp2ip { 80 : $IP }
nft delete element eb-nat tcp2port { 80 } 2>/dev/null || true
nft add element eb-nat tcp2port { 80 : 80 }
# the public https
nft delete element eb-nat tcp2ip { 443 } 2>/dev/null || true
nft add element eb-nat tcp2ip { 443 : $IP }
nft delete element eb-nat tcp2port { 443 } 2>/dev/null || true
nft add element eb-nat tcp2port { 443 : 443 }

# -----------------------------------------------------------------------------
# INIT
# -----------------------------------------------------------------------------
[[ "$DONT_RUN_REVERSE_PROXY" = true ]] && exit

echo
echo "-------------------------- $MACH --------------------------"

# -----------------------------------------------------------------------------
# CONTAINER SETUP
# -----------------------------------------------------------------------------
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
lxc.start.order = 800
lxc.start.delay = 2
lxc.group = eb-group
lxc.group = onboot
EOF

# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# -----------------------------------------------------------------------------
# HOSTNAME
# -----------------------------------------------------------------------------
lxc-attach -n $MACH -- zsh <<EOS
set -e
echo $MACH > /etc/hostname
sed -i 's/\(127.0.1.1\s*\).*$/\1$MACH/' /etc/hosts
hostname $MACH
EOS

# -----------------------------------------------------------------------------
# PACKAGES
# -----------------------------------------------------------------------------
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

# the packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install ssl-cert ca-certificates certbot
apt-get $APT_PROXY_OPTION -y install nginx
EOS

# -----------------------------------------------------------------------------
# EXTERNAL IP
# -----------------------------------------------------------------------------
EXTERNAL_IP=$(dig -4 +short myip.opendns.com a @resolver1.opendns.com) || true
echo EXTERNAL_IP="$EXTERNAL_IP" >> $INSTALLER/000-source

# -----------------------------------------------------------------------------
# SELF-SIGNED CERTIFICATE
# -----------------------------------------------------------------------------
cd /root/eb-ssl
rm -f /root/eb-ssl/ssl-reverse-proxy.*

# the extension file for multiple hosts:
# the container IP, the host IP and the host names
cat >ssl-reverse-proxy.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
EOF

echo "DNS.1 = $KRATOS_FQDN" >>ssl-reverse-proxy.ext
echo "DNS.2 = $SECUREAPP_FQDN" >>ssl-reverse-proxy.ext
echo "IP.1 = $IP" >>ssl-reverse-proxy.ext
echo "IP.2 = $REMOTE_IP" >>ssl-reverse-proxy.ext
[[ -n "$EXTERNAL_IP" ]] && [[ "$EXTERNAL_IP" != "$REMOTE_IP" ]] \
     && echo "IP.3 = $EXTERNAL_IP" >>ssl-reverse-proxy.ext \
     || true

# the domain key and the domain certificate
openssl req -nodes -newkey rsa:2048 \
    -keyout ssl-reverse-proxy.key -out ssl-reverse-proxy.csr \
    -subj "/O=emrah-buster/OU=jitsi/CN=$JITSI_HOST"
openssl x509 -req -CA eb-CA.pem -CAkey eb-CA.key -CAcreateserial \
    -days 10950 -in ssl-reverse-proxy.csr -out ssl-reverse-proxy.pem \
    -extfile ssl-reverse-proxy.ext

cd $MACHINES/$MACH

# -----------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# -----------------------------------------------------------------------------
cp /root/eb-ssl/ssl-reverse-proxy.key $ROOTFS/etc/ssl/private/ssl-eb.key
cp /root/eb-ssl/ssl-reverse-proxy.pem $ROOTFS/etc/ssl/certs/ssl-eb.pem

# -----------------------------------------------------------------------------
# CONTAINER SERVICES
# -----------------------------------------------------------------------------
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING
