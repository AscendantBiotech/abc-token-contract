import json
import os

from vyper import compiler


def transact(w3, func):
    tx_hash = func.transact({"gasPrice": 0})
    receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    return receipt


def vcompile(file_path):
    with open(file_path) as f:
        source_code = f.read()

    compiled_contract = compiler.compile_code(
        source_code, ["abi", "bytecode", "external_interface"]
    )

    return compiled_contract


def deploy(w3, compiled_contract, *args, owner=None, **kwargs):
    contract = w3.eth.contract(
        abi=compiled_contract["abi"], bytecode=compiled_contract["bytecode"]
    )

    params = {"from": owner or w3.eth.accounts[0]}
    params.update(kwargs)
    tx_hash = contract.constructor(*args).transact(params)

    tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    contract_address = tx_receipt.contractAddress

    return contract_address


def get_state(path=""):
    try:
        with open(os.path.join(path, "state.json"), "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_state(state, path=""):
    with open(os.path.join(path, "state.json"), "w") as f:
        json.dump(state, f, indent=2)
