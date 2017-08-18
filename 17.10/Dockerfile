FROM       ubuntu:17.10
MAINTAINER leenchan

ADD docker.sh /tmp/docker.sh
RUN chmod +x /tmp/docker.sh && /tmp/docker.sh && rm -f /tmp/docker.sh

ADD run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 22 80 443 5901 8443

CMD ["/run.sh"]
