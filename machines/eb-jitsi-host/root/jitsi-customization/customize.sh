#!/bin/bash
set -e

# ------------------------------------------------------------------------------
# This script customizes the Jitsi installation. Run it on the host machine.
#
# usage:
#     bash customize.sh
# ------------------------------------------------------------------------------
APP_NAME="Jitsi Meet"
WATERMARK_LINK="https://jitsi.org"

BASEDIR=$(dirname $0)
JITSI_ROOTFS="/var/lib/lxc/eb-jitsi/rootfs"
JITSI_MEET="$JITSI_ROOTFS/usr/share/jitsi-meet"
JITSI_MEET_INTERFACE="$JITSI_ROOTFS/usr/share/jitsi-meet/interface_config.js"
JITSI_MEET_CONFIG="$JITSI_ROOTFS/etc/jitsi/meet/___JITSI_FQDN___-config.js"
JITSI_MEET_VERSION=$(lxc-attach -n eb-jitsi -- apt-cache policy jitsi-meet | \
                     grep Installed | cut -d: -f2 | xargs)
PROSODY="$JITSI_ROOTFS/etc/prosody"
PROSODY_CONFIG="$PROSODY/conf.avail/___JITSI_FQDN___.cfg.lua"
JICOFO="$JITSI_ROOTFS/etc/jitsi/jicofo"

FAVICON="$BASEDIR/favicon.ico"
WATERMARK="$BASEDIR/watermark.svg"

# ------------------------------------------------------------------------------
# backup
# ------------------------------------------------------------------------------
DATE=$(date +'%Y%m%d%H%M%S')
BACKUP=$BASEDIR/backup/$DATE

mkdir -p $BACKUP
cp $JITSI_MEET_INTERFACE $BACKUP/
cp $JITSI_MEET_CONFIG $BACKUP/
cp $JITSI_MEET/images/favicon.ico $BACKUP/
cp $JITSI_MEET/images/watermark.svg $BACKUP/

# ------------------------------------------------------------------------------
# jitsi-meet config.js
# ------------------------------------------------------------------------------
sed -i "/startWithVideoMuted:/ s~//\s*~~" $JITSI_MEET_CONFIG
sed -i "/startWithVideoMuted:/ s~:.*~: true,~" $JITSI_MEET_CONFIG
#sed -i "/^\s*toolbarButtons:/,/\]/d" $JITSI_MEET_CONFIG
#sed -i "/\/\/\s*toolbarButtons:/i \
#\    toolbarButtons: [\\
#\      'camera',\\
#\      'chat',\\
#\      'desktop',\\
#\      'filmstrip',\\
#\      'fullscreen',\\
#\      'hangup',\\
#\      'livestreaming',\\
#\      'microphone',\\
#\      'profile',\\
#\      'raisehand',\\
#\      'recording',\\
#\      'select-background',\\
#\      'settings',\\
#\      'shareaudio',\\
#\      'sharedvideo',\\
#\      'tileview',\\
#\      'toggle-camera',\\
#\      'videoquality',\\
#\      '__end'\\
#\    ]," $JITSI_MEET_CONFIG
#sed -i "/^\s*notifications:/d" $JITSI_MEET_CONFIG
#sed -i "/\/\/\s*notifications:/i \
#\    notifications: []," $JITSI_MEET_CONFIG


# ------------------------------------------------------------------------------
# jitsi-meet interface_config.js
# ------------------------------------------------------------------------------
cp $FAVICON $JITSI_MEET/
cp $FAVICON $JITSI_MEET/images/
cp $WATERMARK $JITSI_MEET/images/

#sed -i "s/watermark.svg/watermark.png/" $JITSI_MEET_INTERFACE
sed -i "/^\s*APP_NAME:/ s~:.*~: '$APP_NAME',~" $JITSI_MEET_INTERFACE
sed -i "/^\s*DISABLE_JOIN_LEAVE_NOTIFICATIONS:/ s~:.*~: true,~" \
    $JITSI_MEET_INTERFACE
sed -i "/^\s*GENERATE_ROOMNAMES_ON_WELCOME_PAGE:/ s~:.*~: false,~" \
    $JITSI_MEET_INTERFACE
sed -i "/^\s*JITSI_WATERMARK_LINK:/ s~:.*~: '$WATERMARK_LINK',~" \
    $JITSI_MEET_INTERFACE

# ------------------------------------------------------------------------------
# jwt
# ------------------------------------------------------------------------------
#APP_ID="myappid"
#APP_SECRET="myappsecret"

#lxc-attach -n eb-jitsi -- zsh <<EOS
#set -e
#export DEBIAN_FRONTEND=noninteractive
#debconf-set-selections <<< \
#    'jitsi-meet-tokens jitsi-meet-tokens/appid string $APP_ID'
#debconf-set-selections <<< \
#    'jitsi-meet-tokens jitsi-meet-tokens/appsecret password $APP_SECRET'
#apt-get -y install jitsi-meet-tokens
#EOF

#sed -i '/allow_empty_token/d' $PROSODY_CONFIG
#sed -i '/token_affiliation/d' $PROSODY_CONFIG
#sed -i '/token_owner_party/d' $PROSODY_CONFIG
#sed -i '/\s*app_secret=/a \
#\    allow_empty_token = false' $PROSODY_CONFIG
#sed -i '/\s*"token_verification"/a \
#\        "token_affiliation";' $PROSODY_CONFIG
#sed -i '/\s*"token_affiliation"/a \
#\        "token_owner_party";' $PROSODY_CONFIG
#lxc-attach -n eb-jitsi -- systemctl restart prosody.service

#lxc-attach -n eb-jitsi -- zsh <<EOS
#set -e
#hocon -f /etc/jitsi/jicofo/jicofo.conf \
#    set jicofo.conference.enable-auto-owner false
#systemctl restart jicofo.service
#systemctl restart jitsi-videobridge2.service
#EOS

#sed -i "/disableProfile:/ s~//\s*~~" $JITSI_MEET_CONFIG
#sed -i "/disableProfile:/ s~:.*~: true,~" $JITSI_MEET_CONFIG
#sed -i "/enableFeaturesBasedOnToken:/ s~//\s*~~" $JITSI_MEET_CONFIG
#sed -i "/enableFeaturesBasedOnToken:/ s~:.*~: true,~" $JITSI_MEET_CONFIG
