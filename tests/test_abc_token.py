import pytest
from datetime import datetime, timedelta
from tests.utils import to_timestamp


MAX_BATCH_SIZE = 100
TOKEN_RANGE = range(1, 10)
INITIAL_MINT = 300


def resize(input_list, size, default_value=0):
    return input_list[:size] + [default_value for _ in range(size - len(input_list))]


def get_bids(contract, level=0):
    result = []
    cursor = contract.levels__nextBid(level, 0)

    while cursor != 0:
        bid_id = cursor
        value = contract.levels__value(level, cursor)
        cursor = contract.levels__nextBid(level, cursor)
        result.append((bid_id, value))
    return result


@pytest.fixture
def contract(w3, get_contract):
    with open("contracts/ABC.vy") as f:
        contract_code = f.read()
        return get_contract(contract_code)


@pytest.fixture
def receiver_contract(w3, get_contract):
    sender = w3.eth.accounts[0]
    with open("contracts/mockERC1155Receiver.vy") as f:
        contract_code = f.read()
        return get_contract(contract_code)


@pytest.fixture
def erc20_contract(w3, get_contract):
    with open("contracts/mockERC20Token.vy") as f:
        contract_code = f.read()
        return get_contract(contract_code, "Mock ERC20", "MER", 20, 20)


@pytest.fixture
def minted_contract(w3, contract, zero_address, get_logs, get_contract):
    owner = w3.eth.accounts[0]

    tx_hash = contract.createToken("Non-Fungible", True, transact={"from": owner})
    token_type = get_logs(tx_hash, contract, "TransferSingle")[0].args._token_id
    with open("contracts/TokenService.vy") as f:
        contract_code = f.read()
        token_service_contract = get_contract(contract_code, contract.address, token_type)
    contract.setTokenService(token_service_contract.address, token_type, transact={"from": owner})
    contract.token_service_contract = token_service_contract

    tx_hash = contract.createToken("Fungible", True, transact={"from": owner})
    token_type_fungible = get_logs(tx_hash, contract, "TransferSingle")[0].args._token_id

    mint_token_to = [owner for _ in TOKEN_RANGE]

    contract.setMintTokenApproval(token_type, owner, True, transact={"from": owner})

    contract.mintNonFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        transact={"from": owner},
    )
    contract.token_type = token_type
    contract.token_type_fungible = token_type_fungible
    contract.token_ids = [token_type | index for index in TOKEN_RANGE]

    tx_hash = contract.createToken("Fungible", False, transact={"from": owner})
    fungible_token_id = get_logs(tx_hash, contract, "TransferSingle")[0].args._token_id

    contract.mintFungibleToken(
        fungible_token_id,
        resize([owner], MAX_BATCH_SIZE, default_value=zero_address),
        resize([INITIAL_MINT], MAX_BATCH_SIZE),
        transact={"from": owner},
    )

    contract.fungible_token_id = fungible_token_id

    return contract


@pytest.fixture
def token_call_contract(w3, get_contract, minted_contract):
    with open("contracts/mockTokenCall.vy") as f:
        contract_code = f.read()
        max_preferred_tkns = 10
        max_total_tkns = 20
        start_date = to_timestamp(datetime.today() - timedelta(days=5))
        end_date = to_timestamp(datetime.today() + timedelta(days=5))
        return get_contract(
            contract_code,
            minted_contract.address,
            minted_contract.token_type,
            minted_contract.token_type_fungible,
            max_preferred_tkns,
            max_total_tkns,
            start_date,
            end_date
    )


def test_create_and_mint_token(w3, contract, zero_address, get_contract):
    sender = w3.eth.accounts[0]

    tx_hash = contract.createToken("test_create_token", True, transact={"from": sender})
    hex_token_id = w3.eth.getTransactionReceipt(tx_hash).logs[1].topics[1]
    token_type = int(hex_token_id.hex(), 0)
    with open("contracts/TokenService.vy") as f:
        contract_code = f.read()
        token_service_contract = get_contract(contract_code, contract.address, token_type)
    contract.setTokenService(token_service_contract.address, token_type, transact={"from": sender})

    assert token_type == 1 << 128 | 1 << 255

    mint_token_to = resize(
        w3.eth.accounts[1:4], MAX_BATCH_SIZE, default_value=zero_address
    )
    token_ids = [i for i in range(1, 10)]

    contract.setMintTokenApproval(token_type, sender, True, transact={"from": sender})
    tx_hash = contract.mintNonFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        transact={"from": sender},
    )

    tx_dict = w3.eth.waitForTransactionReceipt(tx_hash)

    assert all(
        token_service_contract.tokens__owner(token_type | token_id) == to
        for to, token_id in zip(mint_token_to, token_ids)
        if to != zero_address
    )
    assert all(
        contract.getNFTOwner(token_type | token_id) == to
        for to, token_id in zip(mint_token_to, token_ids)
        if to != zero_address
    )


