# ------------------------------------------------------------------------------
# SIP.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="eb-sip-template"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
PJPROJECT_REPO="https://github.com/jitsi/pjproject"
PJPROJECT_BRANCH="jibri-2.10-dev1"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_RUN_SIP" = true ]] && exit

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
systemctl stop sip-ephemeral-container.service

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

cat >> /var/lib/lxc/$MACH/config <<EOF

# Devices
lxc.cgroup2.devices.allow = c 116:* rwm
lxc.cgroup2.devices.allow = c 81:* rwm
lxc.mount.entry = /dev/snd dev/snd none bind,optional,create=dir
lxc.mount.entry = /dev/video2 dev/video2 none bind,optional,create=file
lxc.mount.entry = /dev/video3 dev/video3 none bind,optional,create=file
lxc.mount.entry = /dev/video4 dev/video4 none bind,optional,create=file
lxc.mount.entry = /dev/video5 dev/video5 none bind,optional,create=file
lxc.mount.entry = /dev/video6 dev/video6 none bind,optional,create=file
lxc.mount.entry = /dev/video7 dev/video7 none bind,optional,create=file
lxc.mount.entry = /dev/video8 dev/video8 none bind,optional,create=file
lxc.mount.entry = /dev/video9 dev/video9 none bind,optional,create=file

# Start options
lxc.start.auto = 1
lxc.start.order = 301
lxc.start.delay = 2
lxc.group = eb-group
lxc.group = eb-sip
EOF

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
# HOST PACKAGES
# ------------------------------------------------------------------------------
zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install kmod alsa-utils
apt-get $APT_PROXY_OPTION -y install v4l2loopback-dkms v4l2loopback-utils
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

# packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install gnupg unzip unclutter
apt-get $APT_PROXY_OPTION -y install libnss3-tools
apt-get $APT_PROXY_OPTION -y install va-driver-all vdpau-driver-all
apt-get $APT_PROXY_OPTION -y --install-recommends install ffmpeg
apt-get $APT_PROXY_OPTION -y install x11vnc
EOS

# google chrome
cp etc/apt/sources.list.d/google-chrome.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -T 30 -qO /tmp/google-chrome.gpg.key \
    https://dl.google.com/linux/linux_signing_key.pub
apt-key add /tmp/google-chrome.gpg.key
apt-get $APT_PROXY_OPTION update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y --install-recommends install google-chrome-stable
apt-mark hold google-chrome-stable
EOS

# chromedriver
lxc-attach -n $MACH -- zsh <<EOS
set -e
CHROME_VER=\$(dpkg -s google-chrome-stable | egrep "^Version" | \
    cut -d " " -f2 | cut -d. -f1)
