FROM ubuntu:14.04

ENV DOMAIN=ufg.br
ENV AM_SERVER_DOMAIN=ufg.br
ENV XMPP_DOMAIN=ufg.br

#RUN echo 'deb http://pkg.mytestbed.net/ubuntu precise/ ' >> /etc/apt/sources.list \
RUN apt-get update
RUN apt-get install -y --force-yes \
   build-essential \
   dnsmasq \
   git \
   libsqlite3-dev \
   libreadline6-dev \
   libssl-dev \
   libyaml-dev \
   libxml2-dev \
   libxmlsec1-dev \
   libxslt-dev \
   nano \
   ntp \
   syslinux \
   xmlsec1 \
   wget \
   zlib1g-dev

RUN mkdir -p /root/omf6-testbed
RUN git clone -b amqp https://github.com/LABORA-UFG/omf6-testbed.git /root/omf6-testbed
RUN bash -c '/root/omf6-testbed/installer.sh <<< $"15"'

EXPOSE 8001/tcp

#COPY AND SET THE ENTRYPOINT
COPY entrypoint.sh /usr/bin/
RUN chmod 755 /usr/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/entrypoint.sh"]