def test_set_uri(w3, minted_contract, assert_tx_failed):
    owner = w3.eth.accounts[0]
    non_owner = w3.eth.accounts[1]
    newURI = "New updated URI"

    assert_tx_failed(
        lambda: minted_contract.setURI(newURI, minted_contract.token_type, transact={"from": non_owner})
    )
    
    minted_contract.setURI(newURI, minted_contract.token_type, transact={"from": owner})

    assert minted_contract.tokenTypes__uri(minted_contract.token_type) == newURI
    


def test_get_balance_single_token(w3, minted_contract, zero_address, get_logs):
    owner = w3.eth.accounts[0]

    assert all(
        minted_contract.balanceOf(owner, token_id)
        for token_id in minted_contract.token_ids
    )
    assert minted_contract.balanceOf(owner, minted_contract.token_type) == len(
        TOKEN_RANGE
    )

    assert (
        minted_contract.balanceOf(owner, minted_contract.fungible_token_id)
        == INITIAL_MINT
    )


def test_get_balance_batch_token(w3, minted_contract, zero_address, get_logs):
    sender = w3.eth.accounts[0]
    other_account = w3.eth.accounts[1]
    token_ids = resize(minted_contract.token_ids, MAX_BATCH_SIZE)
    accounts = resize(
        [sender] * 5 + [other_account] * 5, MAX_BATCH_SIZE, default_value=zero_address
    )
    assert minted_contract.balanceOfBatch(accounts, token_ids, call={'from': sender, 'gas': 2000000}) == [
        1 if i < 5 else 0 for i in range(0, MAX_BATCH_SIZE)
    ]


def test_safe_transfer_from_should_transfer_non_fungible_token_to_other_account(
    w3, minted_contract, zero_address, get_logs
):
    owner = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[5]

    tx_hash = minted_contract.safeTransferFrom(
        owner, to, token_id, 1, "", transact={"from": owner}
    )
    assert minted_contract.balanceOf(to, token_id) == 1
    assert minted_contract.balanceOf(owner, token_id) == 0


def test_safe_transfer_from_should_transfer_fungible_token_to_other_account(
    w3, minted_contract, assert_tx_failed
):
    owner = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.fungible_token_id
    transfer_amount = 50

    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            owner,
            to,
            token_id,
            INITIAL_MINT + transfer_amount,
            "",
            transact={"from": owner},
        )
    )

    assert minted_contract.balanceOf(to, token_id) == 0
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT

    tx_hash = minted_contract.safeTransferFrom(
        owner, to, token_id, transfer_amount, "", transact={"from": owner}
    )
    assert minted_contract.balanceOf(to, token_id) == transfer_amount
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - transfer_amount


def test_safe_transfer_from_transfer_fungible_token_to_self_with_approval(
    w3, minted_contract, assert_tx_failed
):
    owner = w3.eth.accounts[0]
    to = w3.eth.accounts[1]

    token_id = minted_contract.fungible_token_id

    # Transaction should failed because no allowance
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            owner, to, token_id, 100, "", transact={"from": to}
        )
    )

    minted_contract.setApprovalForAll(to, True, transact={"from": owner})

    minted_contract.safeTransferFrom(owner, to, token_id, 25, "", transact={"from": to})

    assert minted_contract.balanceOf(to, token_id) == 25
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - 25

    minted_contract.safeTransferFrom(owner, to, token_id, 25, "", transact={"from": to})

    assert minted_contract.balanceOf(to, token_id) == 50
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - 50


def test_safe_transfer_from_transfer_non_fungible_token_to_self_with_approval(
    w3, minted_contract, zero_address, get_logs, assert_tx_failed
):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[5]

    # Transaction should failed because no allowance
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            sender, to, token_id, 1, "", transact={"from": to}
        )
    )

    minted_contract.setApprovalForAll(to, True, transact={"from": sender})

    minted_contract.safeTransferFrom(sender, to, token_id, 1, "", transact={"from": to})
    assert minted_contract.balanceOf(to, token_id) == 1
    assert minted_contract.balanceOf(sender, token_id) == 0

    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            sender, to, token_id, 1, "", transact={"from": sender}
        )
    )


