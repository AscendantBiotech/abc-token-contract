##################### CONSTANTS #####################
CONTRACT_VERSION : constant(uint256) = 1000002  # Update this as behavior changes.
# 1000001 - initial working token call prototype
# 1000002 - updated state machine implementation

# keccak256("onRequestFromTokenCall()")
FROM_TOKEN_CALL: constant(bytes32) = 0x095332897a16faaf295be718bfc48721e7de9e87ff680ab2dd0179fb892881ea
HOUR: constant(timedelta) = 3600

# FOR ASC BATCH OPERATIONS #
MAX_BATCH_SIZE: constant(uint256) = 100

# SKIP LIST CONFIGURATION #
BASE_TOKEN_ID: constant(uint256) = 0
DEEPEST_LEVEL: constant(int128) = 0
MAX_TOKENS: constant(uint256) = 5000000
MAX_QUEUE_SIZE: constant(uint256) = 5000000 * 10
MAX_LEVEL: constant(int128) = 6
PROMOTION_CONSTANT: constant(int128) = 3  # promote probability = 2 ^ PROMOTION_CONSTANT 
UNPROMOTE_PROB: constant(int128) = (2 ** 3) - 1

PREFERRED_TOKEN_TYPE: constant(int128) = 0
REGULAR_TOKEN_TYPE: constant(int128) = 1


# STATE MACHINE #
# States #
UNKNOWN: constant(int128) = 0
PENDING: constant(int128) = 1
PAUSED: constant(int128) = 2
OPEN: constant(int128) = 3
CLOSED: constant(int128) = 4
FINISHED: constant(int128) = 5

## Events ##
TCO_PAUSE_TC: constant(int128) = 0
TCO_UNPAUSE_TC: constant(int128) = 1
# 2 finishing events are needed, because the exit state can vary for the single event based on a condition
TCO_FINISH_TC_REMAINING: constant(int128) = 2
TCO_FINISH_TC_EMPTY: constant(int128) = 3
TCO_DOCS_SUBMITTED: constant(int128) = 4
TCO_USER_QUALIFIED: constant(int128) = 5
TCO_USER_REJECTED: constant(int128) = 6
TO_APPLY_TOKEN: constant(int128) = 7
TO_REMOVE_TOKEN: constant(int128) = 8


STATE_TRANSITION_MATRIX: constant(int128[6][9]) = \
    [   [0,PAUSED,0,PAUSED,0,0], # TCO_PAUSE_TC
        [0,PENDING,0,OPEN,0,0],  # TCO_UNPAUSE_TC
        [0,0,0,0,CLOSED,0],      # TCO_FINISH_TC_REMAINING
        [0,0,0,0,FINISHED,0],    # TCO_FINISH_TC_EMPTY
        [0,0,0,OPEN,CLOSED,0],   # TCO_DOCS_SUBMITTED
        [0,0,0,OPEN,CLOSED,0],   # TCO_USER_QUALIFIED
        [0,0,0,OPEN,CLOSED,0],   # TCO_USER_REJECTED
        [0,0,0,OPEN,0,0],        # TO_APPLY_TOKEN
        [0,0,0,OPEN,0,0],        # TO_REMOVE_TOKEN
    ]



##################### STRUCTS #####################
struct TokenApplication:
    tokenId: uint256
    prevToken: uint256
    nextToken: uint256

struct TokenList:
    tokenTypeId: uint256
    firstToken: uint256
    tokenCount: uint256
    levels: map(uint256, TokenApplication)[6]

struct Transaction:
    entry_state: int128
    exit_state: int128


