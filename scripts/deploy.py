from datetime import datetime, timedelta
import json
from web3 import Web3
from utils import deploy


def to_timestamp(date):
    return int(date.timestamp() * 1000)


if __name__ == "__main__":
    network_config = {"host": "localhost", "port": 8545, "gas": 4_700_000}

    endpoint = f"http://{network_config['host']}:{network_config['port']}"
    w3 = Web3(Web3.HTTPProvider(endpoint))

    with open("build/contracts/ABC.json") as f:
        complied_contract = json.load(f)

    contract_address = deploy(w3, complied_contract)
    print("Your contract address is: ", contract_address)
