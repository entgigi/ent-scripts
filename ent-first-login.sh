#!/bin/bash

function usage() {
    echo "The parameters list:"
    echo "  --proto <proto>          : Default <http://>                       ; Use proto for all tests"
    echo "  --host <hostname>        : Default <ent.10.131.132.235.nip.io> ; Use hostname to connect to enatndo"
    echo "  --help                   : print this help"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    "--proto") PROTO_OVERRIDE="$2";shift;;
    "--host") HOST_OVERRIDE="$2";shift;;
    "--help") usage; exit 3;;
    "--"*) echo "Undefined argument \"$1\"" 1>&2; usage; exit 3;;
  esac
  shift
done

PROTO="${PROTO_OVERRIDE:-http://}"
HOST="${HOST_OVERRIDE:-ent.10.131.132.235.nip.io}"

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "> PROTO:        $PROTO"
echo "> HOST:         $HOST"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"


ENT_HOST=${HOST} ENT_PROTO=${PROTO} taiko /home/gigiozzz/Dev/ent-first-login-change-password.js 
