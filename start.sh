#!/bin/bash

HOST_NAME=$(hostname)
PASSWD=${HACLUSTER}
HOSTS=()
HOSTS+=("${HOST_NAME}")

for node in $(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/ip/ | jq -r '.node.nodes[] | .key + "=" + .value'); do
IFS='=' read -ra RESULT <<< $node
IP=${RESULT[-1]}
IFS='/' read -ra KEY_MAP <<< ${RESULT[0]}
HOST=${KEY_MAP[-1]}
if [ "${HOST}" != "mysql-${HOST_NAME}" ]; then
echo "${me} => Get node ip/name - ${IP}/${HOST}"
echo "${IP}    ${HOST}" | sed 's/mysql-//g' >> /etc/hosts
H=$(echo "${HOST}" | sed 's/mysql-//g')
HOSTS+=("${H}")
fi
done

echo "hacluster:${HACLUSTER}" | chgpasswd
curl --create-dirs -o /usr/lib/ocf/resource.d/percona/IPaddr3 https://raw.githubusercontent.com/percona/percona-pacemaker-agents/master/agents/IPaddr3
chmod u+x /usr/lib/ocf/resource.d/percona/IPaddr3

if [ "$(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/leader | jq -r .node.value)" == "mysql-${HOSTNAME}" ]; then
pcs cluster auth ${HOSTS[@]} -u hacluster -p ${HACLUSTER} --force
pcs cluster setup --force --name Cluster ${HOSTS[@]}
pcs cluster start --all
pcs property set no-quorum-policy=ignore
pcs property set stonith-enabled=false
pcs resource create ClusterIP ocf:percona:IPaddr3 params ip="${VIRTUAL_IP}" cidr_netmask="24" nic="eth0" clusterip_hash="sourceip" op monitor interval="10s"
pcs resource clone ClusterIP meta clone-max=${#HOSTS[@]} clone-node-max=${#HOSTS[@]} globally-unique=true
fi

pcs cluster status