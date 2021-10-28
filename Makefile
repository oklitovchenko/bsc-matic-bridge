TESTS = \
	t01

.PHONY: all build setup stop-geth clean $(TESTS)

export HOME = $(shell pwd)
export ETHESTER_CONTRACT_PATH = build/
export ETHESTER_LOGLEVEL = info
export BSC = ETHESTER_GETH_IPC=/tmp/bsc.ipc ethester
export POLYGON = ETHESTER_GETH_IPC=/tmp/polygon.ipc ethester

all: build

build: clean
	mkdir -p build
	solc -o build --optimize --bin --abi contracts/*.sol

test:
	$(MAKE) -j1 $(TESTS)
	@($(MAKE) stop-geth)
	@echo "\n*** DONE ***\n"

t01: setup
	$(MAKE) deploy-contracts
	@echo "\n*** START TEST $@ ***\n"
	@echo "\n** Mint NFT Tokens **\n"
# In BSC all tokens on NFT contract owner address
# In Polygon all tokens on Bridge contract address
	i=0; while [ $$i -lt 10 ]; do \
        $(BSC) tran @run/nft-owner.addr @run/bsc-simpleNFT.addr \
            SimpleNFT.mint @run/nft-owner.addr || exit 1;  \
        $(POLYGON) tran @run/nft-owner.addr @run/polygon-simpleNFT.addr \
            SimpleNFT.mint @run/bridge.addr || exit 1;  \
        i=$$((i + 1)); \
    done
	@echo "\n** Transfer NFT Tokens to new owner **\n"
# Add and topup account for new owner
	$(BSC) new-account -s > run/nft-nowner1-bsc.addr
	$(BSC) send @run/coinbase.addr @run/nft-nowner1-bsc.addr 10ether
# Transfer two NFT Tokens to new owner in BSC
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 4 \
        -e @run/nft-owner.addr
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 6 \
        -e @run/nft-owner.addr
	$(BSC) tran @run/nft-owner.addr @run/bsc-simpleNFT.addr \
        SimpleNFT.safeTransferFrom @run/nft-owner.addr @run/nft-nowner1-bsc.addr 4
	$(BSC) tran @run/nft-owner.addr @run/bsc-simpleNFT.addr \
        SimpleNFT.safeTransferFrom @run/nft-owner.addr @run/nft-nowner1-bsc.addr 6
# Check if run/nft-nowner1-bsc.addr is current owner of token
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 3 -e @run/nft-owner.addr
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 4 -e @run/nft-nowner1-bsc.addr
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 6 -e @run/nft-nowner1-bsc.addr
	@echo "\n** Test init swap routine **\n"
# Add an account for new NFT owner in Polygon
	$(POLYGON) new-account -s > run/nft-nowner2-polygon.addr
# Try init swap transaction. Revert if tokens not approved for bridge
	$(BSC) tran @run/nft-nowner1-bsc.addr @run/bridge.addr \
        Bridge.initSwap @run/nft-nowner1-bsc.addr @run/nft-nowner2-polygon.addr \
        6 2121 --expect-revert
# Make approve for bridge on token id 6
	$(BSC) tran @run/nft-nowner1-bsc.addr @run/bsc-simpleNFT.addr \
        SimpleNFT.approve @run/bridge.addr 6
# Init swap from BSC to Polygon
	$(BSC) tran @run/nft-nowner1-bsc.addr @run/bridge.addr \
        Bridge.initSwap @run/nft-nowner1-bsc.addr @run/nft-nowner2-polygon.addr \
        6 2121
# Check reverted as duplicate int swap transaction
	$(BSC) tran @run/nft-nowner1-bsc.addr @run/bridge.addr \
        Bridge.initSwap @run/nft-nowner1-bsc.addr @run/nft-nowner2-polygon.addr \
        6 2121 --expect-revert
	@echo "\n** Test init swap events **\n"
# Expect one Swap event in BSC
	$(BSC) events 0 latest @run/bridge.addr \
        --event Bridge.Swap --quiet --expect 1
# Extract nonce for making swap transaction validation in Polygon
	$(BSC) events 0 latest @run/bridge.addr \
        --event Bridge.Swap --field 0.topics.1 > run/nonce
	@echo "\n** Sign swap nonce to be prepared for validate swap tx **\n"
	$(BSC) exec "web3.personal.unlockAccount(\"`cat run/validator.addr`\",\"\", 8000)"
	$(BSC) exec "eth.sign(\"`cat run/validator.addr`\", `cat run/nonce`)" > run/sig
# Finish swap from BSC to Polygon
	@echo "\n** Finish swap **\n"
	$(POLYGON) tran @run/coinbase.addr @run/bridge.addr \
        Bridge.redeemSwap @run/nft-nowner1-bsc.addr @run/nft-nowner2-polygon.addr \
        6 1212 @run/nonce @run/sig
	@echo "\n** Check ownership transferred from BSC to Polygon  **\n"
# Check if run/nft-nowner2-polygon.addr is new token owner in Polygon
	$(POLYGON) call @run/polygon-simpleNFT.addr SimpleNFT.ownerOf \
        6 -e @run/nft-nowner2-polygon.addr
	@echo "\n** Check if token locked in source network on bridge contract  **\n"
# Check if bridge transferred ownership from itself to new owner correctly
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 6 -e @run/bridge.addr
	@echo "\n** Check if we can send token back  **\n"
# Check if we can send token back
	$(POLYGON) send @run/coinbase.addr @run/nft-nowner2-polygon.addr 10ether
	$(POLYGON) tran @run/nft-nowner2-polygon.addr @run/polygon-simpleNFT.addr \
        SimpleNFT.approve @run/bridge.addr 6
	$(POLYGON) tran @run/nft-nowner2-polygon.addr @run/bridge.addr \
        Bridge.initSwap @run/nft-nowner2-polygon.addr @run/nft-owner.addr 6 1212
	$(POLYGON) events 0 latest @run/bridge.addr \
        --event Bridge.Swap --field 0.topics.1 > run/nonce
	$(BSC) exec "web3.personal.unlockAccount(\"`cat run/validator.addr`\",\"\", 8000)"
	$(BSC) exec "eth.sign(\"`cat run/validator.addr`\", `cat run/nonce`)" > run/sig
	$(BSC) tran @run/nft-owner.addr @run/bridge.addr \
        Bridge.redeemSwap @run/nft-nowner2-polygon.addr @run/nft-owner.addr \
        6 2121 @run/nonce @run/sig
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 6 -e @run/nft-owner.addr
	$(POLYGON) call @run/polygon-simpleNFT.addr SimpleNFT.ownerOf 6 -e @run/bridge.addr
	@echo "\n** Check revert if somebody try swap not own token  **\n"
# Check revert if somebody try swap not own token
	$(POLYGON) tran @run/nft-nowner2-polygon.addr @run/bridge.addr \
        Bridge.initSwap @run/nft-nowner2-polygon.addr @run/nft-owner.addr \
        2 1212 --expect-revert
	@echo "\n** Check swap init through direct sending token on bridge **\n"
# Check swap init thtouth dirct sending token on bridge
	@echo "\n** Make data to run safeTransferFrom(address, address, uint256, bytes) **\n"
	@echo "\"`sed 's/0x/0x000000000000000000000000/' run/nft-nowner2-polygon.addr`\"" > run/call.data
	@sed -i 's/0x/0x0000000000000000000000000000000000000000000000000000000000000849/' run/call.data
	@echo "\n** Check data **\n"
	$(BSC) call @run/bridge.addr \
        Bridge.parseCallDataOnERC721Received @run/call.data -e '[@run/nft-nowner2-polygon.addr, 2121]'
	@echo "\n** Run direct tx **\n"
	$(BSC) tran @run/nft-nowner1-bsc.addr @run/bsc-simpleNFT.addr \
        SimpleNFT.safeTransferFrom @run/nft-nowner1-bsc.addr @run/bridge.addr \
        4 @run/call.data
	@echo "\n** Check new event **\n"
	$(BSC) events 0 latest @run/bridge.addr \
        --event Bridge.Swap --quiet --expect 2
	$(BSC) events 0 latest @run/bridge.addr \
        --event Bridge.Swap --field 1.topics.1 > run/nonce
	$(BSC) exec "web3.personal.unlockAccount(\"`cat run/validator.addr`\",\"\", 8000)"
	$(BSC) exec "eth.sign(\"`cat run/validator.addr`\", `cat run/nonce`)" > run/sig
	$(POLYGON) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 4 -e @run/bridge.addr
	$(POLYGON) tran @run/coinbase.addr @run/bridge.addr \
        Bridge.redeemSwap @run/nft-nowner1-bsc.addr @run/nft-nowner2-polygon.addr \
        4 1212 @run/nonce @run/sig
	@echo "\n** Check ownership transferred from BSC to Polygon by direct tx **\n"
	$(BSC) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 4 -e @run/bridge.addr
	$(POLYGON) call @run/bsc-simpleNFT.addr SimpleNFT.ownerOf 4 -e @run/nft-nowner2-polygon.addr

deploy-contracts:
	@echo "\n** $@ **\n"
	@echo "\n** Deploy NFT in both networks **\n"
	$(BSC) deploy @run/nft-owner.addr SimpleNFT "Test" "TST" -s \
        > run/bsc-simpleNFT.addr
	$(POLYGON) deploy @run/nft-owner.addr SimpleNFT "Test" "TST" -s \
        > run/polygon-simpleNFT.addr
	@echo "\n** Deploy Bridge in both networks **\n"
	$(BSC) deploy @run/coinbase.addr \
        Bridge @run/bsc-simpleNFT.addr @run/validator.addr 1212 -s \
        > run/bridge.addr
	$(POLYGON) deploy @run/coinbase.addr \
        Bridge @run/polygon-simpleNFT.addr @run/validator.addr 2121 -s \
        > run/polygon-bridge.addr

# Preparing fot tests
setup: stop-geth
	@echo "\n** Preparing for TESTS **\n"
	@mkdir -p run/bsc/keystore
	@mkdir -p run/polygon/keystore
# Store address(0) into file
	@echo '"0x0000000000000000000000000000000000000000"' > run/0.addr
# Copy pregenerated key to both chains.
# Use it as coinbase in both chains (only fot test purposes).
	@cp *659ecb1cf623417537d2847045a64416fde598ab run/bsc/keystore/
	@cp *659ecb1cf623417537d2847045a64416fde598ab run/polygon/keystore/
# Start BSC and Polygon geth nodes in --dev mode (for test reasone only)
# --allow-insecure-unlock only for test purposes
	@nohup bsc-geth --dev --networkid 1212 --cache 512 \
        --ipcpath /tmp/bsc.ipc --datadir run/bsc  \
        --allow-insecure-unlock > run/bsc.log 2>&1 &
	@nohup polygon-geth --dev --networkid 2121 --cache 512 \
        --ipcpath /tmp/polygon.ipc --datadir run/polygon \
        --allow-insecure-unlock > run/polygon.log 2>&1 &
# Waiting for nodes up
	@(t=1; while true; do \
        nc.openbsd -Uz /tmp/bsc.ipc > /dev/null 2>&1 && \
        nc.openbsd -Uz /tmp/polygon.ipc > /dev/null 2>&1 && \
            break; \
        t=$$((t+1)); [ $$t -gt 60 ] && exit 1; sleep 1s; \
    done)
# Add an account for validator
	@($(BSC) new-account -s > run/validator.addr)
# Add an account for NFT contract owner in BSC chain
	@($(BSC) new-account -s > run/nft-owner.addr)
# Extract coinbase address
	@($(BSC) exec "eth.accounts[0]" -s > run/coinbase.addr)
# Copy NFT owner to Polygon node keychain
	@(cp run/bsc/keystore/*`cat run/nft-owner.addr | sed 's/0x//'` run/polygon/keystore/)
# Topup accounts in both chains
	@($(BSC) send @run/coinbase.addr @run/nft-owner.addr 10ether)
	@($(POLYGON) send @run/coinbase.addr @run/nft-owner.addr 10ether)

stop-geth:
	@killall -9 bsc-geth > /dev/null 2>&1 || true
	@killall -9 polygon-geth > /dev/null 2>&1 || true

clean: stop-geth
	rm -rf -- build
	rm -rf -- run
	rm -rf -- .ethereum
