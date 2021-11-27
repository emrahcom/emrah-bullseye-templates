## JITSI CUSTOMIZATION

Add the customization notes, scripts and related files in this folder.

#### TLS update

Run the following command to regenerate the TLS certificates.

```bash
set-letsencrypt-cert ___JITSI_FQDN___,___TURN_FQDN___
```

#### Customization script

Customize the `customize.sh` script according to your needs.

Usage:

```bash
bash customize.sh
```

#### Commands

Some commands to be useful in the `eb-jitsi` container

```bash
lxc-attach -n eb-jitsi -- curl http://127.0.0.1:8080/colibri/conferences
lxc-attach -n eb-jitsi -- curl http://127.0.0.1:8888/stats
lxc-attach -n eb-jitsi -- \
    egrep -o "\[room=.*\].*(Created|Stopped)" /var/log/jitsi/jicofo.log
```

```bash
diff /var/lib/lxc/eb-jitsi/rootfs/etc/jitsi/meet/___JITSI_FQDN___-config.js \
    files/jitsi.mydomain.corp-config.js
diff /var/lib/lxc/eb-jitsi/rootfs/usr/share/jitsi-meet/interface_config.js \
    files/interface_config.js
```
