#! /bin/bash

REDIS_CERT_FOLDER=tls
REDIS_KEY=$REDIS_CERT_FOLDER/redis.key
REDIS_CRT=$REDIS_CERT_FOLDER/redis.crt
REDIS_DH=$REDIS_CERT_FOLDER/redis.dh
REDIS_CA_KEY=$REDIS_CERT_FOLDER/trusted-sources/ca.key
REDIS_CA_CRT=$REDIS_CERT_FOLDER/trusted-sources/ca.crt


echo delete $REDIS_KEY and $REDIS_CRT to generate these again.
echo you can check the certificate expiration date with ./checkCertificateExpiration.sh $REDIS_CRT

[[ ! -f $REDIS_CA_KEY ]] && echo generate CA private key && openssl genrsa -out $REDIS_CA_KEY 4096
[[ ! -f $REDIS_CA_CRT ]] && echo generate CA certificate && openssl req \
    -x509 -new -nodes -sha256 \
    -key $REDIS_CA_KEY \
    -days 3650 \
    -subj '/O=Redis Test/CN=Certificate Authority' \
    -out $REDIS_CA_CRT

[[ ! -f $REDIS_KEY ]] && echo generate redis client private key && openssl genrsa -out $REDIS_KEY 2048
[[ ! -f $REDIS_CRT ]] && echo generate redis client private certificate && openssl req \
    -new -sha256 \
    -subj "/O=Redis Test/CN=redis" \
    -key $REDIS_KEY | \
    openssl x509 \
        -req -sha256 \
        -CA $REDIS_CA_CRT \
        -CAkey $REDIS_CA_KEY \
        -CAcreateserial \
        -days 730 \
        -out $REDIS_CRT

[[ ! -f $REDIS_DH ]] && echo "generating DH parameters for the redis cluster" && openssl dhparam -out $REDIS_DH 2048