def test_safe_transfer_from_transfer_fungible_token_to_self_with_approved_amount(
    w3, minted_contract, assert_tx_failed
):
    owner = w3.eth.accounts[0]
    to = w3.eth.accounts[1]

    token_id = minted_contract.fungible_token_id

    # Transaction should failed because no allowance
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            owner, to, token_id, 100, "", transact={"from": to}
        )
    )

    minted_contract.approve(to, token_id, 0, 30, transact={"from": owner})
    minted_contract.safeTransferFrom(owner, to, token_id, 25, "", transact={"from": to})

    assert minted_contract.balanceOf(to, token_id) == 25
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - 25

    # Transaction should failed because exceed maximum allowance
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            owner, to, token_id, 26, "", transact={"from": to}
        )
    )

    minted_contract.safeTransferFrom(owner, to, token_id, 5, "", transact={"from": to})

    assert minted_contract.balanceOf(to, token_id) == 30
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - 30


def test_safe_transfer_from_transfer_non_fungible_token_to_self_with_approved_token(
    w3, minted_contract, zero_address, get_logs, assert_tx_failed
):
    owner = w3.eth.accounts[0]
    to = w3.eth.accounts[1]

    token_id = minted_contract.fungible_token_id

    # Transaction should failed because no allowance
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            owner, to, token_id, 100, "", transact={"from": to}
        )
    )

    minted_contract.approve(to, token_id, 0, 20, transact={"from": owner})
    minted_contract.setApprovalForAll(to, True, transact={"from": owner})
    minted_contract.safeTransferFrom(owner, to, token_id, 25, "", transact={"from": to})

    assert minted_contract.balanceOf(to, token_id) == 25
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - 25

    assert minted_contract.allowance(owner, to, token_id) == 20


    minted_contract.setApprovalForAll(to, False, transact={"from": owner})

    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            owner, to, token_id, 26, "", transact={"from": to}
        )
    )

    minted_contract.safeTransferFrom(owner, to, token_id, 10, "", transact={"from": to})

    assert minted_contract.balanceOf(to, token_id) == 35
    assert minted_contract.balanceOf(owner, token_id) == INITIAL_MINT - 35

    assert minted_contract.allowance(owner, to, token_id) == 10


def test_safe_transfer_should_not_approved_amount_for_operator(
    w3, minted_contract, zero_address, get_logs, assert_tx_failed
):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[5]

    # Transaction should failed because no allowance
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            sender, to, token_id, 1, "", transact={"from": to}
        )
    )

    minted_contract.approve(to, token_id, 0, 2, transact={"from": sender})

    minted_contract.safeTransferFrom(sender, to, token_id, 1, "", transact={"from": to})
    assert minted_contract.balanceOf(to, token_id) == 1
    assert minted_contract.balanceOf(sender, token_id) == 0

    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            sender, to, token_id, 1, "", transact={"from": sender}
        )
    )


def test_safe_transfer_should_transfer_asset_to_other_receiver_contract(
    w3, minted_contract, receiver_contract, zero_address, get_logs
):
    sender = w3.eth.accounts[0]
    to = receiver_contract.address
    token_id = minted_contract.token_ids[5]

    tx_hash = minted_contract.safeTransferFrom(
        sender, to, token_id, 1, "", transact={"from": sender}
    )
    assert minted_contract.balanceOf(to, token_id) == 1
    assert minted_contract.balanceOf(sender, token_id) == 0


def test_safe_batch_transfer_should_transfer_asset_to_other_receiver_contract(
    w3, minted_contract, receiver_contract, zero_address, get_logs
):
    sender = w3.eth.accounts[0]
    to = receiver_contract.address
    start, end = 4, 8

    token_ids = resize(minted_contract.token_ids[start:end], MAX_BATCH_SIZE)
    values = resize([1] * (end - start), MAX_BATCH_SIZE)

    tx_hash = minted_contract.safeBatchTransferFrom(
        sender, to, token_ids, values, "", transact={"from": sender}
    )

    for token_id in token_ids:
        if token_id == 0:
            continue
        assert minted_contract.balanceOf(to, token_id) == 1
        assert minted_contract.balanceOf(sender, token_id) == 0


