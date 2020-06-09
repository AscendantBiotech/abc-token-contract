struct Option:
    buyer: address
    price: uint256
    currency: address
    expires: timestamp

struct TCO:
    tokenCall: address
    docsSubmitted: bool
    userQualified: bool

struct Token:
    tid: uint256
    owner: address
    option: Option
    tco: TCO

struct Transaction:
    tid: uint256
    entry_state: int128
    exit_state: int128



contract ERC20Currency:
    def balanceOf(_address: address) -> uint256: constant
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: modifying

contract ERC1155:
    def updateBalanceOnNFTTransfer(_tokenId: uint256, _tokenType: uint256, _from: address, _to: address): modifying
    def isApprovedToMintToken(_tokenTypeId: uint256, _sender: address) -> bool: constant
    def getNonFungibleBaseType(_tokenId: uint256) -> uint256: constant

contract TokenCall:
    def onRequestFromTokenCall() -> bytes32: constant
    def applyToken(_tokenId: uint256): modifying
    def removeToken(_tokenId: uint256): modifying


# blockchain log events
EntryStateLog: event({_tid: uint256, _entry_state: int128, _exit_state: int128, _event: int128})
ExitStateLog: event({_tid: uint256, _exit_state: int128})
StateCount: event({_state_count: int128})
UnAuthorizedEventRequest: event({_event: int128, _origin_address: address, _auth_address: address})


# This is needed to check the sending contract is TokenCall
# keccak256("onRequestFromTokenCall()") 
FROM_TOKEN_CALL: constant(bytes32) = 0x095332897a16faaf295be718bfc48721e7de9e87ff680ab2dd0179fb892881ea


## STATES ##
UNKNOWN: constant(int128) = 0
AVAILABLE: constant(int128) = 1
EAPAPPLIED: constant(int128) = 2
EAPPROCESSING: constant(int128) = 3
EAPAPROVED: constant(int128) = 4
OPTIONED: constant(int128) = 5
BURNED: constant(int128) = 6


## EVENTS ##
AO_MINT_TOKEN: constant(int128) = 0
TO_APPLY_TOKEN: constant(int128) = 1
TO_REMOVE_TOKEN: constant(int128) = 2
TO_SELL_TOKEN: constant(int128) = 3
TCO_USER_REJECTED: constant(int128) = 4
TCO_DOCS_SUBMITTED: constant(int128) = 5
TCO_USER_QUALIFIED: constant(int128) = 6
TCO_FINALIZE: constant(int128) = 7
WO_BUY_TOKEN: constant(int128) = 8


StateTransitionMatrix: constant(int128[7][9]) = \
	[	[AVAILABLE,0,0,0,0,0,0],	# AO_MINT_TOKEN
		[0,EAPAPPLIED,0,0,0,0,0],	# TO_APPLY_TOKEN
		[0,0,AVAILABLE,AVAILABLE,0,0,0], # TO_REMOVE_TOKEN
		[0,OPTIONED,0,0,0,0,0],	# TO_SELL_TOKEN
		[0,0,AVAILABLE,AVAILABLE,AVAILABLE,0,0], # TCO_USER_REJECTED
		[0,0,EAPPROCESSING,0,0,0,0], # TCO_DOCS_SUBMITTED
		[0,0,0,EAPAPROVED,0,0,0], # TCO_USER_QUALIFIED
		[0,0,0,0,BURNED,0,0], # TCO_FINALIZE
		[0,0,0,0,0,AVAILABLE,0], # WO_BUY_TOKEN
	]


nextTid: public(uint256)
tokens: public(map(uint256,Token))
contract_owner: address
erc1155_addr: address
token_type_id: uint256

# Put our array into persistent storage (Cheaper gas-wise)
# Declare it here, initialize inside __init__
StateTransition: int128[7][9]

# _getState covers this one completely.
# @private
# @constant
# def _isAvailableState(token: Token) -> int128:
#     # token.tid != 0
#     # token.owner != ZERO_ADDRESS
#     # token.tco.tokenCall == ZERO_ADDRESS
#     # token.option.buyer == ZERO_ADDRESS
#     if  token.option.buyer == ZERO_ADDRESS :
#         return AVAILABLE
#     return UNKNOWN

