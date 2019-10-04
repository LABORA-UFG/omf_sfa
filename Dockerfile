FROM ubuntu:16.04

ARG DEBIAN_FRONTEND=noninteractive

#install_dependencies
RUN apt-get update \
    && apt-get install -y \
    curl \
    dnsmasq \
    git \
    libsqlite3-dev \
    libreadline6-dev \
    libyaml-dev \
    libxmlsec1-dev \
    ntp \
    python \
    syslinux \
    xmlsec1 \
    wget \
    zlib1g-dev \
    virtinst

#install_omf_dependencies
RUN apt-get update \
    && apt-get install -y \
    build-essential \
    libssl-dev

#install ruby dependencies
RUN apt-get update \
    && apt-get install -y \
    gcc \
    make \
    libc6-dev \
    libreadline6-dev \
    zlib1g-dev \
    libssl-dev \
    libyaml-dev \
    libsqlite3-dev \
    sqlite3 \
    autoconf \
    libgmp-dev \
    libgdbm-dev \
    libncurses5-dev \
    automake \
    libtool \
    bison \
    pkg-config \
    libffi-dev \
    wget

#postgres client dependency
RUN apt-get update \
    && apt-get install -y libpq-dev postgresql-client


ARG RUBY_VERSION_BASE=2.3
ARG RUBY_VERSION=2.3.2

#install ruby
RUN cd /tmp \
    && wget http://ftp.ruby-lang.org/pub/ruby/$RUBY_VERSION_BASE/ruby-$RUBY_VERSION.tar.gz \
    && tar -xvzf ruby-$RUBY_VERSION.tar.gz \
    && cd ruby-$RUBY_VERSION/ \
    && ./configure --prefix=/usr/local \
    && make \
    && make install \
    && rm -rf /tmp/ruby \
    && gem install bundler --no-ri --no-rdoc


RUN bundle config --global frozen 1

WORKDIR /root

RUN git clone -b amqp https://git.rnp.br/fibre/omf.git

#install_omf_common_gem
RUN cd /root/omf/omf_common && \
    gem build omf_common.gemspec && \
    gem install omf_common-*.gem   

# #install_omf_rc_gem
RUN cd /root/omf/omf_rc && \
   gem build omf_rc.gemspec && \
   gem install omf_rc-*.gem

# # install omf_sfa
RUN git clone -b amqp https://git.rnp.br/fibre/omf_sfa.git

#ARG BROKER_VERSION=f3391c25c907122b0893305f0ad570a50bff4833
#RUN git -C ./omf_sfa checkout $BROKER_VERSION

# hack because of Gemfile.lock missing
ADD ./Gemfile.lock /root/omf_sfa/Gemfile.lock

RUN cd ./omf_sfa && bundle install

###############CREATING DEFAULT SSH KEY###############
RUN ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""

ARG DOMAIN=localhost
ARG AM_SERVER_DOMAIN=localhost
ARG XMPP_DOMAIN=localhost

#create_broker_cerficates
RUN mkdir -p /root/.omf/trusted_roots && \
    omf_cert.rb --email root@$DOMAIN -o /root/.omf/trusted_roots/root.pem --duration 50000000 create_root && \
    omf_cert.rb -o /root/.omf/am.pem  --geni_uri URI:urn:publicid:IDN+$AM_SERVER_DOMAIN+user+am --email am@$DOMAIN --resource-id amqp://am_controller@$XMPP_DOMAIN --resource-type am_controller --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_resource && \
    omf_cert.rb -o /root/.omf/user_cert.pem --geni_uri URI:urn:publicid:IDN+$AM_SERVER_DOMAIN+user+root --email root@$DOMAIN --user root --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_user && \
    openssl rsa -in /root/.omf/am.pem -outform PEM -out /root/.omf/am.pkey && \
    openssl rsa -in /root/.omf/user_cert.pem -outform PEM -out /root/.omf/user_cert.pkey