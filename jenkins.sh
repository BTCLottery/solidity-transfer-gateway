#!/bin/bash

# If the ETHEREUM_NETWORK env var isn't set this script spin up a DAppChain node & Ganache to run
# the e2e tests on. Otherwise it will run the tests against the Ethereum and DAppChain networks
# specified by the ETHEREUM_NETWORK and DAPPCHAIN_NETWORK env vars.
#
# Currently supported values for ETHEREUM_NETWORK (case-sensitive, if set):
# - rinkeby
#
# Currently supported values for DAPPCHAIN_NETWORK (case-sensitive, if set):
# - pc_testnet (PlasmaChain Testnet)
#
# The following env vars may also be set to tweak the script flow:
# TEST_TO_RUN - Can be used to specify a single test to run.

set -exo pipefail

REPO_ROOT=`pwd`
pkill -f loom || true
pkill -f loom-gateway || true
pkill -f binance_tgoracle || true

rm -rf loom loom-gateway binance_tgoracle tgoracle loomcoin_tgoracle

# Loom build to use for tests
export BUILD_ID=build-1311
# Binance Oracle build to use for tests
BINANCE_ORACLE_BUILD_ID=build-33

# Check available platforms
PLATFORM='unknown'
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
  PLATFORM='linux'
elif [[ "$unamestr" == 'Darwin' ]]; then
  PLATFORM='osx'
else
  echo "Platform not supported on this script yet"
  exit -1
fi

# If loom custom build is used, change this URL to https://private.delegatecall.com/loom/${PLATFORM}/${BUILD_ID}
export DOWNLOAD_LOOM_URL=https://downloads.loomx.io/loom/${PLATFORM}/${BUILD_ID}
DOWNLOAD_BINANCE_URL=https://downloads.loomx.io/binance_tgoracle/${PLATFORM}/${BINANCE_ORACLE_BUILD_ID}

wget ${DOWNLOAD_LOOM_URL}/loom-gateway
chmod +x loom-gateway
mv loom-gateway loom
export LOOM_BIN=`pwd`/loom
CFG=$REPO_ROOT/e2e_config/local_ganache/loom.cluster.yml

wget ${DOWNLOAD_LOOM_URL}/loomcoin_tgoracle
chmod +x loomcoin_tgoracle
wget ${DOWNLOAD_LOOM_URL}/tgoracle
chmod +x tgoracle

# Setting up solidity code analyzer
source /var/lib/jenkins/python-virtualenvs/transfer-gateway-v2/bin/activate
pip install slither-analyzer


if [[ -z "$ETHEREUM_NETWORK" ]]; then
    cd $REPO_ROOT/mainnet
    yarn install
    yarn lint
    yarn compile
    yarn test
    slither . --filter-path openzeppelin-solidity,contracts/mocks || echo "slither analyzed on mainnet contracts"

    cd $REPO_ROOT/dappchain
    yarn install
    CFG=$CFG yarn compile
    CFG=$CFG slither . --filter-path openzeppelin-solidity || echo "slither analyzed on dappchain contracts"
fi

cd $REPO_ROOT
export GOPATH=/tmp/gopath-$BUILD_TAG
mkdir -p $GOPATH/bin
export PATH=$PATH:$GOPATH/bin

make clean
make deps
make vendor-deps
make deployer