@private
@constant
def _isEAPAppliedState(_token: Token) -> int128:    
    # token.tid != 0
    # token.owner != ZERO_ADDRESS
    # token.tco.tokenCall != ZERO_ADDRESS
    # token.option.buyer == ZERO_ADDRESS
    if  _token.tco.docsSubmitted == False and \
        _token.tco.userQualified == False : 
        return EAPAPPLIED
    return UNKNOWN

@private
@constant
def _isEAPProcessingState(_token: Token) -> int128:
    # token.tid != 0
    # token.owner != ZERO_ADDRESS
    # token.tco.tokenCall != ZERO_ADDRESS
    # token.option.buyer == ZERO_ADDRESS
    if  _token.tco.docsSubmitted == True and \
        _token.tco.userQualified == False : 
        return EAPPROCESSING
    return UNKNOWN

@private
@constant
def _isEAPApprovedState(_token: Token) -> int128:
    # token.tid != 0
    # token.owner != ZERO_ADDRESS
    # token.tco.tokenCall != ZERO_ADDRESS
    # token.option.buyer == ZERO_ADDRESS
    if  _token.tco.docsSubmitted == True and \
        _token.tco.userQualified == True :
        return EAPAPROVED
    return UNKNOWN   

@private
@constant
def _isOptionedState(_token: Token) -> int128:
    # token.tid != 0
    # token.owner != ZERO_ADDRESS
    # token.tco.tokenCall == ZERO_ADDRESS:
    if  _token.option.buyer != ZERO_ADDRESS:
        if _token.option.expires >= block.timestamp :
            return OPTIONED
        else:
            # Option has expired - we're really available.
            return AVAILABLE

    return UNKNOWN     

# _getState covers this one completely.
# @private
# @constant
# def _isBurnedState(token: Token) -> int128:
#     # token.tid != 0
#     # token.owner == ZERO_ADDRESS
#     return BURNED

@private
@constant
def _getState(_token: Token) -> int128:
    # Guarantees the Token is in one and only one valid state.
    if _token.tid == 0: return UNKNOWN
    count: int128 = 0
    result: int128 = UNKNOWN
    t: int128 = UNKNOWN
    if _token.owner == ZERO_ADDRESS:
        #t = self._isBurnedState(_token)
        #if t != UNKNOWN: 
        #    count += 1
        #    result = t
        count += 1
        result = BURNED
    elif _token.option.buyer == ZERO_ADDRESS:
        if _token.tco.tokenCall == ZERO_ADDRESS:        
            # t = self._isAvailableState(_token)
            # if t != UNKNOWN: 
            #     count += 1
            #     result = t
            count += 1
            result = AVAILABLE
        else:
            t = self._isEAPAppliedState(_token)
            if t != UNKNOWN: 
                count += 1
                result = t
            t = self._isEAPProcessingState(_token)
            if t != UNKNOWN: 
                count += 1
                result = t
            t = self._isEAPApprovedState(_token)
            if t != UNKNOWN: 
                count += 1
                result = t
    elif _token.option.buyer != ZERO_ADDRESS:
        if _token.tco.tokenCall == ZERO_ADDRESS: 
            t = self._isOptionedState(_token)
            if t != UNKNOWN: 
                count += 1
                result = t            

    if count != 1:
        return UNKNOWN
    return result


@private
@constant
def _isState(_state: int128, _token: Token) -> bool:
   return self._getState(_token) == _state


