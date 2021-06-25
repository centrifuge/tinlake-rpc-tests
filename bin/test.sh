#!/usr/bin/env bash
set -e

DIR=$(pwd)
ADDR_SOL="$DIR/$1"
export DAPP_TEST_TIMESTAMP=$(date +%s)
echo $ADDR_SOL

node src/js/createAddresses.js $ADDR_SOL

dapp --use solc:0.7.6 build --extract
hevm dapp-test --rpc="$ETH_RPC_URL" --json-file=out/dapp.sol.json --verbose=1
