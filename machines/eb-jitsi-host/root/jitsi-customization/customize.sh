#!/bin/bash
set -e

# ------------------------------------------------------------------------------
# This script customizes the Jitsi installation. Run it on the host machine.
#
# usage:
#     bash customize.sh
# ------------------------------------------------------------------------------
BASEDIR=$(dirname $0)
JITSI_VERSION=$(lxc-attach -n eb-jitsi -- apt-cache policy jitsi-meet | \
                     grep Installed | cut -d: -f2 | xargs)
JITSI_ROOTFS="/var/lib/lxc/eb-jitsi/rootfs"
JITSI_MEET="$JITSI_ROOTFS/usr/share/jitsi-meet"
JITSI_CONFIG="$JITSI_ROOTFS/etc/jitsi/meet/___JITSI_FQDN___-config.js"
JITSI_INTERFACE="$JITSI_ROOTFS/usr/share/jitsi-meet/interface_config.js"
PROSODY_CONFIG="$JITSI_ROOTFS/etc/prosody/conf.avail/___JITSI_FQDN___.cfg.lua"

# ------------------------------------------------------------------------------
# backup
# ------------------------------------------------------------------------------
DATE=$(date +'%Y%m%d%H%M%S')
BACKUP=$BASEDIR/backup/$DATE

mkdir -p $BACKUP
cp $JITSI_CONFIG $BACKUP/
cp $JITSI_INTERFACE $BACKUP/
cp $JITSI_MEET/images/favicon.ico $BACKUP/
cp $JITSI_MEET/images/watermark.svg $BACKUP/
cp $PROSODY_CONFIG $BACKUP/
cp $PROSODY_CONFIG $BACKUP/

# ------------------------------------------------------------------------------
# config.js
# ------------------------------------------------------------------------------
[[ -f "$BASEDIR/___JITSI_FQDN___-config.js" ]] && \
    cp $BASEDIR/___JITSI_FQDN___-config.js $JITSI_CONFIG

# ------------------------------------------------------------------------------
# interface_config.js
# ------------------------------------------------------------------------------
[[ -f "$BASEDIR/interface_config.js" ]] && \
    cp $BASEDIR/interface_config.js $JITSI_INTERFACE

# ------------------------------------------------------------------------------
# static
# ------------------------------------------------------------------------------
[[ -f "$BASEDIR/favicon.ico" ]] && cp $BASEDIR/favicon.ico $JITSI_MEET/
[[ -f "$BASEDIR/favicon.ico" ]] && cp $BASEDIR/favicon.ico $JITSI_MEET/images/
[[ -f "$BASEDIR/watermark.svg" ]] && \
    cp $BASEDIR/watermark.svg $JITSI_MEET/images/

# ------------------------------------------------------------------------------
# jwt
# ------------------------------------------------------------------------------
# Set disableProfile and enableFeaturesBasedOnToken in local config.js if needed

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
#EOS

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