def test_safe_transfer_batch_from_should_transfer_asset_to_other_users(
    w3, minted_contract, zero_address, get_logs
):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_ids = resize(minted_contract.token_ids[6:9], MAX_BATCH_SIZE)
    values = resize([1 for _ in range(3)], MAX_BATCH_SIZE)

    tx_hash = minted_contract.safeBatchTransferFrom(
        sender, to, token_ids, values, "", transact={"from": sender}
    )

    for token_id in token_ids:
        if token_id == 0:
            continue
        assert minted_contract.balanceOf(to, token_id) == 1
        assert minted_contract.balanceOf(sender, token_id) == 0


def test_apply_and_withdraw_token(
        w3, minted_contract, token_call_contract, assert_tx_failed, get_logs):
    sender = w3.eth.accounts[0]
    token_id = minted_contract.token_ids[0]

    minted_contract.applyToken(token_id, token_call_contract.address, transact={"from": sender})

    assert minted_contract.getNFTTokenCall(token_id) == token_call_contract.address

    # Tx failed - can not withdraw the token call directly
    assert_tx_failed(
        lambda: token_call_contract.removeToken(
            token_id, transact={"from": sender}
        )
    )

    minted_contract.removeToken(token_id, transact={"from": sender})

    assert minted_contract.getNFTTokenCall(token_id) == None


def test_burn_token(w3, minted_contract, get_contract,  assert_tx_failed, get_logs):
    with open("contracts/mockTokenCall.vy") as f:
        contract_code = f.read()
        max_preferred_tkns = 10
        max_total_tkns = 20
        start_date = to_timestamp(datetime.today() - timedelta(days=5))
        end_date = w3.eth.getBlock('latest').timestamp + 8
        current = w3.eth.getBlock('latest').timestamp
        token_call_contract = get_contract(
            contract_code,
            minted_contract.address,
            minted_contract.token_type,
            minted_contract.token_type_fungible,
            max_preferred_tkns,
            max_total_tkns,
            start_date,
            end_date
        )

    sender = w3.eth.accounts[0]
    token_id = minted_contract.token_ids[0]
    token_id_2 = minted_contract.token_ids[1]

    # Cannot burn token directly
    assert_tx_failed(
        lambda: minted_contract.finalize(token_id, transact={"from": sender})
    )

    minted_contract.applyToken(token_id, token_call_contract.address, transact={"from": sender})
    minted_contract.applyToken(token_id_2, token_call_contract.address, transact={"from": sender})

    assert minted_contract.getNFTState(token_id) == 2 # Applied

    # Cannot burn token directly even the token is applied
    assert_tx_failed(
        lambda: minted_contract.finalize(token_id, transact={"from": sender})
    )

    token_call_contract.docsSubmitted(token_id, transact={"from": sender})
    token_call_contract.userQualified(token_id, transact={"from": sender})
    token_call_contract.docsSubmitted(token_id_2, transact={"from": sender})
    token_call_contract.userQualified(token_id_2, transact={"from": sender})

    assert minted_contract.getNFTState(token_id) == 4 # Approved
    # Only finalizing a token call can burn a token

    tx_hash = token_call_contract.finalize(1, transact={"from": sender, "gas": 2000000})

    assert minted_contract.getNFTOwner(token_id) == None

    assert token_call_contract.getState() == 4 # Closed

    assert_tx_failed(
        lambda: minted_contract.removeToken(token_id, transact={"from": sender})
    )


def test_should_not_be_able_to_apply_to_unsupported_token_call(
    w3, minted_contract, token_call_contract, assert_tx_failed
):
    sender = w3.eth.accounts[0]
    invalid_token_call = w3.eth.accounts[0]
    token_id = minted_contract.token_ids[0]

    # Cannot apply token directly
    assert_tx_failed(
        lambda: token_call_contract.applyToken(
            token_id, transact={"from": invalid_token_call}
        )
    )


