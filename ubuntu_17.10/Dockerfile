FROM       ubuntu:17.10
MAINTAINER leenchan

RUN sh <(curl https://github.com/leenchan/vps/raw/master/vps.sh) docker

ADD run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 22 80 443 5901 8443

CMD ["/run.sh"]
