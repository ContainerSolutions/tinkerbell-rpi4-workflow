#!/bin/sh
export hw=$(cat hw.json)
docker exec -ti deploy_tink-cli_1 tink hardware push "$hw"
docker exec -ti deploy_tink-cli_1 tink target create '{"targets": {"machine1": {"mac_addr": "52:54:00:f9:79:28"}}}'
docker cp ubuntu.tmpl deploy_tink-cli_1:/root
docker exec -ti deploy_tink-cli_1 tink template create -p /root/ubuntu.tmpl -n ubuntu