##################### EXTERNAL CONTRACTS #####################
contract ASCToken:
    def isNonFungible(_tokenId: uint256) -> bool: constant
    def isFungible(_tokenId: uint256) -> bool: constant
    def getNonFungibleIndex(_tokenId: uint256) -> uint256: constant
    def getNonFungibleBaseType(_tokenId: uint256) -> uint256: constant
    def isNonFungibleBaseType(_tokenId: uint256) -> bool: constant
    def isNonFungibleItem(_tokenId: uint256) -> bool: constant
    def safeTransferFrom(_from: address, _to: address, _tokenId: uint256, _value: uint256, _data: bytes[1024]): modifying
    def safeBatchTransferFrom(_from: address, _to: address, _tokenIds: uint256[100], _values: uint256[100], _data: bytes[1024]): modifying
    def balanceOf(_owner: address, _tokenId: uint256) -> uint256: constant
    def balanceOfBatch(_owners: address[100], _tokenIds: uint256[100]) -> uint256[100]: constant
    def setApprovalForAll(_operator: address, _approved: bool): modifying
    def approve(_spender: address, _tokenId: uint256, _currentValue: uint256, _value: uint256): modifying
    def isApprovedForAll(_owner: address, _operator: address) -> bool: constant
    def createToken(_uri: string[256], _isNonFungible: bool) -> uint256: modifying
    def mintNonFungibleToken(_tokenTypeId: uint256, _to: address[100], _indexes: uint256[100]): modifying
    def mintFungibleToken(_tokenId: uint256, _to: address[100], _quantities: uint256[100]): modifying
    def setURI(_uri: string[256], _id: uint256): modifying
    def tokenCallApprove(_tokenCall: address, _tokenId: uint256): modifying
    def applyToken(_tokenId: uint256): modifying
    def removeToken(_tokenId: uint256): modifying
    def userRejected(_tokenId: uint256): modifying
    def finalize(_tokenId: uint256): modifying
    def owners(arg0: uint256) -> address: constant
    def tokenTypes__tokenTypeId(arg0: uint256) -> uint256: constant
    def tokenTypes__uri(arg0: uint256) -> string[256]: constant
    def tokenTypes__creator(arg0: uint256) -> address: constant
    def tokenTypes__mintedQty(arg0: uint256) -> uint256: constant
    def owner(arg0: uint256) -> address: constant
    def docsSubmitted(_tid: uint256): modifying
    def userQualified(_tid: uint256): modifying
    def nonce() -> uint256: constant
    def tokenServices(tokenType: uint256) -> address: constant


##################### BLOCKCHAIN LOG EVENTS #####################
TokenApply: event({_tokenId: indexed(uint256), _tokenOwner: address})
TokenWithdraw: event({_tokenId: indexed(uint256), _tokenOwner: address})
TokenReject: event({_tokenId: indexed(uint256)})
TokenDataSubmitted: event({_tokenId: indexed(uint256)})
TokenUserQualified: event({_tokenId: indexed(uint256)})
TokenCallPause: event({})
TokenCallUnpause: event({})
TokenBatchDataSubmitted: event({_tokenIds: uint256[MAX_BATCH_SIZE]})
TokenBatchUserQualified: event({_tokenIds: uint256[MAX_BATCH_SIZE]})
TokenCallFinalize: event({_size: uint256})
EntryStateLog: event({_entry_state: int128, _exit_state: int128, _event: int128})
ExitStateLog: event({_exit_state: int128})
StateCount: event({_state_count: int128})
UnAuthorizedEventRequest: event({_event: int128, _origin_address: address, _auth_address: address})



##################### STORAGES #####################
tokenContract: address

maxTokens: public(uint256)
maxPreferredTokens: public(uint256)

contractOwner: address
paused: public(bool)
startDate: public(timestamp)
endDate: public(timestamp)

tokenLists: public(TokenList[2])
StateTransition: int128[6][9]


##################### CONSTANT FUNCTIONS #####################
@public
@constant
def contractVersion() -> uint256:
    return CONTRACT_VERSION


@public
@constant
def onRequestFromTokenCall() -> bytes32:
    return FROM_TOKEN_CALL



# Skip list functions #
@public
@constant
def getDeepestLevel() -> int128:
    return DEEPEST_LEVEL


@private
@constant
def tokensRemaining() -> bool:
    return self.tokenLists[PREFERRED_TOKEN_TYPE].tokenCount == 0 and \
           self.tokenLists[REGULAR_TOKEN_TYPE].tokenCount == 0


