#!/bin/bash

HOST_NAME=$(hostname)
PASSWD=${HACLUSTER}
HOSTS=()
MAX_NODES=$(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/max_nodes | jq -r '.node.value')

for node in $(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/ip/ | jq -r '.node.nodes[] | .key + "=" + .value'); do
IFS='=' read -ra RESULT <<< $node
IP=${RESULT[-1]}
IFS='/' read -ra KEY_MAP <<< ${RESULT[0]}
HOST=${KEY_MAP[-1]}
echo "${me} => Get node ip/name - ${IP}/${HOST}"
echo "${IP}    ${HOST}" | sed 's/mysql-//g' >> /etc/hosts
H=$(echo "${HOST}" | sed 's/mysql-//g')
HOSTS+=("${H}")
done

IN=$(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs_nodes/$(hostname) | jq -r .node.value)
if [ "${IN}" == "in" ]; then
echo "Node $(hostname) back in cluster"
curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs_nodes/$(hostname) -XPUT -d value="out"
fi

echo "hacluster:${HACLUSTER}" | chpasswd
service pcsd start
rm -f /etc/corosync/corosync.conf
sleep 10
service pcsd status
curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs/${HOST_NAME} -XPUT -d value="True"

if [ "$(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/leader | jq -r .node.value)" == "mysql-${HOSTNAME}" ]; then
while  [ $(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs/ | jq -r ".node.nodes[] | select(.value == \"$(printf 'True')\") | .key" | wc -l) -lt $((${MAX_NODES})) ]; do
sleep 1
done
pcs cluster auth ${HOSTS[@]} -u hacluster -p ${HACLUSTER} --force
pcs cluster setup --force --name Cluster ${HOSTS[@]}
pcs cluster start --all
pcs property set no-quorum-policy=ignore
pcs property set stonith-enabled=false
pcs resource create ClusterIP ocf:percona:IPaddr3 params ip="${VIRTUAL_IP}" cidr_netmask="19" nic="eth0" clusterip_hash="sourceip" op monitor interval="10s"
#pcs resource create ClusterIP ocf:heartbeat:IPaddr2 ip="${VIRTUAL_IP}" cidr_netmask=19 op monitor interval=10s
#pcs resource clone ClusterIP meta clone-max=${#HOSTS[@]} clone-node-max=${#HOSTS[@]} globally-unique=true
curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs_cluster -XPUT -d value="True"
for node in "${HOSTS[@]}"; do
curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs_nodes/$node -XPUT -d value="in"
done
while true; do
sleep 30
for node in $(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs_nodes/ | jq -r ".node.nodes[] | select(.value == \"$(printf 'out')\") | .key"); do
IFS='/' read -ra RESULT <<< $node
OUT=${RESULT[-1]}
if [ "${OUT}" != "$(hostname)" ]; then
pcs cluster auth ${OUT} -u hacluster -p ${HACLUSTER} --force
pcs cluster node remove ${OUT}
pcs cluster node add --start ${OUT}
echo "Node ${OUT} back in cluster"
fi
done
done
else
while  [ $(curl -s http://${ETCD_HOST}:2379/v2/keys/mysql/pcs_cluster | jq -r '.node.value') == "null" ]; do
sleep 1;
done
fi

pcs cluster status
exec tail -f /var/log/pcsd/pcsd.log
