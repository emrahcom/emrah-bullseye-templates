JITSI CUSTOMIZATION
===================
Add the customization notes, scripts and related files in this folder.

# TLS update
Run the following command to regenerate the TLS certificates.

```bash
set-letsencrypt-cert ___JITSI_HOST___,___TURN_HOST___
```

# Customization script
Customize the `customize.sh` script according to your needs.

Usage:

```bash
bash customize.sh
```

# Commands
Some commands to be useful in the `eb-jitsi` container

```bash
lxc-attach -n eb-jitsi

    curl http://127.0.0.1:8080/colibri/conferences
    curl http://127.0.0.1:8888/stats
    egrep -o "\[room=.*\].*(Created|Stopped)" /var/log/jitsi/jicofo.log

    exit
```