@private
@constant
def findClosestHigherValueToken(_type: int128, _level: int128, _start: uint256, _tokenId: uint256) -> uint256:
    tokenId: uint256 = _start
    for _ in range(MAX_QUEUE_SIZE):
        token: TokenApplication = self.tokenLists[_type].levels[_level][tokenId]
        if token.nextToken == 0 or token.nextToken >= _tokenId:
            break
        tokenId = token.nextToken
    return tokenId


@private
@constant
def getLevel(_tokenId: uint256, _sender: address) -> int128:
    level: int128 = 0
    xor_result: uint256 = bitwise_xor(bitwise_xor(convert(_sender, uint256), _tokenId), convert(block.prevhash, uint256))
    random: uint256 = convert(keccak256(convert(xor_result, bytes32)), uint256)
    for i in range(MAX_LEVEL - 1):
        if bitwise_and(random, shift(15, PROMOTION_CONSTANT * i)) == 0:
            level += 1
        else:
            break

    return level


@private
@constant
def _getTokenTypeIndex(_tokenId: uint256) -> int128:
    tokenTypeId: uint256 = ASCToken(self.tokenContract).getNonFungibleBaseType(_tokenId)
    tokenTypeIndex: int128 = 0

    if tokenTypeId == self.tokenLists[PREFERRED_TOKEN_TYPE].tokenTypeId:
        tokenTypeIndex = PREFERRED_TOKEN_TYPE
    elif tokenTypeId == self.tokenLists[REGULAR_TOKEN_TYPE].tokenTypeId:
        tokenTypeIndex = REGULAR_TOKEN_TYPE
    else:
        assert False, 'Invalid token type!'

    return tokenTypeIndex


@public
def getTokenTypeIndex(_tokenId: uint256) -> int128:
    return self._getTokenTypeIndex(_tokenId)



# State Machine functions #
@private
@constant
def _isPausedState() -> int128:
    if self.paused:
        if  block.timestamp >= self.startDate and \
            block.timestamp >= self.endDate:
            # Token Call has expired #
            return CLOSED
        else:
            return PAUSED
    return UNKNOWN


# Ensure Token Call is in one state at a moment of time #
@private
@constant
def _getState() -> int128:
    count: int128 = 0
    temp_state: int128 = UNKNOWN
    result: int128 = UNKNOWN

    if self.contractOwner == ZERO_ADDRESS:
        if not self.tokensRemaining():
            count += 1
            result = FINISHED
    elif self.paused:
        temp_state = self._isPausedState()
        if temp_state != UNKNOWN:
            count += 1
            result = temp_state
    elif not self.paused:
        if block.timestamp >= self.startDate:
            if block.timestamp < self.endDate:
                count += 1
                result = OPEN
            else:
                count += 1
                result = CLOSED
        else:
            if block.timestamp < self.endDate:
                count += 1
                result = PENDING

    log.StateCount(count)
    if count != 1:
        return UNKNOWN

    return result


@public
@constant
def getState() -> int128:
    return self._getState()


@private
@constant
def _isState(_state: int128) -> bool:
   return self._getState() == _state


@private
@constant
def isAuthorizedForTransition(_event: int128, _sender: address, _tokenTypeId: uint256) -> bool:
    if _event in [TCO_PAUSE_TC,TCO_FINISH_TC_REMAINING,TCO_UNPAUSE_TC,
                  TCO_FINISH_TC_EMPTY,TCO_DOCS_SUBMITTED,
                  TCO_USER_QUALIFIED,TCO_USER_REJECTED]:
        if _sender != self.contractOwner:
            log.UnAuthorizedEventRequest(_event, _sender, self.contractOwner)
        return _sender == self.contractOwner
    elif _event in [TO_APPLY_TOKEN,TO_REMOVE_TOKEN]:
        tokenService: address = ASCToken(self.tokenContract).tokenServices(_tokenTypeId)
        if _sender != tokenService:
            log.UnAuthorizedEventRequest(_event, _sender, self.tokenContract)
        return _sender == tokenService
    else:
        log.UnAuthorizedEventRequest(_event, _sender, ZERO_ADDRESS)
        return False


