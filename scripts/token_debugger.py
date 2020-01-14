import argparse
import dateutil.parser

from datetime import date, datetime, timedelta
from scripts.utils import vcompile, deploy, transact
from scripts.const import NETWORK_CONFIG
from web3 import Web3
from web3.middleware import geth_poa_middleware


def get_logs(w3, tx_hash, contract, event_name):
    tx_receipt = w3.eth.getTransactionReceipt(tx_hash)
    logs = contract.events[event_name]().processReceipt(tx_receipt)
    return logs


def create_account_and_fund(w3, source_account, amount, password):
    new_account = w3.geth.personal.newAccount(password)
    w3.eth.sendTransaction({"from": source_account, "to": new_account, "value": amount})
    w3.geth.personal.unlockAccount(new_account, password, 36000)

    return new_account


if __name__ == "__main__":
    endpoint = f"http://{NETWORK_CONFIG['HOST']}:{NETWORK_CONFIG['PORT']}"
    w3 = Web3(Web3.HTTPProvider(endpoint))
    w3.eth.defaultAccount = w3.eth.accounts[0]
    w3.middleware_onion.inject(geth_poa_middleware, layer=0)

    owner = create_account_and_fund(
        w3, w3.eth.accounts[0], w3.toWei(10000, "ether"), "123"
    )


    sender = w3.eth.accounts[0]
    compiled_contract = vcompile("contracts/ABC.vy")
    contract_address = deploy(w3, compiled_contract, owner=owner)

    token_contract = w3.eth.contract(address=contract_address, abi=compiled_contract["abi"])
    tx_hash = token_contract.functions.createToken("ABC Test Token", True).transact(
        {"from": owner}
    )
    logs = get_logs(w3, tx_hash, token_contract, "TransferSingle")
    token_type_id = logs[0].args._token_id

    import ipdb; ipdb.set_trace()
