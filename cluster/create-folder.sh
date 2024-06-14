#!/bin/bash

port_start=$1
port_end=$(($port_start + 5))

for port in $(seq $port_start $port_end); do
  mkdir $port
  echo "include ../common-redis-conf.conf" > $port/redis.conf
  echo "tls-port $port" >> $port/redis.conf
done;

cat > start.sh <<- EOF
#!/bin/bash

here=$(pwd)
if [[ \$here != "/appl/neutrino/neutrinong"* ]]; then
  echo "WARNING : Running redis outside of /appl/neutrino/neutrinong is strongly discoureaged for production"
fi

echo "looking for the RHEL version to link the correct binaries"
version=$(grep "VERSION_ID=" /etc/os-release | cut -d"=" -f2 | sed -e 's/"//g')

echo "found RHEL version \$version"

if [ -d tools-\$version ]; then
  echo "linking to the redis binaries compiled for RHEL \$version"
  ln -sfn tools-\$version tools

  echo "starting nodes"
  for i in \$(seq $port_start $port_end);
  do
    echo "starting redis at port \$i"
    (cd \$i && ../tools/redis-server redis.conf > ../server-\$i.log &)
  done
else
  echo "no binaries found for your RHEL version (\$version)"
  echo "available versions :"
  echo "$(ls | grep 'tools-' | cut -d'-' -f2)"
fi
EOF
chmod +x start.sh

cat > force-stop.sh <<- EOF
#!/bin/bash

for i in \$(seq $port_start $port_end);
do
    echo stopping redis at port \$i
    ./redis-cli.sh -p \$i shutdown &
done
EOF
chmod +x force-stop.sh

cat > redis-cli.sh <<- EOF
#!/bin/bash

./tools/redis-cli -a $REDIS_PASS -c -p $port_start --no-auth-warning --tls \
    --cert ./tls/redis.crt \
    --key ./tls/redis.key \
    --cacert ./tls/trusted-sources/ca.crt \$*
    #--cacertdir ./tls/trusted-sources \$*
EOF
chmod +x redis-cli.sh

[[ ! -d tls/trusted-sources ]] && mkdir -p tls/trusted-sources && ./makeRedisCerts.sh

cat common-redis-conf.conf.template | sed -e "s/\$REDIS_PASS/$REDIS_PASS/gm" > common-redis-conf.conf

echo "starting the nodes"
./start.sh
sleep 5

ip="127.0.0.1"
echo "creating the cluster"
./redis-cli.sh --cluster create \
      $ip:$(($port_start + 0)) \
      $ip:$(($port_start + 1)) \
      $ip:$(($port_start + 2)) \
      $ip:$(($port_start + 3)) \
      $ip:$(($port_start + 4)) \
      $ip:$(($port_start + 5)) \
      --cluster-replicas 1 \
      --cluster-yes

sleep 5
./redis-cli.sh cluster info | grep cluster_state
if [ ! $(./redis-cli.sh cluster info | grep -c "cluster_state:ok") -eq 1 ]; then
  exit 1
fi
./redis-cli.sh cluster nodes

./force-stop.sh
sleep 5
for port in $(seq $port_start $port_end); do
  echo "================================================================== node $port"
  cat server-$port.log
done;
