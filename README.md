# ERC-1155 token smart contract


## Prerequisites

- docker
- docker-compose
- git


## Setup
```bash
./setup
```


## Smart contract

#### Compile
```bash
./compile
```

Result of compilation will be generated to `{project_root}/build/contracts/`


#### Run tests
```bash
./runtests
```

#### Debugging the contract ####
```bash
./debug
```

#### Deploy smart contract
In order to deploy you need to have an existing ethereum node to deploy the contract to.
If you don't have one please take a look [private network](#private-network) section.

If your ethereum node ready, then
```bash
./deploy
```
