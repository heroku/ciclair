#!/usr/bin/env bash

if [ $# != 1 ]; then
    echo "usage: $(basename "$0") <docker image>" >&2
    exit 1
fi

CLAIR_DB_IMAGE=arminc/clair-db:latest
CLAIR_IMAGE=arminc/clair-local-scan:v2.0.5
CLAIR_DB=db-$(openssl rand -hex 8)
CLAIR=clair-$(openssl rand -hex 8)

DOCKER_IMAGE=${1:-}

if ! docker run --name $CLAIR_DB -d "$CLAIR_DB_IMAGE" > /dev/null; then
    echo "error starting clair-db '$CLAIR_DB_IMAGE'" >&2
    exit 1
fi

while true
do
    if docker logs "$CLAIR_DB" |& grep "database system is ready to accept connections" > /dev/null; then
        break
    fi
    echo -n "."
    sleep 1
done

if ! docker run -p 6060:6060 --link $CLAIR_DB:postgres -d --name $CLAIR --restart on-failure "$CLAIR_IMAGE" > /dev/null; then
    echo "error starting clair '$CLAIR_IMAGE'" >&2
    exit 1
fi

# get scanner binary
curl -o clair-scanner -sL https://github.com/cji/clair-scanner/releases/download/v8.1/clair-scanner_linux_amd64
chmod +x clair-scanner

# get our whitelist
curl -o safevulns.yaml -sL https://raw.githubusercontent.com/heroku/ciclair/master/safevulns.yaml

HOST_IP=$(docker inspect --format '{{ .NetworkSettings.Gateway }}' $CLAIR)
./clair-scanner --threshold="High" --reportAll=false -w safevulns.yaml --ip $HOST_IP $DOCKER_IMAGE

EXIT_CODE=$?

docker kill "$CLAIR_DB"
docker rm "$CLAIR_DB"

docker kill "$CLAIR"
docker rm "$CLAIR"

exit "$EXIT_CODE"