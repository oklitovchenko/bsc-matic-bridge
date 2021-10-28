# Simple bridge solidity smart contract example

inherited from openzeppelin-contracts

## Summary
Simple bridge solidity smart contract example with integration tests.   
Executed according to https://docs.google.com/document/d/1LTV03VZZENlOVqNjQunjy1eu8f03tT4Z8FKT0gt6HdA/edit

For this repository development environment must include:

_Debian Bullseye_ distributive  
_solidity_ - solc compiler built from https://github.com/ethereum/solidity  
_bsc-geth_ - geth deb pakage built from https://github.com/binance-chain/bsc     
_polygon-geth_ - geth deb pakage built from https://github.com/maticnetwork/bor  
_ethester_ - https://github.com/oklitovchenko/ethester 

### To prepare build/test enviroment:
```
apt-get update -y
apt-get install -y wget
wget https://github.com/oklitovchenko/ethester/releases/download/0.12.0/ethester_0.12.0_all.deb
wget https://github.com/oklitovchenko/deb-ethereum/releases/download/1.0.0/bsc_1.0.0_amd64.deb
wget https://github.com/oklitovchenko/deb-ethereum/releases/download/1.0.0/polygon_1.0.0_amd64.deb
wget https://github.com/oklitovchenko/deb-ethereum/releases/download/1.0.0/solidity_1.0.0_amd64.deb
dpkg -i bsc_1.0.0_amd64.deb
dpkg -i polygon_1.0.0_amd64.deb
dpkg -i solidity_1.0.0_amd64.deb
dpkg -i ethester_0.11.1_all.deb
apt --fix-broken install
git clone --recursive git@github.com:oklitovchenko/bsc-matic-bridge.git
```
### To compile *.sol files:
```
cd bsc-matic-bridge.git
make build
```
### To run tests:
```
make test
```