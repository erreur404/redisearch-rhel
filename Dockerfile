FROM registry.access.redhat.com/ubi8/ubi:8.8 as build-redis
SHELL ["/bin/bash", "-c"]

# Check arguments before running the build
ARG REDIS_VERSION
RUN if [ -z "$REDIS_VERSION" ]; then echo 'Environment variable REDIS_VERSION must be specified with --build-arg REDIS_VERSION=7.x.y'; exit 1; fi

# prepare RHEL image for building redis and redissearch
RUN yum -y update \ 
    # install build dependencies and dev tools
    && yum -y install wget make gcc openssl-devel which

# ==================================================
# ||   now actually building redis                ||
# ==================================================

# set output directory
WORKDIR /workspace
RUN mkdir dist


# build redis
RUN wget -q https://github.com/redis/redis/archive/${REDIS_VERSION}.tar.gz -O sources.tgz \
        && tar -zxf sources.tgz \
        && rm sources.tgz
WORKDIR /workspace/redis-$REDIS_VERSION
RUN make BUILD_TLS=yes MALLOC=libc
RUN cp src/redis-* ../dist \
        && rm -f ../dist/*.h ../dist/*.c ../dist/*.o ../dist/*.d \
        && ls -ltr ../dist



##FROM registry.access.redhat.com/ubi8/ubi:8.8 as build # no epel
##FROM fedora:28 as build # no epel
FROM quay.io/centos/centos:stream8 as build-redissearch
SHELL ["/bin/bash", "-c"]


RUN yum -y update \
    && yum -y install yum-utils python3-pip \
    # add Oracle Linux repo (brother of CentOS and RHEL)
    && yum-config-manager --add-repo http://yum.oracle.com/repo/OracleLinux/OL9/distro/builder/x86_64 \
    && yum -y update
    
RUN pip3 install dataclasses
    
RUN yum -y install wget make git openssl-devel
RUN yum -y --allowerasing install curl
RUN yum -y --nogpgcheck install redhat-lsb-core


# ==================================================
# ||   now actually building redisearch           ||
# ==================================================

# build redissearch
WORKDIR /workspace

ARG REDIS_VERSION
# v2.0.15, v2.2.11, v2.4.16, v2.6.13, v2.8.5, v2.10.0
ARG REDIS_SEARCH_VERSION
RUN if [ -z "$REDIS_SEARCH_VERSION" ]; then \
        echo 'Environment variable REDIS_SEARCH_VERSION not set (--build-arg REDIS_SEARCH_VERSION=v2.x.y). Building latest version.'; \
        git clone --recursive https://github.com/RediSearch/RediSearch.git; \
    else \
        echo "cloning RediSearch ${REDIS_SEARCH_VERSION}"; \
        git clone --recursive https://github.com/RediSearch/RediSearch.git --branch $REDIS_SEARCH_VERSION; \
    fi

WORKDIR /workspace/RediSearch

# add the future destinations to the path so that the python that will be installed gets picked up in the rest of the build
ENV PATH /root/.pyenv/shims:/root/.pyenv/bin:/usr/share/Modules/bin:/opt/rh/gcc-toolset-11/root/usr/bin:/root/.local/bin:$PATH
# inspired from how the docker build in ./build/docker works
# test redisearch multithread
ENV REDISEARCH_MT_BUILD=1

RUN ./deps/readies/bin/getbash
RUN ./deps/readies/bin/getpy3
RUN ./deps/readies/bin/getupdates
RUN ./sbin/setup
RUN /workspace/RediSearch/deps/readies/bin/getredis -v ${REDIS_VERSION}

RUN make conan SHOW=1
RUN make setup 
RUN make fetch
RUN make build COORD=oss STATIC_LIBSTDCXX=0 GCC=1 CLANG=0 LITE=0 DEBUG=0 TESTS=0 VG=0 SLOW=0


##Assert this will run
FROM registry.access.redhat.com/ubi8/ubi:8.8 as test
WORKDIR /redis


ENV REDIS_PASS masterpass
RUN echo "cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2" > os-pretty.sh; chmod +x os-pretty.sh
RUN yum -y update && yum -y install openssl

COPY cluster/common-redis-conf.conf.template cluster/common-redis-conf.conf.template
COPY cluster/makeRedisCerts.sh cluster/makeRedisCerts.sh
WORKDIR /redis/cluster
RUN version=$(grep "VERSION_ID=" /etc/os-release | cut -d"=" -f2 | sed -e 's/"//g') \
   && mkdir tools-$version \
   && ln -sfn tools-$version tools
COPY --from=build-redis /workspace/dist/* ./tools/
#COPY --from=build-redissearch /workspace/RediSearch/bin/linux-x64-release/search/redisearch.so ./tools
COPY --from=build-redissearch /workspace/RediSearch/bin/linux-x64-release/coord-oss/module-oss.so ./tools

RUN cd tools && ls -ltr
RUN echo $(./tools/redis-server --version) running on $(../os-pretty.sh)
RUN echo $(./tools/redis-cli --version) running on $(../os-pretty.sh)

RUN mkdir -p tls/trusted-sources && ./makeRedisCerts.sh
COPY cluster/create-folder.sh create-folder.sh
RUN ./create-folder.sh 6500

COPY cluster/test-redisearch.sh test-redisearch.sh
CMD [ "./test-redisearch.sh" ]