@private
@constant
def preStateTransition(_sender: address, _tid: uint256, _event: int128) -> Transaction:
    _token : Token = self.tokens[_tid]
    # Ensure our transaction is being called from a wallet authorized to perform the transaction.
    if _event == AO_MINT_TOKEN:
        # Minting persmission should be determined on the ERC contact side
        token_type: uint256 = ERC1155(self.erc1155_addr).getNonFungibleBaseType(_tid)
        is_approved_to_mint: bool = ERC1155(self.erc1155_addr).isApprovedToMintToken(token_type, _sender)
        if not is_approved_to_mint:
            log.UnAuthorizedEventRequest(_event, _sender, ZERO_ADDRESS)
        assert is_approved_to_mint

    elif _event in [TO_APPLY_TOKEN, TO_REMOVE_TOKEN, TO_SELL_TOKEN]:
        if _sender != _token.owner:
            log.UnAuthorizedEventRequest(_event, _sender, _token.owner)
        assert _sender == _token.owner

    elif _event in [TCO_DOCS_SUBMITTED, TCO_USER_REJECTED, TCO_USER_QUALIFIED, TCO_FINALIZE]:
        if _sender != _token.tco.tokenCall:
            log.UnAuthorizedEventRequest(_event, _sender, _token.tco.tokenCall)
        assert _sender == _token.tco.tokenCall
        assert TokenCall(_sender).onRequestFromTokenCall() == FROM_TOKEN_CALL

    elif _event == WO_BUY_TOKEN:
        if _sender != _token.option.buyer:
            log.UnAuthorizedEventRequest(_event, _sender, _token.option.buyer)  
        assert _sender == _token.option.buyer
    else:
        # Not a legal event at all.
        log.UnAuthorizedEventRequest(_event, _sender, ZERO_ADDRESS) 
        assert False

    _entry_state : int128 = self._getState(_token)
    _exit_state : int128 = self.StateTransition[_event][_entry_state]
    ## DEBUG - remark this out to see expected state transition in log output.
    assert _exit_state != UNKNOWN
    
    xtrans : Transaction = Transaction({tid: _tid, entry_state : _entry_state, exit_state : _exit_state})
    log.EntryStateLog(_tid, _entry_state, xtrans.exit_state, _event)
    return xtrans


@private
@constant
def postStateTransition(_xtrans: Transaction):
    log.ExitStateLog(_xtrans.tid, _xtrans.exit_state)
    token : Token = self.tokens[_xtrans.tid]
    ## DEBUG - remark this out to see log output.
    assert self._isState(_xtrans.exit_state, token)


@public
def __init__(
        _erc1155_addr: address,
        _token_type: uint256
    ):
    # The necessity for copying the matrix will be fixed with this
    # issue: https://github.com/ethereum/vyper/issues/1915
    self.StateTransition = StateTransitionMatrix
    self.contract_owner = msg.sender
    self.erc1155_addr = _erc1155_addr
    self.token_type_id = _token_type
    self.nextTid = _token_type + 1


@public 
@constant
def get_nextTid() -> uint256:
    return self.nextTid


@public
@constant
def get_state(_tid: uint256) -> int128:
    token: Token = self.tokens[_tid]
    return self._getState(token)


@public
@constant
def get_option(_tid: uint256) -> Option:
    token : Token = self.tokens[_tid]
    return token.option


