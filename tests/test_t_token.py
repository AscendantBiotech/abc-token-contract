from datetime import datetime, timedelta
from tests.utils import to_timestamp
from dataclasses import dataclass
from tests.utils import to_timestamp

import pytest

BATCH_SIZE = 100

def printLogEvents(contract, tx_dict):
    #
    #   Would be really nice if we could discover the public method from the tx_dict. Anyone know how?
    #
    ev = contract._classic_contract.events
    print("\nLOG for transaction blockNumber: %s, total gas: %s" % (tx_dict.blockNumber,tx_dict.gasUsed))
    for event in ev:
        #print("event: %s = dir(event): %s\n" % (event, dir(event)))
        #print("event(): %s\n" % event())
        #print("event().event_name : %s" % event().event_name)
        
        receipt = event().processReceipt(tx_dict)
        #print("receipt = %s\n" % str(receipt))
        receipt_text = ""
        if receipt:
            if len(receipt) == 1:
                #receipt_text += "\tblockNumber : %s" % receipt[0].blockNumber
                for x in receipt[0].args:
                    receipt_text += "\n\t\t%s : %s" % (x,receipt[0].args[x])
            else:
                receipt_text += "(Multiple Entries)"
                for n in range(len(receipt)):
                    for x in receipt[n].args:
                        receipt_text += "\n\t\t%s) %s : %s" % (n,x,receipt[n].args[x])
        else:
            receipt_text += " : No incidents."
        print("\tEVENT: %s %s\n" % (event().event_name, receipt_text))
    #print("tx_dict = %s" % tx_dict)


def resize(input_list, size, default_value=0):
    return input_list[:size] + [default_value for _ in range(size - len(input_list))]


@pytest.fixture
def erc20_contract(w3, get_contract):
    with open("contracts/mockERC20Token.vy") as f:
        contract_code = f.read()
        return get_contract(contract_code, "Mock ERC20", "MER", 10, 2000)


@pytest.fixture
def erc1155_contract(w3, get_contract, zero_address):
    with open("contracts/ABC.vy") as f:
        contract_code = f.read()
        return get_contract(contract_code)


@dataclass
class demo_accounts:
    ao: str
    to: str
    tco: str
    wo: str




@pytest.fixture
def accounts(w3):

    return demo_accounts(   ao=w3.eth.accounts[0],
                            to= w3.eth.accounts[1],
                            tco= w3.eth.accounts[2],
                            wo= w3.eth.accounts[0]  )


def _get_available_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs):
    # account = demo_accounts(    ao=w3.eth.accounts[0],
    #                             to= w3.eth.accounts[1],
    #                             tco= w3.eth.accounts[2],
    #                             wo= w3.eth.accounts[0]  )
    
    tx_hash = erc1155_contract.createToken("Non-Fungible Mock", True, transact={"from": accounts.ao})
    token_type = get_logs(tx_hash, erc1155_contract, "TransferSingle")[0].args._token_id

    with open("contracts/TokenService.vy") as f:
        contract_code = f.read()
        acs_contract = get_contract(contract_code, erc1155_contract.address, token_type)

    erc1155_contract.setTokenService(acs_contract.address, token_type, transact={"from": accounts.ao})
    erc1155_contract.acs_contract = acs_contract
    erc1155_contract.setMintTokenApproval(token_type, accounts.ao, True, transact={"from": accounts.ao})
    erc1155_contract.token_type = token_type
    erc1155_contract.acs_contract = acs_contract

    with open("contracts/mockTokenCall.vy") as f:
        contract_code = f.read()
        max_preferred_tkns = 10
        max_total_tkns = 20
        start_date = to_timestamp(datetime.today() - timedelta(days=5))
        end_date = w3.eth.getBlock("latest").timestamp + 4
        token_call_contract = get_contract(
            contract_code,
            erc1155_contract.address,
            token_type,
            0,
            max_preferred_tkns,
            max_total_tkns,
            start_date,
            end_date
        )
    erc1155_contract.token_call_contract = token_call_contract

    ## AO Create Token #1
    erc1155_contract.mintNonFungibleToken(
        token_type,
        resize([accounts.to], BATCH_SIZE, default_value=zero_address),
        transact={"from": accounts.ao},
    )

    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert acs_contract.get_state(token_type | 1) == 1
    return erc1155_contract