CHROMEDRIVER_VER=\$(curl -s \
    https://chromedriver.storage.googleapis.com/LATEST_RELEASE_\$CHROME_VER)
wget -T 30 -qO /tmp/chromedriver_linux64.zip \
    https://chromedriver.storage.googleapis.com/\$CHROMEDRIVER_VER/chromedriver_linux64.zip
unzip /tmp/chromedriver_linux64.zip -d /usr/local/bin/
chmod 755 /usr/local/bin/chromedriver
EOS

# jibri
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
apt-get $APT_PROXY_OPTION -y install openjdk-11-jre-headless

[[ -z "$JIBRI_VERSION" ]] && \
    apt-get $APT_PROXY_OPTION -y install jibri || \
    apt-get $APT_PROXY_OPTION -y install jibri=$JIBRI_VERSION
apt-mark hold jibri
EOS

# pjproject releated packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install build-essential
apt-get $APT_PROXY_OPTION -y install libv4l-dev libsdl2-dev libavcodec-dev \
    libavdevice-dev libavfilter-dev libavformat-dev libavresample-dev \
    libavutil-dev libswresample-dev libswscale-dev libasound2-dev libopus-dev \
    libvpx-dev
EOS

# removed packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y purge upower
EOS

# ------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# ------------------------------------------------------------------------------
# disable ssh service
lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl stop ssh.service
systemctl disable ssh.service
EOS

# snd_aloop module
[ -z "$(egrep '^snd_aloop' /etc/modules)" ] && echo snd_aloop >>/etc/modules
cp $MACHINES/eb-sip-host/etc/modprobe.d/alsa-loopback.conf /etc/modprobe.d/
rmmod -f snd_aloop || true
modprobe snd_aloop || true
[[ "$DONT_CHECK_SND_ALOOP" = true ]] || [[ -n "$(lsmod | ack snd_aloop)" ]]

# v4l2loopback module
[ -z "$(egrep '^v4l2loopback' /etc/modules)" ] && \
    echo v4l2loopback >>/etc/modules
cp $MACHINES/eb-sip-host/etc/modprobe.d/v4l2loopback.conf /etc/modprobe.d/
rmmod -f v4l2loopback || true
modprobe v4l2loopback || true
[[ "$DONT_CHECK_V4L2LOOPBACK" = true ]] || \
    [[ -n "$(lsmod | ack v4l2loopback)" ]]

# google chrome managed policies
mkdir -p $ROOTFS/etc/opt/chrome/policies/managed
cp etc/opt/chrome/policies/managed/eb-policies.json \
    $ROOTFS/etc/opt/chrome/policies/managed/

# ------------------------------------------------------------------------------
# JIBRI
# ------------------------------------------------------------------------------
cp $ROOTFS/etc/jitsi/jibri/xorg-video-dummy.conf \
    $ROOTFS/etc/jitsi/jibri/xorg-video-dummy.conf.org
cp $ROOTFS/etc/jitsi/jibri/pjsua.config $ROOTFS/etc/jitsi/jibri/pjsua.config.org
cp $ROOTFS/opt/jitsi/jibri/pjsua.sh $ROOTFS/opt/jitsi/jibri/pjsua.sh.org
cp $ROOTFS/opt/jitsi/jibri/finalize_sip.sh \
    $ROOTFS/opt/jitsi/jibri/finalize_sip.sh.org

# meta
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /root/meta
VERSION=\$(apt-cache policy jibri | grep Installed | rev | cut -d' ' -f1 | rev)
echo \$VERSION > /root/meta/jibri-version
EOS

# resolution 1280x720
lxc-attach -n $MACH -- zsh <<EOS
set -e
sed -ri "s/^(\s*)Virtual 1920/\1#Virtual 1920/" \
    /etc/jitsi/jibri/xorg-video-dummy.conf
sed -ri "s/^(\s*)#Virtual 1280/\1Virtual 1280/" \
    /etc/jitsi/jibri/xorg-video-dummy.conf
EOS

# xorg DISPLAY :1
cp etc/systemd/system/sip-xorg.service \
    $ROOTFS/etc/systemd/system/sip-xorg.service
lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl daemon-reload
systemctl enable sip-xorg.service
EOS

# icewm DISPLAY :1
cp etc/systemd/system/sip-icewm.service \
    $ROOTFS/etc/systemd/system/sip-icewm.service
lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl daemon-reload
systemctl enable sip-icewm.service
EOS

# jibri groups
lxc-attach -n $MACH -- zsh <<EOS
set -e
chsh -s /bin/bash jibri
usermod -aG adm,audio,video,plugdev jibri
chown jibri:jibri /home/jibri
EOS

# jibri, icewm
mkdir -p $ROOTFS/home/jibri/.icewm
cp home/jibri/.icewm/theme $ROOTFS/home/jibri/.icewm/
cp home/jibri/.icewm/prefoverride $ROOTFS/home/jibri/.icewm/
cp home/jibri/.icewm/startup $ROOTFS/home/jibri/.icewm/
chmod 755 $ROOTFS/home/jibri/.icewm/startup

# pki
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /home/jibri/.pki/nssdb
chmod 700 /home/jibri/.pki
chmod 700 /home/jibri/.pki/nssdb
chown jibri:jibri /home/jibri/.pki -R
EOS

# jibri config
cp etc/jitsi/jibri/jibri.conf $ROOTFS/etc/jitsi/jibri/

# sip ephemeral config service
cp usr/local/sbin/sip-ephemeral-config $ROOTFS/usr/local/sbin/
chmod 744 $ROOTFS/usr/local/sbin/sip-ephemeral-config
cp etc/systemd/system/sip-ephemeral-config.service \
    $ROOTFS/etc/systemd/system/

lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl daemon-reload
systemctl enable sip-ephemeral-config.service
EOS

# jibri service
lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl enable jibri.service
systemctl start jibri.service
EOS

# jibri, vnc
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /home/jibri/.vnc
x11vnc -storepasswd jibri /home/jibri/.vnc/passwd
chown jibri:jibri /home/jibri/.vnc -R
EOS

# jibri, Xdefaults
cp home/jibri/.Xdefaults $ROOTFS/home/jibri/
lxc-attach -n $MACH -- zsh <<EOS
set -e
chown jibri:jibri /home/jibri/.Xdefaults
EOS

# ------------------------------------------------------------------------------
# PJSUA
# ------------------------------------------------------------------------------
# build
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir /home/jibri/src
chown jibri:jibri /home/jibri/src
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
su -l jibri <<EOSS
    set -e

    cd ~/src
    git clone -b $PJPROJECT_BRANCH $PJPROJECT_REPO
    cd pjproject

    ./configure
    make dep
    make
EOSS
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
cp /home/jibri/src/pjproject/pjsip-apps/bin/pjsua-x86_64-unknown-linux-gnu \
    /usr/local/bin/pjsua
chmod 755 /usr/local/bin/pjsua
EOS

# pjsua scripts
cp opt/jitsi/jibri/pjsua.sh $ROOTFS/opt/jitsi/jibri/pjsua.sh
cp opt/jitsi/jibri/finalize_sip.sh $ROOTFS/opt/jitsi/jibri/finalize_sip.sh

# ------------------------------------------------------------------------------
# CONTAINER SERVICES
# ------------------------------------------------------------------------------
lxc-attach -n $MACH -- systemctl stop jibri-xorg.service
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED

# ------------------------------------------------------------------------------
# CLEAN UP
# ------------------------------------------------------------------------------
find $ROOTFS/var/log/jitsi/jibri -type f -delete

# ------------------------------------------------------------------------------
# EPHEMERAL SIP CONTAINERS
# ------------------------------------------------------------------------------
# sip-ephemeral-container service
cp $MACHINES/eb-sip-host/usr/local/sbin/sip-ephemeral-start /usr/local/sbin/
cp $MACHINES/eb-sip-host/usr/local/sbin/sip-ephemeral-stop /usr/local/sbin/
chmod 744 /usr/local/sbin/sip-ephemeral-start
chmod 744 /usr/local/sbin/sip-ephemeral-stop

cp $MACHINES/eb-sip-host/etc/systemd/system/sip-ephemeral-container.service \
    /etc/systemd/system/

systemctl daemon-reload
systemctl enable sip-ephemeral-container.service
systemctl start sip-ephemeral-container.service