@public
def mintToken(_to_owner: address, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    xtrans : Transaction = self.preStateTransition(_tx_sender, self.nextTid, AO_MINT_TOKEN)
    token: Token = self.tokens[xtrans.tid]

    # Assert the new token sequence number will not overflow
    prev_token_seq_number: uint256 = bitwise_xor(self.token_type_id, self.nextTid - 1)
    new_token_seq_number: uint256 = bitwise_xor(self.token_type_id, self.nextTid)
    assert new_token_seq_number > prev_token_seq_number

    token.tid = self.nextTid
    token.owner = _to_owner

    self.nextTid += 1

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public
def applyToken(_tid: uint256, tokenCall: address, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    assert TokenCall(tokenCall).onRequestFromTokenCall() == FROM_TOKEN_CALL
    xtrans : Transaction = self.preStateTransition(_tx_sender, _tid, TO_APPLY_TOKEN)
    token: Token = self.tokens[_tid]

    token.tco.tokenCall = tokenCall
    token.tco.docsSubmitted = False
    token.tco.userQualified = False

    TokenCall(tokenCall).applyToken(_tid)

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public 
def removeToken(_tid: uint256, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    xtrans : Transaction = self.preStateTransition(_tx_sender, _tid, TO_REMOVE_TOKEN)  
    token: Token = self.tokens[_tid]    

    TokenCall(token.tco.tokenCall).removeToken(_tid)

    token.tco.tokenCall = ZERO_ADDRESS
    token.tco.docsSubmitted = False
    token.tco.userQualified = False

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public
def sellToken(_tid: uint256, _buyer: address, _currency: address, _price: uint256, _expires: timestamp):
    xtrans : Transaction = self.preStateTransition(msg.sender, _tid, TO_SELL_TOKEN)  
    token: Token = self.tokens[_tid]  

    # Any other tests we can do for a valid wallet address??
    assert _buyer != ZERO_ADDRESS

    # Any tests we can do for a non-zero address to check for legitimate ERC-20 contract?

    # Assure that expiration is no more than 10 days out from now.
    assert _expires <= block.timestamp + (3600 * 24 * 10)

    token.option = Option({ buyer: _buyer,
                            price: _price,
                            currency: _currency,
                            expires: _expires })

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public 
@payable
def buyToken(_tid: uint256, _currency: address):
    xtrans : Transaction = self.preStateTransition(msg.sender, _tid, WO_BUY_TOKEN)  
    token: Token = self.tokens[_tid]  
    previousOwner: address = token.owner

    option: Option = token.option

    assert msg.sender == option.buyer

    assert option.expires > block.timestamp

    if option.currency == _currency:
        if option.currency == ZERO_ADDRESS:
            # Paying in ETH.
            assert msg.value >= option.price

            # Be sure and forward the money to the current token owner!
            send(token.owner, msg.value)

            # Sold!
            token.owner = msg.sender
        else:
            # Paying in some ERC20 token. Ensure the contract actually is honest.
            buyer_balance: uint256 = ERC20Currency(option.currency).balanceOf(option.buyer)
            seller_balance: uint256 = ERC20Currency(option.currency).balanceOf(token.owner)
            ERC20Currency(option.currency).transferFrom(option.buyer, token.owner, option.price)
            assert buyer_balance - option.price == ERC20Currency(option.currency).balanceOf(option.buyer)
            assert seller_balance + option.price == ERC20Currency(option.currency).balanceOf(token.owner)

            # Sold!
            token.owner = msg.sender
    else:
        # Not paying in a valid currency.
        assert False

    ERC1155(self.erc1155_addr).updateBalanceOnNFTTransfer(token.tid, self.token_type_id, previousOwner, token.owner)

    # Did we make the sale?
    #assert token.owner == msg.sender

    token.option = Option({ buyer: ZERO_ADDRESS,
                            price: 0,
                            currency: ZERO_ADDRESS,
                            expires: 0 })

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public 
def userRejected(_tid: uint256, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    xtrans : Transaction = self.preStateTransition(_tx_sender, _tid, TCO_USER_REJECTED)
    token: Token = self.tokens[_tid]

    token.tco.tokenCall = ZERO_ADDRESS
    token.tco.docsSubmitted = False
    token.tco.userQualified = False

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public 
def docsSubmitted(_tid: uint256, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    xtrans : Transaction = self.preStateTransition(_tx_sender, _tid, TCO_DOCS_SUBMITTED)
    token: Token = self.tokens[_tid]

    token.tco.docsSubmitted = True

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public 
def userQualified(_tid: uint256, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    xtrans : Transaction = self.preStateTransition(_tx_sender, _tid, TCO_USER_QUALIFIED)
    token: Token = self.tokens[_tid]

    token.tco.userQualified = True

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public 
def finalize(_tid: uint256, _tx_sender: address):
    assert msg.sender == self.erc1155_addr
    xtrans : Transaction = self.preStateTransition(_tx_sender, _tid, TCO_FINALIZE)
    token: Token = self.tokens[_tid]

    token.owner = ZERO_ADDRESS

    self.tokens[xtrans.tid] = token
    self.postStateTransition(xtrans)


@public
def setOwner(_tokenId: uint256, _newOwner: address):
    assert msg.sender == self.erc1155_addr
    self.tokens[_tokenId].owner = _newOwner