def test_available_token(w3, erc1155_contract, zero_address, get_contract, accounts, assert_tx_failed, get_logs):
    erc1155_contract = _get_available_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs)
    accounts.tco = erc1155_contract.token_call_contract.address
    token_id = erc1155_contract.token_type | 1
    assert erc1155_contract.acs_contract.get_state(token_id) == 1

    tester = w3.provider.ethereum_tester
    snapshot = tester.take_snapshot()

    valid_trans=[(erc1155_contract.applyToken, accounts.to), (erc1155_contract.acs_contract.sellToken, accounts.to)]

    all_senders=[accounts.ao, accounts.to, accounts.tco, accounts.wo]

    trans = [ { "event": erc1155_contract.applyToken, 
                "params": [token_id, accounts.tco], 
                #"sender": accounts.to,
                "end_state" : 2,
                },
                { "event": erc1155_contract.acs_contract.sellToken, 
                "params": [token_id, accounts.wo, zero_address, 5000, w3.eth.getBlock("latest").timestamp + 1000], 
                #"sender": accounts.to,
                "end_state" : 5,
                },
             ]
    for sender in all_senders:
        for t in trans:
            tester.revert_to_snapshot(snapshot)

            if (t["event"],sender) in valid_trans:

                t["event"](*t["params"], transact={"from": sender})
                assert erc1155_contract.acs_contract.get_state(token_id) == t["end_state"]

            else:

                assert_tx_failed( lambda: t["event"](*t["params"], transact={"from": sender}) )
                assert erc1155_contract.acs_contract.get_state(token_id) != t["end_state"]





def test_get_optioned_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs):
    erc1155_contract = _get_available_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs)
    accounts.tco = erc1155_contract.token_call_contract.address
    token_id = erc1155_contract.token_type | 1


    price = 500000     
    # Make sure both wallets start off equally.
    orig_to = w3.eth.getBalance(accounts.to)
    orig_wo = w3.eth.getBalance(accounts.wo)
    assert orig_to == orig_wo
    expires = w3.eth.getBlock("latest").timestamp + 1000

    tx_hash = erc1155_contract.acs_contract.sellToken(token_id, accounts.wo, zero_address, price, expires, transact={"from": accounts.to})
    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert erc1155_contract.acs_contract.get_state(token_id) == 5

    return erc1155_contract


def test_get_applied_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs):
    erc1155_contract = _get_available_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs)
    accounts.tco = erc1155_contract.token_call_contract.address
    token_id = erc1155_contract.token_type | 1

    tx_hash = erc1155_contract.applyToken(token_id, accounts.tco, transact={"from": accounts.to})
    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert erc1155_contract.acs_contract.get_state(token_id) == 2

    return erc1155_contract


def test_get_processing_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs):
    erc1155_contract = test_get_applied_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs)
    token_id = erc1155_contract.token_type | 1

    tx_hash = erc1155_contract.token_call_contract.docsSubmitted(token_id, transact={"from": accounts.ao})
    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert erc1155_contract.acs_contract.get_state(token_id) == 3

    return erc1155_contract


def test_get_approved_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs):
    erc1155_contract = test_get_processing_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs)
    token_id = erc1155_contract.token_type | 1

    tx_hash = erc1155_contract.token_call_contract.userQualified(token_id, transact={"from": accounts.ao})
    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert erc1155_contract.acs_contract.get_state(token_id) == 4

    return erc1155_contract


def test_get_burned_token(w3, erc1155_contract, zero_address, get_contract, accounts, get_logs):
    erc1155_contract = test_get_approved_token(w3, erc1155_contract, zero_address, get_contract, accounts,get_logs)
    token_id = erc1155_contract.token_type | 1

    assert erc1155_contract.token_call_contract.getState() == 4 # TC is closed
    tx_hash = erc1155_contract.token_call_contract.finalize(1, transact={"from": accounts.ao})
    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert erc1155_contract.acs_contract.get_state(token_id) == 6

    return erc1155_contract


