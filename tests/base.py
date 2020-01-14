import unittest
import pytest

from eth_utils.toolz import compose
from eth_tester.exceptions import TransactionFailed
from web3 import Web3
from web3.contract import Contract, mk_collision_prop
from web3.exceptions import ValidationError
from web3.providers.eth_tester import EthereumTesterProvider
from eth_tester import EthereumTester


def assert_validation_failed(func, exception=ValidationError):
    with pytest.raises(exception):
        func()


def assert_tx_failed(func, exception=Exception):
    with pytest.raises(exception):
        func()


class BaseEthTestCase(unittest.TestCase):
    def deploy(self, w3, built_contract, *args, **kwargs):
        abi = built_contract["abi"]
        bytecode = built_contract["bytecode"]
        contract = w3.eth.contract(abi=abi, bytecode=bytecode)

        params = {"from": w3.eth.accounts[0], "gasPrice": 0}
        params.update(kwargs)
        tx_hash = contract.constructor(*args).transact(params)

        tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)
        contract_address = tx_receipt.contractAddress

        return contract_address

    def get_w3(self):
        # network_config = {'host': 'localhost','port': 8545,}
        # endpoint = f"http://{network_config['host']}:{network_config['port']}"
        # return Web3(Web3.HTTPProvider(endpoint))
        return Web3(EthereumTesterProvider(EthereumTester()))

    def get_contract(self, w3, built_contract):
        contract_address = self.deploy(self.w3, built_contract)
        contract = w3.eth.contract(
            address=contract_address,
            abi=built_contract["abi"],
            ContractFactoryClass=ContractFactory,
        )

        return contract_address, contract


class ContractMethod:
    ALLOWED_MODIFIERS = {"call", "estimateGas", "transact", "buildTransaction"}

    def __init__(self, function, normalizers=None):
        self._function = function
        self._function._return_data_normalizers = normalizers

    def __call__(self, *args, **kwargs):
        return self.__prepared_function(*args, **kwargs)

    def __prepared_function(self, *args, **kwargs):
        if not kwargs:
            modifier, modifier_dict = "call", {}
            fn_abi = [
                x
                for x in self._function.contract_abi
                if x.get("name") == self._function.function_identifier
            ].pop()
            # To make tests faster just supply some high gas value.
            modifier_dict.update({"gas": fn_abi.get("gas", 0) + 50000})
        elif len(kwargs) == 1:
            modifier, modifier_dict = kwargs.popitem()
            if modifier not in self.ALLOWED_MODIFIERS:
                raise TypeError(
                    "The only allowed keyword arguments are: %s"
                    % self.ALLOWED_MODIFIERS
                )
        else:
            raise TypeError(
                "Use up to one keyword argument, one of: %s" % self.ALLOWED_MODIFIERS
            )

        return getattr(self._function(*args), modifier)(modifier_dict)


class ContractFactory:

    """
    An alternative Contract Factory which invokes all methods as `call()`,
    unless you add a keyword argument. The keyword argument assigns the prep method.

    This call

    > contract.withdraw(amount, transact={'from': eth.accounts[1], 'gas': 100000, ...})

    is equivalent to this call in the classic contract:

    > contract.functions.withdraw(amount).transact({'from': eth.accounts[1], 'gas': 100000, ...})
    """

    def __init__(self, classic_contract, method_class=ContractMethod):

        classic_contract._return_data_normalizers += CONCISE_NORMALIZERS
        self._classic_contract = classic_contract
        self.address = self._classic_contract.address

        protected_fn_names = [fn for fn in dir(self) if not fn.endswith("__")]

        for fn_name in self._classic_contract.functions:

            # Override namespace collisions
            if fn_name in protected_fn_names:
                _concise_method = mk_collision_prop(fn_name)

            else:
                _classic_method = getattr(self._classic_contract.functions, fn_name)

                _concise_method = method_class(
                    _classic_method, self._classic_contract._return_data_normalizers
                )

            setattr(self, fn_name, _concise_method)

    @classmethod
    def factory(cls, *args, **kwargs):
        return compose(cls, Contract.factory(*args, **kwargs))


def _none_addr(datatype, data):
    if datatype == "address" and int(data, base=16) == 0:
        return (datatype, None)
    else:
        return (datatype, data)


CONCISE_NORMALIZERS = (_none_addr,)