@private
@constant
def preStateTransition(_sender: address, _event: int128, _tokenTypeId: uint256 = 0) -> Transaction:
    assert self.isAuthorizedForTransition(_event, _sender, _tokenTypeId)
    co: address = self.contractOwner
    _entry_state : int128 = self._getState()
    _exit_state : int128 = self.StateTransition[_event][_entry_state]

    assert _exit_state != UNKNOWN

    log.EntryStateLog(_entry_state, _exit_state, _event)

    return Transaction({ entry_state: _entry_state,
                         exit_state:  _exit_state  })


@private
@constant
def postStateTransition(_xtrans: Transaction):
    log.ExitStateLog(_xtrans.exit_state)
    assert self._isState(_xtrans.exit_state)



##################### MODIFYING FUNCTIONS #####################

@private
def insertToken(_tokenTypeIndex: int128, _tokenId: uint256, _sender: address):
    assert _tokenId != 0

    cursorTokenId: uint256 = 0
    height: int128 = self.getLevel(_tokenId, _sender)

    for i in range(MAX_LEVEL):
        level: int128 = MAX_LEVEL - i - 1
        cursorTokenId = self.findClosestHigherValueToken(
            _tokenTypeIndex,
            level,
            cursorTokenId,
            _tokenId
        )

        if level <= height:
            nextToken: uint256 = self.tokenLists[_tokenTypeIndex].levels[level][cursorTokenId].nextToken
            newToken: TokenApplication = TokenApplication({
                tokenId: _tokenId,
                prevToken: cursorTokenId,
                nextToken: nextToken,
            })

            if nextToken != 0:
                self.tokenLists[_tokenTypeIndex].levels[level][nextToken].prevToken = _tokenId
            self.tokenLists[_tokenTypeIndex].levels[level][cursorTokenId].nextToken = _tokenId
            self.tokenLists[_tokenTypeIndex].levels[level][_tokenId] = newToken

    if self.tokenLists[_tokenTypeIndex].firstToken == 0 or self.tokenLists[_tokenTypeIndex].firstToken > _tokenId:
        self.tokenLists[_tokenTypeIndex].firstToken = _tokenId

    self.tokenLists[_tokenTypeIndex].tokenCount += 1



@private
def _removeToken(_tokenTypeIndex: int128, _tokenId: uint256):
    assert _tokenId != 0

    nextToken: uint256 = self.tokenLists[_tokenTypeIndex].levels[DEEPEST_LEVEL][_tokenId].nextToken

    for i in range(MAX_LEVEL):
        level: int128 = MAX_LEVEL -i - 1
        token: TokenApplication = self.tokenLists[_tokenTypeIndex].levels[level][_tokenId]
        if token.tokenId == 0:
            continue
        self.tokenLists[_tokenTypeIndex].levels[level][token.prevToken].nextToken = token.nextToken
        self.tokenLists[_tokenTypeIndex].levels[level][token.nextToken].prevToken = token.prevToken
        self.tokenLists[_tokenTypeIndex].levels[level][_tokenId] = TokenApplication({
                tokenId: 0,
                prevToken: 0,
                nextToken: 0,
            })

    self.tokenLists[_tokenTypeIndex].tokenCount -= 1

    if self.tokenLists[_tokenTypeIndex].firstToken == _tokenId:
        self.tokenLists[_tokenTypeIndex].firstToken = nextToken


