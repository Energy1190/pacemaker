FROM debian

ADD start.sh /start.sh

RUN apt-get update -y \
    && apt-get install -y \
	   pcs \
	   pacemaker \
	   corosync \
	   curl \
	   jq \

RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
CMD ["tail"]
