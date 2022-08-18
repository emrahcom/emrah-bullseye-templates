# ------------------------------------------------------------------------------
# JITSI-CUSTOMIZATION.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="eb-jitsi-host"
cd $MACHINES/$MACH

JITSI_ROOTFS="/var/lib/lxc/eb-jitsi/rootfs"
JITSI_MEET_CONFIG="$JITSI_ROOTFS/etc/jitsi/meet/$JITSI_FQDN-config.js"
JITSI_MEET_INTERFACE="$JITSI_ROOTFS/usr/share/jitsi-meet/interface_config.js"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[ "$DONT_RUN_JITSI_CUSTOMIZATION" = true ] && exit

echo
echo "------------------- JITSI CUSTOMIZATION -------------------"

# ------------------------------------------------------------------------------
# JITSI-CUSTOMIZATION
# ------------------------------------------------------------------------------
FOLDER="/root/jitsi-customization"

# is there an old customization folder?
if [[ -d "/root/jitsi-customization" ]]; then
    FOLDER="/root/jitsi-customization-new"
    rm -rf $FOLDER

    echo "There is already an old customization folder."
    echo "A new folder will be created as $FOLDER"
fi

cp -arp root/jitsi-customization $FOLDER

sed -i "s/___TURN_FQDN___/$TURN_FQDN/g" $FOLDER/README.md
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/g" $FOLDER/README.md
sed -i "s/___TURN_FQDN___/$TURN_FQDN/g" $FOLDER/customize.sh
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/g" $FOLDER/customize.sh

mkdir -p $FOLDER/files
cp $JITSI_ROOTFS/etc/jitsi/meet/$JITSI_FQDN-config.js $FOLDER/files/
cp $JITSI_ROOTFS//usr/share/jitsi-meet/interface_config.js $FOLDER/files/
cp $JITSI_ROOTFS/usr/share/jitsi-meet/images/favicon.ico $FOLDER/files/
cp $JITSI_ROOTFS/usr/share/jitsi-meet/images/watermark.svg $FOLDER/files/

# ------------------------------------------------------------------------------
# CONFIG.JS
# ------------------------------------------------------------------------------
cp $JITSI_MEET_CONFIG $JITSI_MEET_CONFIG.org

# ------------------------------------------------------------------------------
# INTERFACE_CONFIG.JS
# ------------------------------------------------------------------------------
cp $JITSI_MEET_INTERFACE $JITSI_MEET_INTERFACE.org
