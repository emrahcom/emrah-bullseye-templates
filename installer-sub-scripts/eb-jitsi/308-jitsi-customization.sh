# ------------------------------------------------------------------------------
# JITSI-CUSTOMIZATION.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="$TAG-jitsi-host"
cd $MACHINES/$MACH

JITSI_ROOTFS="/var/lib/lxc/$TAG-jitsi/rootfs"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_RUN_JITSI_CUSTOMIZATION" = true ]] && exit

echo
echo "------------------- JITSI CUSTOMIZATION -------------------"

# ------------------------------------------------------------------------------
# CONFIG.JS
# ------------------------------------------------------------------------------
# recording
cat $MACHINES/$TAG-jitsi/etc/jitsi/meet/config.recording.js >> \
    $JITSI_ROOTFS/etc/jitsi/meet/$JITSI_FQDN-config.js

# livestreaming
cat $MACHINES/$TAG-jitsi/etc/jitsi/meet/config.livestreaming.js >> \
    $JITSI_ROOTFS/etc/jitsi/meet/$JITSI_FQDN-config.js

# UI customizations
cat $MACHINES/$TAG-jitsi/etc/jitsi/meet/config.ui.js >> \
    $JITSI_ROOTFS/etc/jitsi/meet/$JITSI_FQDN-config.js

# substitutions
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/" \
    $JITSI_ROOTFS/etc/jitsi/meet/$JITSI_FQDN-config.js

# ------------------------------------------------------------------------------
# CUSTOMIZATION FOLDER & TOOLS
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