def test_full_token_happy_path(w3, erc1155_contract, zero_address, get_contract, erc20_contract, get_logs):

    ao_sender = w3.eth.accounts[0]  # Always gets credit for deployed contracts.
    to_sender = w3.eth.accounts[1]
    tco_sender = w3.eth.accounts[2]
    wo_sender = w3.eth.accounts[3]


    print("\n")
    for x in [("ao",ao_sender), ("to",to_sender), ("tco",tco_sender), ("wo",wo_sender)]:
        print("%s : %s (%s)" % (x[0],x[1],w3.eth.getBalance(x[1])) )
    print("\n")

    with open("contracts/TokenService.vy") as f:
        contract_code = f.read()
        tx_hash = erc1155_contract.createToken("Non-Fungible Mock", True, transact={"from": ao_sender})
        token_type = get_logs(tx_hash, erc1155_contract, "TransferSingle")[0].args._token_id

        acs_contract = get_contract(contract_code, erc1155_contract.address, token_type)

        erc1155_contract.setTokenService(acs_contract.address, token_type, transact={"from": ao_sender})
        erc1155_contract.setMintTokenApproval(token_type, ao_sender, True, transact={"from": ao_sender})

        with open("contracts/mockTokenCall.vy") as f:
            contract_code = f.read()
            max_preferred_tkns = 10
            max_total_tkns = 20
            start_date = w3.eth.getBlock("latest").timestamp
            end_date = w3.eth.getBlock("latest").timestamp + 15
            token_call_contract = get_contract(
                contract_code,
                erc1155_contract.address,
                token_type,
                0,
                max_preferred_tkns,
                max_total_tkns,
                start_date,
                end_date
            )
        tco_sender = token_call_contract.address

        assert acs_contract.get_nextTid() == token_type | 1

        ## AO Create Token #1
        tx_hash = erc1155_contract.mintNonFungibleToken(
            token_type,
            resize([to_sender], BATCH_SIZE, default_value=zero_address),
            transact={"from": ao_sender},
        )
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)
        token_1_id = token_type | 1
        assert acs_contract.get_nextTid() == token_type | 2
        assert acs_contract.get_state(token_1_id) == 1

        printLogEvents(acs_contract, tx_dict)

        print("TO Apply Token #1")
        tx_hash = erc1155_contract.applyToken(token_1_id, tco_sender, transact={"from": to_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_1_id) == 2

        print("TCO Reject User Token #1")
        tx_hash = token_call_contract.userRejected(token_1_id, transact={"from": ao_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_1_id) == 1

        print("AO Create Token #2")

        tx_hash = erc1155_contract.mintNonFungibleToken(
            token_type,
            resize([to_sender], BATCH_SIZE, default_value=zero_address),
            transact={"from": ao_sender},
        )
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)
        token_2_id = token_type | 2

        assert acs_contract.get_nextTid() == token_type | 3
        assert acs_contract.get_state(token_1_id) == 1

        print("TO Apply Token #2")
        tx_hash = erc1155_contract.applyToken(token_2_id, tco_sender, transact={"from": to_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 2

        print("TO Remove Token #2")
        tx_hash = erc1155_contract.removeToken(token_2_id, transact={"from": to_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 1

        price = 500000
        # Make sure both wallets start off equally.
        orig_to = w3.eth.getBalance(to_sender)
        orig_wo = w3.eth.getBalance(wo_sender)
        assert orig_to == orig_wo
        print("TO Sell Token to WO for %s wei" % price)
        expires = w3.eth.getBlock("latest").timestamp + 1000
        tx_hash = acs_contract.sellToken(token_2_id, wo_sender, zero_address, price, expires, transact={"from": to_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 5

        print("WO Buys Token from TO for %s wei" % price)
        tx_hash = acs_contract.buyToken(token_2_id, zero_address, transact={"from": wo_sender, "value" : price})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 1

        # Make sure money was transferred to the wallet.
        assert orig_wo - price == w3.eth.getBalance(wo_sender) 
        assert orig_to + price == w3.eth.getBalance(to_sender)

        print("WO Sell Token to TO for 10 ERC20 tokens")

        # Give TO wallet 1000 ERC-20 tokens.
        erc20_contract.mint(to_sender, 1000, transact={'from' : ao_sender})

        # Get ERC-20 balances for TO & WO
        to_erc = erc20_contract.balanceOf(to_sender)
        wo_erc = erc20_contract.balanceOf(wo_sender)

        # WO Sell Token to TO for 10 ERC20.
        price = 10
        expires = w3.eth.getBlock("latest").timestamp + 1000
        tx_hash = acs_contract.sellToken(token_2_id, to_sender, erc20_contract.address, price, expires, transact={"from": wo_sender})


        print("TO Buys Token from WO for 10 ERC20.")

        # Approve ERC20 transfer
        erc20_contract.approve(acs_contract.address, price, transact={'from': to_sender})
        tx_hash = acs_contract.buyToken(token_2_id, erc20_contract.address, transact={"from": to_sender, "value" : price})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 1

        # Confirm WO has 10 more ERC20 tokens and TO has 10 fewer.
        assert wo_erc + price == erc20_contract.balanceOf(wo_sender) 
        assert to_erc - price == erc20_contract.balanceOf(to_sender)



        print("TO Apply Token #2")
        tx_hash = erc1155_contract.applyToken(token_2_id, tco_sender, transact={"from": to_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 2


        print("TCO Docs Submitted Token #2")
        tx_hash = token_call_contract.docsSubmitted(token_2_id, transact={"from": ao_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 3


        print("TCO User Qualified Token #2")
        tx_hash = token_call_contract.userQualified(token_2_id, transact={"from": ao_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 4

        print("TCO finalize & Burn Token #2")
        tx_hash = token_call_contract.finalize(2, transact={"from": ao_sender})
        tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

        printLogEvents(acs_contract, tx_dict)
        assert acs_contract.get_state(token_2_id) == 6

        print("\ntx_hash : %s" % tx_hash)


    print("\n")
    for x in [("ao",ao_sender), ("to",to_sender), ("tco",tco_sender), ("wo",wo_sender)]:
        print("%s : %s (%s)" % (x[0],x[1],w3.eth.getBalance(x[1])) )
    print("\n")        