if [[ -z "$ETHEREUM_NETWORK" ]]; then
    pkill -f ganache || true
    REPO_ROOT=`pwd` \
    bash loom_e2e_tests.sh --download-loom --nodes 4 --skip-tests

    # run the tests on a single node
    REPO_ROOT=`pwd` \
    LOOM_BIN=$REPO_ROOT/loom \
    LOOMCOIN_TGORACLE=$REPO_ROOT/loomcoin_tgoracle \
    LOOM_ORACLE=$REPO_ROOT/tgoracle \
    bash loom_e2e_tests.sh --init \
                           --launch-dappchain --launch-ganache  --launch-oracle \
                           --deploy-dappchain-contracts --deploy-ethereum-contracts \
                           --map-contracts --update-hot-wallet-address

    # # run the tests on a single node with yubihsm (disabled until we setup new remote signer)
    # pkill -f ganache || true
    # REPO_ROOT=`pwd` \
    # LOOM_BIN=$REPO_ROOT/loom \
    # bash loom_e2e_tests.sh --init \
    #                       --launch-dappchain --launch-ganache \
    #                       --deploy-dappchain-contracts --deploy-ethereum-contracts \
    #                       --map-contracts \
    #                       --run-test ERC721DepositAndWithdraw \
    #                       --enable-hsm --hsmkey-address 0x2669Ff29f3D3e78DAFd2dB842Cb9d0dDb96D90f2
    
    # run the tests again on a 4-node cluster...
    pkill -f ganache || true
    REPO_ROOT=`pwd` \
    LOOM_BIN=$REPO_ROOT/loom \
    LOOMCOIN_TGORACLE=$REPO_ROOT/loomcoin_tgoracle \
    LOOM_ORACLE=$REPO_ROOT/tgoracle \
    LOOM_VALIDATORS_TOOL=$REPO_ROOT/validators-tool \
    bash loom_e2e_tests.sh --init \
                           --launch-dappchain --launch-ganache --launch-oracle \
                           --deploy-dappchain-contracts --deploy-ethereum-contracts \
                           --map-contracts --update-hot-wallet-address \
                           --nodes 4

    # # run the tests again on a 4-node cluster with yubihsm
    # pkill -f ganache || true
    # REPO_ROOT=`pwd` \
    # LOOM_BIN=$REPO_ROOT/loom \
    # LOOMCOIN_TGORACLE=$REPO_ROOT/loomcoin_tgoracle \
    # LOOM_ORACLE=$REPO_ROOT/tgoracle \
    # LOOM_VALIDATORS_TOOL=$REPO_ROOT/validators-tool \
    # bash loom_e2e_tests.sh --init \
    #                       --launch-dappchain --launch-ganache --launch-oracle \
    #                       --deploy-dappchain-contracts --deploy-ethereum-contracts \
    #                       --map-contracts \
    #                       --nodes 4 \
    #                       --run-test ERC721DepositAndWithdraw \
    #                       --enable-hsm --hsmkey-address 0x2669Ff29f3D3e78DAFd2dB842Cb9d0dDb96D90f2
else
    REPO_ROOT=`pwd` \
    bash loom_e2e_tests.sh --dappchain-network "$DAPPCHAIN_NETWORK" \
                           --ethereum-network "$ETHEREUM_NETWORK" \
                           --run-test "$TEST_TO_RUN"

    REPO_ROOT=`pwd` \
    bash loom_e2e_tests.sh --dappchain-network "$DAPPCHAIN_NETWORK" \
                          --ethereum-network "$ETHEREUM_NETWORK" \
                          --run-test "$TEST_TO_RUN" \
                          --enable-hsm --hsmkey-address 0x2669Ff29f3D3e78DAFd2dB842Cb9d0dDb96D90f2
fi

# cd tron

# make deps

# cd ../

## Tron gateway get wiped, and for some reasons we can't deploy a new gateway at the moment. So, we disable the end to end test script
# ## Run Tron test on Shasta
# REPO_ROOT=`pwd` \
# bash loom_e2e_tests.sh --init \
#     --gateway-type tron-gateway \
#     --tron-network shasta \
#     --launch-dappchain \
#     --deploy-dappchain-contracts \
#     --map-contracts

# Run Binance Gateway e2e test
cd $REPO_ROOT
wget ${DOWNLOAD_BINANCE_URL}/binance_tgoracle
chmod +x binance_tgoracle

LOOM_ORACLE=$REPO_ROOT/binance_tgoracle \
REPO_ROOT=`pwd` \
bash loom_e2e_tests.sh --init \
    --gateway-type binance-gateway \
    --binance-network bnbtestnet \
    --launch-dappchain \
    --launch-oracle \
    --map-contracts \
    --deploy-dappchain-contracts \
    --run-test ALL \
    --reset-latest-block-num \
    --set-transfer-fee

