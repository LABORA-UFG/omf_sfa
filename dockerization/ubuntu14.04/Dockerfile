FROM ubuntu:14.04

ENV OMF_SFA_HOME=/root/omf_sfa
ENV DOMAIN=ufg.br
ENV AM_SERVER_DOMAIN=ufg.br
ENV XMPP_DOMAIN=ufg.br

RUN apt-get update
RUN apt-get install -y \
   build-essential \
   git \
   libsqlite3-dev \
   libreadline6-dev \
   libssl-dev \
   libxmlsec1-dev \
   libyaml-dev \
   xmlsec1 \
   wget \
   zlib1g-dev

RUN cd /tmp \
   && wget http://ftp.ruby-lang.org/pub/ruby/2.1/ruby-2.1.5.tar.gz \
   && tar -xvzf ruby-2.1.5.tar.gz \
   && cd ruby-2.1.5/ \
   && ./configure --prefix=/usr/local \
   && make \
   && make install \
   && rm -rf /tmp/ruby

RUN gem install bundler --no-ri --no-rdoc

WORKDIR /root

#BEGIN BROKER DOWNLOAD E INSTALATION
RUN git clone https://github.com/viniciusgb4/omf_sfa.git \
&& cd $OMF_SFA_HOME && bundle install
#END BROKER DOWNLOAD E INSTALATION

#BEGIN DATABASE CONFIGURATION
WORKDIR $OMF_SFA_HOME
RUN rake db:migrate
#END DATABASE CONFIGURATION

#BEGIN CERTIFICATES CONFIGURATION
RUN mkdir certs
WORKDIR $OMF_SFA_HOME/certs
RUN omf_cert.rb --email root@DOMAIN -o root.pem --duration 50000000 create_root \
&& omf_cert.rb -o am.pem  --geni_uri URI:urn:publicid:IDN+AM_SERVER_DOMAIN+user+am --email am@DOMAIN --resource-id xmpp://am_controller@XMPP_DOMAIN --resource-type am_controller --root root.pem --duration 50000000 create_resource \
&& omf_cert.rb -o user_cert.pem --geni_uri URI:urn:publicid:IDN+AM_SERVER_DOMAIN+user+root --email root@DOMAIN --user root --root root.pem --duration 50000000 create_user

RUN mkdir -p /root/.omf/trusted_roots && cp * /root/.omf/ && cp root.pem am.pem /root/.omf/trusted_roots/
RUN openssl rsa -in /root/.omf/am.pem -outform PEM -out /root/.omf/am.pkey \
&& openssl rsa -in /root/.omf/user_cert.pem -outform PEM -out /root/.omf/user_cert.pkey
#END CERTIFICATES CONFIGURATION

#BEGIN COPY CONFIGURATION FILE
COPY omf-sfa-am.yaml $OMF_SFA_HOME/etc/omf-sfa/
#END COPY CONFIGURATION FILE

#EXECUTE BROKER
WORKDIR $OMF_SFA_HOME
RUN cp init/omf-sfa.conf /etc/init/ && sed -i '/chdir \/root\/omf\/omf_sfa/c\chdir \/root\/omf_sfa' /etc/init/omf-sfa.conf

ENTRYPOINT ["bundle", "exec", "ruby", "-I", "lib", "lib/omf-sfa/am/am_server.rb", "start"]