@public
def __init__(
    _tokenContract: address,
    _preferredToken: uint256,
    _regularToken: uint256,
    _maxPreferredTokens: uint256,
    _maxTokens: uint256,
    _startDate: timestamp,
    _endDate: timestamp
):
    """
    _tokenContract - address of token contract.

    _regularTokenType - type id of regular ABC token.

    _preferredTokenType - type id of preferred ABC token.

    _maxPreferredTokens - maximum number of preferred tokens that the token call can accept.

    _maxTokens - maximum number of tokens for both regular and preferred type that the token call can accept.

    _startDate - the datetime when the token call can accept tokens.

    _endDate - the datetime when the token call ends.
    """

    assert _maxTokens <= MAX_TOKENS
    assert _maxPreferredTokens <= _maxTokens
    assert _startDate < _endDate
    assert block.timestamp < _endDate

    self.tokenContract = _tokenContract

    self.tokenLists[PREFERRED_TOKEN_TYPE].tokenTypeId = _preferredToken
    self.tokenLists[REGULAR_TOKEN_TYPE].tokenTypeId = _regularToken

    self.maxPreferredTokens = _maxPreferredTokens
    self.maxTokens = _maxTokens

    self.contractOwner = msg.sender

    self.startDate = _startDate
    self.endDate = _endDate

    self.StateTransition = STATE_TRANSITION_MATRIX


@public
def applyToken(_tokenId: uint256):
    tokenTypeId: uint256 = ASCToken(self.tokenContract).getNonFungibleBaseType(_tokenId)
    tokenTypeIndex: int128 = 0

    xtrans: Transaction = self.preStateTransition(msg.sender, TO_APPLY_TOKEN, tokenTypeId)

    if tokenTypeId == self.tokenLists[PREFERRED_TOKEN_TYPE].tokenTypeId:
        tokenTypeIndex = PREFERRED_TOKEN_TYPE
    elif tokenTypeId == self.tokenLists[REGULAR_TOKEN_TYPE].tokenTypeId:
        tokenTypeIndex = REGULAR_TOKEN_TYPE
    else:
        assert False, 'Invalid token type!'

    self.insertToken(tokenTypeIndex, _tokenId, msg.sender)
    log.TokenApply(_tokenId, msg.sender)

    self.postStateTransition(xtrans)


@public
def removeToken(_tokenId: uint256):
    tokenTypeId: uint256 = ASCToken(self.tokenContract).getNonFungibleBaseType(_tokenId)
    xtrans: Transaction = self.preStateTransition(msg.sender, TO_REMOVE_TOKEN, tokenTypeId)

    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)
    self._removeToken(tokenTypeIndex, _tokenId)
    log.TokenWithdraw(_tokenId, msg.sender)

    self.postStateTransition(xtrans)


@public
def userRejected(_tokenId: uint256):
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_USER_REJECTED)

    ASCToken(self.tokenContract).userRejected(_tokenId)
    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)
    self._removeToken(tokenTypeIndex, _tokenId)
    log.TokenReject(_tokenId)

    self.postStateTransition(xtrans)


@public
def pause():
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_PAUSE_TC)

    self.paused = True
    log.TokenCallPause()

    self.postStateTransition(xtrans)


@public
def unPause():
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_UNPAUSE_TC)

    self.paused = False
    log.TokenCallUnpause()

    self.postStateTransition(xtrans)


@private
def _docsSubmitted(_tokenId: uint256):
    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)
    assert self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][_tokenId].tokenId != 0

    ASCToken(self.tokenContract).docsSubmitted(_tokenId)
    log.TokenDataSubmitted(_tokenId)


@private
def _userQualified(_tokenId: uint256):
    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)
    assert self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][_tokenId].tokenId != 0

    ASCToken(self.tokenContract).userQualified(_tokenId)
    log.TokenUserQualified(_tokenId)


@public
def docsSubmitted(_tokenId: uint256):
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_DOCS_SUBMITTED)

    self._docsSubmitted(_tokenId)

    self.postStateTransition(xtrans)


@public
def userQualified(_tokenId: uint256):
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_USER_QUALIFIED)

    self._userQualified(_tokenId)

    self.postStateTransition(xtrans)


