FROM ubuntu:14.04

ENV GCF_HOME=/root/gcf

RUN apt-get update && \
    apt-get install -y \
    git \
    libxmlsec1 \
    libxmlsec1-dev \
    libxmlsec1-openssl \
    python-dateutil \
    python-m2crypto  \
    python-openssl \
    xmlsec1 \
    wget

WORKDIR /root

RUN mkdir -p $GCF_HOME \
    && git clone https://github.com/GENI-NSF/geni-tools.git gcf
#    && mv geni-tools $GCF_HOME \
#    && cd $GCF_HOME \
#    && rm gcf; ln -s gcf-2.10 gcf

COPY gcf_path.txt /root/

RUN cat /root/gcf_path.txt >> /root/.bashrc \
    && rm /root/gcf_path.txt

COPY .gcf/ /root/.gcf/

RUN /root/gcf/src/gen-certs.py

EXPOSE 8000/tcp

ENTRYPOINT ["/root/gcf/src/gcf-ch.py"]