def test_sell_token(w3, minted_contract, receiver_contract, token_call_contract, erc20_contract, assert_tx_failed):
    sender = w3.eth.accounts[0]
    to = receiver_contract.address
    token_id = minted_contract.token_ids[0]

    # Available state
    assert minted_contract.getNFTState(token_id) == 1
    # Sender is owner
    assert minted_contract.getNFTOwner(token_id) == sender

    minted_contract.applyToken(token_id, token_call_contract.address, transact={'from': sender})
    # Assert token is applied
    assert minted_contract.getNFTState(token_id) == 2
    assert minted_contract.getNFTTokenCall(token_id) == token_call_contract.address

    # Cannot sell an applied token
    assert_tx_failed(
        lambda: minted_contract.token_service_contract.sellToken(token_id, to, erc20_contract.address, 10, w3.eth.getBlock("latest").timestamp + 100, transact={'from': sender})
    )
    assert minted_contract.getNFTState(token_id) == 2
    minted_contract.removeToken(token_id, transact={'from': sender})

    minted_contract.token_service_contract.sellToken(token_id, to, erc20_contract.address, 10, w3.eth.getBlock("latest").timestamp + 100, transact={'from': sender})

    assert minted_contract.getNFTState(token_id) == 5
    assert minted_contract.token_service_contract.tokens__option__buyer(token_id) == to
    assert minted_contract.token_service_contract.tokens__option__price(token_id) == 10
    assert minted_contract.token_service_contract.tokens__option__currency(token_id) == erc20_contract.address

    # After set sell option, the token should not be able to transfer or applied to token calls
    assert_tx_failed(
        lambda: minted_contract.safeTransferFrom(
            sender, to, token_id, 1, "", transact={"from": sender}
        )
    )

    token_ids = resize([token_id], MAX_BATCH_SIZE)
    values = resize([1], MAX_BATCH_SIZE)
    assert_tx_failed(
        lambda: minted_contract.safeBatchTransferFrom(
            sender, to, token_ids, values, "", transact={"from": sender}
        )
    )

    assert_tx_failed(
        lambda: minted_contract.applyToken(token_id, token_call_contract.address, transact={'from': sender})
    )


def test_buy_token_erc20(w3, minted_contract, receiver_contract, erc20_contract, assert_tx_failed):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[0]
    erc20_contract.transfer(to, 50, transact={'from': sender})
    initial_sender_balance = erc20_contract.balanceOf(sender)

    assert minted_contract.getNFTState(token_id) == 1

    minted_contract.token_service_contract.sellToken(token_id, to, erc20_contract.address, 10, w3.eth.getBlock("latest").timestamp + 100, transact={'from': sender})

    assert minted_contract.getNFTState(token_id) == 5

    erc20_contract.approve(minted_contract.token_service_contract.address, 10, transact={'from': to})
    minted_contract.token_service_contract.buyToken(token_id, erc20_contract.address, transact={'from': to})

    assert minted_contract.getNFTOwner(token_id) == to
    assert minted_contract.token_service_contract.tokens__option__expires(token_id) == 0
    assert minted_contract.token_service_contract.tokens__option__buyer(token_id) == None
    assert minted_contract.token_service_contract.tokens__option__price(token_id) == 0
    assert minted_contract.token_service_contract.tokens__option__currency(token_id) == None

    assert erc20_contract.balanceOf(to) == 40
    assert erc20_contract.balanceOf(sender) == initial_sender_balance + 10


def test_buy_token_native(w3, minted_contract, receiver_contract, erc20_contract, assert_tx_failed, zero_address):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[0]
    initial_sender_balance = w3.eth.getBalance(sender)
    initial_to_balance = w3.eth.getBalance(to)

    assert minted_contract.getNFTState(token_id) == 1

    minted_contract.token_service_contract.sellToken(token_id, to, zero_address, 10, w3.eth.getBlock("latest").timestamp + 100, transact={'from': sender})

    assert minted_contract.getNFTState(token_id) == 5

    minted_contract.token_service_contract.buyToken(token_id, zero_address, transact={'from': to, 'value': 10 })

    assert minted_contract.getNFTOwner(token_id) == to
    assert minted_contract.token_service_contract.tokens__option__expires(token_id) == 0
    assert minted_contract.token_service_contract.tokens__option__buyer(token_id) == None
    assert minted_contract.token_service_contract.tokens__option__price(token_id) == 0
    assert minted_contract.token_service_contract.tokens__option__currency(token_id) == None

    assert w3.eth.getBalance(sender) == initial_sender_balance + 10
    assert w3.eth.getBalance(to) == initial_to_balance - 10


