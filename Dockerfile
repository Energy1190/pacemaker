FROM debian

ADD start.sh /start.sh

RUN apt-get update -y \
    && apt-get install -y \
	   pcs \
	   pacemaker \
	   corosync \
	   iptables \
	   curl \
	   jq

RUN chmod +x /start.sh
RUN curl --create-dirs -o /usr/lib/ocf/resource.d/percona/IPaddr3 https://raw.githubusercontent.com/percona/percona-pacemaker-agents/master/agents/IPaddr3 \
    && chmod u+x /usr/lib/ocf/resource.d/percona/IPaddr3
    
ENTRYPOINT ["/start.sh"]
