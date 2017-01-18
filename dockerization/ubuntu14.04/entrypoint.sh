#!/bin/bash

#sqlite3 is one of the gems installed for Broker. Here we check if it is already installed.
#We assume that if it is not installed it means that the Broker are not installed too.
if [ ! -f "$INVENTORY_PATH" ]; then
    echo "###############INSTALLATION OF THE MODULES###############"
    #Start of Broker installation
    cd $OMF_SFA_HOME
    echo "###############INSTALLING OMF_SFA###############"
    bundle install

    echo "###############RAKE DB:MIGRATE###############"
    rake db:migrate

    echo "###############CREATING DEFAULT SSH KEY###############"
    ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""

    ##START OF CERTIFICATES CONFIGURATION
    echo "###############CONFIGURING OMF_SFA CERTIFICATES###############"
    mkdir -p /root/.omf/trusted_roots
    omf_cert.rb --email root@$DOMAIN -o /root/.omf/trusted_roots/root.pem --duration 50000000 create_root
    omf_cert.rb -o /root/.omf/am.pem  --geni_uri URI:urn:publicid:IDN+$AM_SERVER_DOMAIN+user+am --email am@$DOMAIN --resource-id amqp://am_controller@$XMPP_DOMAIN --resource-type am_controller --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_resource
    omf_cert.rb -o /root/.omf/user_cert.pem --geni_uri URI:urn:publicid:IDN+$AM_SERVER_DOMAIN+user+root --email root@$DOMAIN --user root --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_user

    openssl rsa -in /root/.omf/am.pem -outform PEM -out /root/.omf/am.pkey
    openssl rsa -in /root/.omf/user_cert.pem -outform PEM -out /root/.omf/user_cert.pkey
    ##END OF CERTIFICATES CONFIGURATION

    echo "###############CONFIGURING OMF_SFA AS UPSTART SERVICE###############"
    cp init/omf-sfa.conf /etc/init/ && sed -i '/chdir \/root\/omf\/omf_sfa/c\chdir \/root\/omf_sfa' /etc/init/omf-sfa.conf
    #End of Broker installation
fi

#if ! gem list nitos_testbed_rc -i; then
#    #Start of NITOS Testbed RCs installation
#    echo "###############INSTALLING NITOS TESTBED RCS###############"
#    gem install nitos_testbed_rc
#    install_ntrc
#
#    ##START OF CERTIFICATES CONFIGURATION
#    echo "###############CONFIGURING NITOS TESTBED RCS CERTIFICATES###############"
#    omf_cert.rb -o /root/.omf/user_factory.pem --email user_factory@$DOMAIN --resource-type user_factory --resource-id amqp://user_factory@$XMPP_DOMAIN --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_resource
#    omf_cert.rb -o /root/.omf/cm_factory.pem --email cm_factory@$DOMAIN --resource-type cm_factory --resource-id amqp://cm_factory@$XMPP_DOMAIN --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_resource
#    omf_cert.rb -o /root/.omf/frisbee_factory.pem --email frisbee_factory@$DOMAIN --resource-type frisbee_factory --resource-id amqp://frisbee_factory@$XMPP_DOMAIN --root /root/.omf/trusted_roots/root.pem --duration 50000000 create_resource
#    cp -r /root/.omf/trusted_roots/ /etc/nitos_testbed_rc/
#    ##END OF CERTIFICATES CONFIGURATION
#    #End of NITOS Testbed RCs installation
#fi

if [ "$(ls -A /root/testbed-files)" ]; then

    ##START OF - COPING CONFIGURATION FILES
    echo "###############COPYING CONFIGURATION FILES TO THE RIGHT PLACE###############"
    cp -r /root/testbed-files/* /
    rm -rf /root/testbed-files
    ##END OF - COPING CONFIGURATION FILES

    #START OF PXE CONFIGURATION
    echo "###############PXE CONFIGURATION###############"
    ln -s /usr/lib/syslinux/pxelinux.0 /tftpboot/
    ln -s /tftpboot/pxelinux.cfg/pxeconfig /tftpboot/pxelinux.cfg/01-00:03:1d:0c:23:46
    ln -s /tftpboot/pxelinux.cfg/pxeconfig /tftpboot/pxelinux.cfg/01-00:03:1d:0c:47:48
    cp -rf /root/dnsmasq.conf >> /etc/dnsmasq.conf
    cat /root/hosts >> /etc/hosts
    #END OF PXE CONFIGURATION
fi

#echo "Starting dnsmasq"
#/etc/init.d/dnsmasq start

run_broker() {
    cd /root/omf_sfa
    bundle exec ruby -I lib /root/omf_sfa/lib/omf-sfa/am/am_server.rb start &> /var/log/omf-sfa.log &
}

debug_broker() {
    cd /root/omf_sfa
    bundle exec rdebug-ide --host 0.0.0.0 --port 1234 --dispatcher-port 26162 -- /usr/local/bin/bundle exec ruby -I lib lib/omf-sfa/am/am_server.rb start
}

echo "Executing omf_sfa"
export $(< $OMF_SFA_HOME/dockerization/ubuntu14.04/broker.env)
if [ "$DEBUG" == 1 ]; then
    debug_broker;
else
    run_broker;
fi


#echo "Executing NITOS Testbed RCs"

#user_proxy &> /var/log/ntrc/user_proxy.log &
#frisbee_proxy &> /var/log/ntrc/frisbee_proxy.log &
#cm_proxy &> /var/log/ntrc/cm_proxy.log &

#start ntrc

#sleep 10s

#/root/omf_sfa/bin/create_resource -t node -c /root/omf_sfa/bin/conf.yaml -i /root/resources.json

#export TERM=xterm

tail -f /var/log/omf-sfa.log