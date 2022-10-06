Clone the following repo here:
https://github.com/jitsi-contrib/sip-dial-plan.git

In `config.ts`:

- set `HOSTNAME` as `0.0.0.0`
- check `TOKEN_SECRET`
- check `TOKEN_ALGORITHM`

On `Jitsi` server:

- Enable `token` authentication for `prosody`
- Enable `token_affiliation` for `prosody`
- Disable `enable-auto-owner` for `jicofo`

- in `config.js`

```javascript
peopleSearchQueryTypes: ['conferenceRooms'],
peopleSearchUrl: 'https://jitsi.mydomain.corp/get-dial-plan',
```

- in `Nginx` config

```conf
upstream sip-dial-plan {
    zone upstreams 64K;
    server 172.22.22.16:9001;
    keepalive 2;
}
```

```conf
location = /get-dial-plan {
    proxy_pass http://sip-dial-plan;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-For $remote_addr;
}
```