def test_available_state(w3, minted_contract, receiver_contract, token_call_contract, erc20_contract, assert_tx_failed, zero_address):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[0]

    # Available state
    assert minted_contract.getNFTState(token_id) == 1
    # Sender is owner
    assert minted_contract.getNFTOwner(token_id) == sender

    # minted_contract.tokenCallApprove(token_call_contract.address, token_id, transact={"from": sender})
    # token_call_contract.applyToken(token_id, transact={'from': sender})

    assert_tx_failed(
        lambda: minted_contract.removeToken(token_id, transact={'from': sender})
    )

    minted_contract.token_service_contract.sellToken(
        token_id,
        to,
        zero_address,
        10,
        w3.eth.getBlock("latest").timestamp + 100,
        transact={'from': sender}
    )

    assert minted_contract.getNFTState(token_id) == 5

    minted_contract.token_service_contract.buyToken(token_id, zero_address, transact={'from': to, 'value': 10 })

    assert minted_contract.token_service_contract.tokens__option__expires(token_id) == 0
    assert minted_contract.token_service_contract.tokens__option__buyer(token_id) == None
    assert minted_contract.token_service_contract.tokens__option__price(token_id) == 0
    assert minted_contract.token_service_contract.tokens__option__currency(token_id) == None

    assert minted_contract.getNFTOwner(token_id) == to
    # Go back to available state after buying
    assert minted_contract.getNFTState(token_id) == 1

    minted_contract.applyToken(token_id, token_call_contract.address, transact={'from': to})

    # Assert token is applied
    assert minted_contract.getNFTState(token_id) == 2
    assert minted_contract.getNFTTokenCall(token_id) == token_call_contract.address

    token_call_contract.docsSubmitted(token_id, transact={"from": sender})
    token_call_contract.userQualified(token_id, transact={"from": sender})
    token_call_contract.userRejected(token_id, transact={"from": sender})

    # Available after rejection
    assert minted_contract.getNFTState(token_id) == 1
    assert minted_contract.getNFTTokenCall(token_id) is None


def test_applied_state(w3, minted_contract, receiver_contract, token_call_contract, erc20_contract, assert_tx_failed):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[0]

    # Available state
    assert minted_contract.getNFTState(token_id) == 1
    # Sender is owner
    assert minted_contract.getNFTOwner(token_id) == sender

    minted_contract.applyToken(token_id, token_call_contract.address, transact={'from': sender})
    # Assert token is applied
    assert minted_contract.getNFTState(token_id) == 2
    assert minted_contract.getNFTTokenCall(token_id) == token_call_contract.address

    # Cannot sell an applied token
    assert_tx_failed(
        lambda: minted_contract.token_service_contract.sellToken(
            token_id,
            to,
            erc20_contract.address,
            10,
            w3.eth.getBlock("latest").timestamp + 100,
            transact={'from': sender}
        )
    )

    assert minted_contract.getNFTState(token_id) == 2
    minted_contract.removeToken(token_id, transact={'from': sender})

    # Back to available state after token withdrawal
    assert minted_contract.getNFTState(token_id) == 1
    assert minted_contract.getNFTTokenCall(token_id) is None


def test_processing_state(w3, minted_contract, receiver_contract, token_call_contract, erc20_contract, assert_tx_failed):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[0]

    # Available state
    assert minted_contract.getNFTState(token_id) == 1
    # Sender is owner
    assert minted_contract.getNFTOwner(token_id) == sender

    minted_contract.applyToken(token_id, token_call_contract.address, transact={'from': sender})
    # Assert token is applied
    assert minted_contract.getNFTState(token_id) == 2
    assert minted_contract.getNFTTokenCall(token_id) == token_call_contract.address

    token_call_contract.docsSubmitted(token_id, transact={"from": sender})
    assert minted_contract.getNFTState(token_id) == 3

    # Cannot sell an applied token
    assert_tx_failed(
        lambda: minted_contract.token_service_contract.sellToken(
            token_id,
            to,
            erc20_contract.address,
            10,
            w3.eth.getBlock("latest").timestamp + 100,
            transact={'from': sender}
        )
    )

    assert minted_contract.getNFTState(token_id) == 3
    minted_contract.removeToken(token_id, transact={'from': sender})

    # Back to available state after token withdrawal
    assert minted_contract.getNFTState(token_id) == 1
    assert minted_contract.getNFTTokenCall(token_id) is None