@public
def docSubmittedBatch(_tokenIds: uint256[MAX_BATCH_SIZE]):
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_DOCS_SUBMITTED)

    for i in range(MAX_BATCH_SIZE):
        tokenId: uint256 = _tokenIds[i]
        if tokenId == 0:
            continue
        self._docsSubmitted(tokenId)

    log.TokenBatchDataSubmitted(_tokenIds)

    self.postStateTransition(xtrans)


@public
def userQualifiedBatch(_tokenIds: uint256[MAX_BATCH_SIZE]):
    xtrans: Transaction = self.preStateTransition(msg.sender, TCO_USER_QUALIFIED)

    for i in range(MAX_BATCH_SIZE):
        tokenId: uint256 = _tokenIds[i]
        if tokenId == 0:
            continue
        self._userQualified(tokenId)

    log.TokenBatchUserQualified(_tokenIds)

    self.postStateTransition(xtrans)


@public
def finalize(_size: uint256):
    _event: int128 = TCO_FINISH_TC_EMPTY
    if (self.tokenLists[PREFERRED_TOKEN_TYPE].tokenCount + self.tokenLists[REGULAR_TOKEN_TYPE].tokenCount) > _size:
        _event = TCO_FINISH_TC_REMAINING


    opCounts: uint256[2] = [0,0]
    EapLimits: uint256[2] = [self.maxPreferredTokens, self.maxTokens]
    tokenId: uint256 = 0
    token: TokenApplication = TokenApplication({
        tokenId: 0,
        prevToken: 0,
        nextToken: 0
    })

    # If assertion are BEFORE variable declarations - transaction fails immediately
    xtrans: Transaction = self.preStateTransition(msg.sender, _event)
    assert _size > 0, 'Op size must greater than zero'

    for tokenTypeIndex in [PREFERRED_TOKEN_TYPE, REGULAR_TOKEN_TYPE]:
        if self.tokenLists[tokenTypeIndex].tokenCount > 0:
            tokenId = self.tokenLists[tokenTypeIndex].firstToken
            for _ in range(MAX_BATCH_SIZE):
                if tokenId == 0 or opCounts[0] + opCounts[1] >= _size:
                    break

                token = self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][tokenId]
                
                if (EapLimits[tokenTypeIndex] > 0):
                    ASCToken(self.tokenContract).finalize(tokenId)

                    if tokenTypeIndex == PREFERRED_TOKEN_TYPE:
                        EapLimits[REGULAR_TOKEN_TYPE] -= 1
                    EapLimits[tokenTypeIndex] -= 1
                else:
                    ASCToken(self.tokenContract).userRejected(tokenId)

                for level in range(MAX_LEVEL):
                    if token.tokenId != 0:
                        self.tokenLists[tokenTypeIndex].levels[level][token.nextToken].prevToken = 0
                        self.tokenLists[tokenTypeIndex].levels[level][tokenId] = TokenApplication({
                            tokenId: 0,
                            prevToken: 0,
                            nextToken: 0,
                        })

                tokenId = token.nextToken
                opCounts[tokenTypeIndex] += 1

        self.tokenLists[tokenTypeIndex].firstToken = tokenId
        self.tokenLists[tokenTypeIndex].tokenCount -= opCounts[tokenTypeIndex]

    self.maxPreferredTokens = EapLimits[PREFERRED_TOKEN_TYPE]
    self.maxTokens = EapLimits[REGULAR_TOKEN_TYPE]

    log.TokenCallFinalize(_size)
    if (self.tokenLists[PREFERRED_TOKEN_TYPE].tokenCount == 0 and \
        self.tokenLists[REGULAR_TOKEN_TYPE].tokenCount == 0):

        self.contractOwner = ZERO_ADDRESS
        selfdestruct(msg.sender)

    self.postStateTransition(xtrans)


@public
def destroyTokenCall():
    assert self.contractOwner == msg.sender
    assert self.tokenLists[PREFERRED_TOKEN_TYPE].tokenCount == 0 and self.tokenLists[REGULAR_TOKEN_TYPE].tokenCount == 0
    self.contractOwner = ZERO_ADDRESS

    selfdestruct(msg.sender)
