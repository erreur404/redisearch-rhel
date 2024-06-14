#!/bin/bash

echo "testing redis and search functionnality (briefly)"
./start.sh && sleep 4
# if cluster nok or nodes disconnected, print start log and fail fast
if [ $(./redis-cli.sh cluster nodes | grep -c disconnected) -gt 0 ]; then
  port_start=6500
  port_end=$(($port_start + 5))
  for port in $(seq $port_start $port_end); do
    echo "================================================================== node $port"
    cat server-$port.log
  done;
  exit 1
fi

echo "inserting elements into hashes"
./redis-cli.sh hmset conversion:0 created 0 method "pdfToText"
./redis-cli.sh hmset conversion:1 created 1 method "wordToText"

echo "check the content of conversion:0"
./redis-cli.sh hgetall conversion:0

echo ""
echo "create the conversion index"
./redis-cli.sh FT.CREATE conv-idx \
    ON HASH PREFIX 1 conversion: \
    SCHEMA \
        created NUMERIC SORTABLE \
        method TAG

echo "TEST: searching the index by method"
res=$(echo $(./redis-cli.sh FT.SEARCH conv-idx "@method:{pdfToText}" NOCONTENT) | cut -d' ' -f1)
if [ ! 1 -eq $res ]; then
  echo "expected 1 conversion to have method pdfToText. (got $res)"
  exit 1
fi
echo "OK"

echo "TEST: adding and changing objects updates the indices"
./redis-cli.sh hmset conversion:2 created 2 method "wordToText"
./redis-cli.sh hset conversion:0 method "wordToText"

echo "TEST: search the indices again by method"
res=$(echo $(./redis-cli.sh FT.SEARCH conv-idx "@method:{wordToText}" NOCONTENT) | cut -d' ' -f1)
if [ ! 3 -eq $res ]; then
  echo "expected 3 conversion to have method wordToText. (got $res)"
  exit 1
fi
echo "OK"

#echo "TEST: search by created date (from, to(excluded))"
#./redis-cli.sh FT.SEARCH conv-idx "@created:[0 (2]" NOCONTENT
#res=$(echo $(./redis-cli.sh ./redis-cli.sh FT.SEARCH conv-idx "@created:[0 (2]" NOCONTENT) | cut -d' ' -f1)
#if [ ! 3 -eq $res ]; then
#  echo "expected 3 conversion to have method wordToText. (got $res)"
#  exit 1
#fi
#echo "OK"