def test_approved_state(w3, minted_contract, receiver_contract, token_call_contract, erc20_contract, assert_tx_failed):
    sender = w3.eth.accounts[0]
    to = w3.eth.accounts[1]
    token_id = minted_contract.token_ids[0]

    # Available state
    assert minted_contract.getNFTState(token_id) == 1
    # Sender is owner
    assert minted_contract.getNFTOwner(token_id) == sender

    minted_contract.applyToken(token_id, token_call_contract.address, transact={'from': sender})

    # Assert token is applied
    assert minted_contract.getNFTState(token_id) == 2
    assert minted_contract.getNFTTokenCall(token_id) == token_call_contract.address

    token_call_contract.docsSubmitted(token_id, transact={"from": sender})
    assert minted_contract.getNFTState(token_id) == 3

    token_call_contract.userQualified(token_id, transact={"from": sender})
    assert minted_contract.getNFTState(token_id) == 4
    # Cannot sell an approved token
    assert_tx_failed(
        lambda: minted_contract.token_service_contract.sellToken(
            token_id,
            to,
            erc20_contract.address,
            10,
            w3.eth.getBlock("latest").timestamp + 100,
            transact={'from': sender}
        )
    )
    assert minted_contract.getNFTState(token_id) == 4

    # Can't withdraw an approved token
    assert_tx_failed(
        lambda: minted_contract.removeToken(token_id, transact={'from': sender})
    )

    assert minted_contract.getNFTState(token_id) == 4


def test_nf_token_must_be_minted_by_auction_only(w3, contract, zero_address, assert_tx_failed, get_contract):
    creator = w3.eth.accounts[0]
    sender = w3.eth.accounts[1]

    tx_hash = contract.createToken("test_create_token", True, transact={"from": creator})
    hex_token_id = w3.eth.getTransactionReceipt(tx_hash).logs[1].topics[1]
    token_type = int(hex_token_id.hex(), 0)
    with open("contracts/TokenService.vy") as f:
        contract_code = f.read()
        token_service_contract = get_contract(contract_code, contract.address, token_type)
    contract.setTokenService(token_service_contract.address, token_type, transact={"from": creator})

    mint_token_to = resize(
        w3.eth.accounts[1:4], MAX_BATCH_SIZE, default_value=zero_address
    )
    token_ids = [i for i in range(1, 10)]

    assert_tx_failed(lambda: contract.mintNonFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        transact={"from": sender},
    ))

    assert_tx_failed(lambda: contract.mintNonFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        transact={"from": creator},
    ))

    assert_tx_failed(lambda: contract.setMintTokenApproval(token_type, sender, True, transact={"from": sender}))

    contract.setMintTokenApproval(token_type, sender, True, transact={"from": creator})
    assert contract.isApprovedToMintToken(token_type, sender)

    contract.mintNonFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        transact={"from": sender},
    )

    assert all(
        contract.getNFTOwner(token_type | token_id) == to
        for to, token_id in zip(mint_token_to, token_ids)
        if to != zero_address
    )


def test_fungible_token_must_be_minted_by_creator_or_operator_only(w3, contract, zero_address, assert_tx_failed):
    creator = w3.eth.accounts[0]
    operator = w3.eth.accounts[1]
    sender = w3.eth.accounts[2]

    contract.setApprovalForAll(operator, True, transact={"from": creator})

    assert contract.isApprovedForAll(creator, operator)

    tx_hash = contract.createToken("test_create_token", False, transact={"from": creator})
    hex_token_id = w3.eth.getTransactionReceipt(tx_hash).logs[1].topics[1]
    token_type = int(hex_token_id.hex(), 0)

    mint_token_to = resize(
        w3.eth.accounts[1:4], MAX_BATCH_SIZE, default_value=zero_address
    )
    quantities = [10 for _ in range(20, 30)]

    assert_tx_failed(lambda: contract.mintFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        resize(quantities, MAX_BATCH_SIZE),
        transact={"from": sender},
    ))

    contract.mintFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        resize(quantities, MAX_BATCH_SIZE),
        transact={"from": creator},
    )

    contract.mintFungibleToken(
        token_type,
        resize(mint_token_to, MAX_BATCH_SIZE, default_value=zero_address),
        resize(quantities, MAX_BATCH_SIZE),
        transact={"from": operator},
    )

    assert all(
        contract.balanceOf(to, token_type) == 20
        for to in mint_token_to if to != zero_address
    )
