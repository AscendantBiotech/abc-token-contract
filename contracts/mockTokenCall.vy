
struct TokenApplication:
    tokenId: uint256
    dataSubmitted: bool
    userQualified: bool
    prevToken: uint256
    nextToken: uint256

struct TokenList:
    tokenTypeId: uint256
    firstToken: uint256
    tokenCount: uint256
    levels: map(uint256, TokenApplication)[6]


# External Contracts
contract ABC:
    def isNonFungible(_tokenId: uint256) -> bool: constant
    def isFungible(_tokenId: uint256) -> bool: constant
    def getNonFungibleIndex(_tokenId: uint256) -> uint256: constant
    def getNonFungibleBaseType(_tokenId: uint256) -> uint256: constant
    def isNonFungibleBaseType(_tokenId: uint256) -> bool: constant
    def isNonFungibleItem(_tokenId: uint256) -> bool: constant
    def ownerOf(_tokenId: uint256) -> address: constant
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
    def applyTokenCall(_tokenId: uint256): modifying
    def withdrawFromTokenCall(_tokenId: uint256): modifying
    def burnToken(_tokenId: uint256): modifying
    def owners(arg0: uint256) -> address: constant
    def tokenTypes__tokenTypeId(arg0: uint256) -> uint256: constant
    def tokenTypes__uri(arg0: uint256) -> string[256]: constant
    def tokenTypes__creator(arg0: uint256) -> address: constant
    def tokenTypes__mintedQty(arg0: uint256) -> uint256: constant
    def nfTokens__id(arg0: uint256) -> uint256: constant
    def nfTokens__owner(arg0: uint256) -> address: constant
    def nfTokens__tokenCall(arg0: uint256) -> address: constant
    def nonce() -> uint256: constant


CONTRACT_VERSION : constant(uint256) = 1000001  # Update this as behavior changes.

# keccak256("onRequestFromTokenCall()")
FROM_TOKEN_CALL: constant(bytes32) = 0x095332897a16faaf295be718bfc48721e7de9e87ff680ab2dd0179fb892881ea

BASE_TOKEN_ID: constant(uint256) = 0
DEEPEST_LEVEL: constant(int128) = 0
HOUR: constant(timedelta) = 3600

# ABC token
MAX_BATCH_SIZE: constant(uint256) = 100

# Contract configuration
MAX_TOKENS: constant(uint256) = 5000000
MAX_QUEUE_SIZE: constant(uint256) = 5000000 * 10
MAX_LEVEL: constant(int128) = 6
PROMOTION_CONSTANT: constant(int128) = 3  # promote probability = 2 ^ PROMOTION_CONSTANT 
UNPROMOTE_PROB: constant(int128) = (2 ** 3) - 1

PREFERRED_TOKEN_TYPE: constant(int128) = 0
REGULAR_TOKEN_TYPE: constant(int128) = 1


PENDING_STATE: constant(uint256) = 1
PAUSED_STATE: constant(uint256) = 2
OPEN_STATE: constant(uint256) = 3
CLOSED_STATE: constant(uint256) = 4

tokenContract: address

maxTokens: public(uint256)
maxPreferredTokens: public(uint256)

contractOwner: address
paused: public(bool)
startDate: public(timestamp)
endDate: public(timestamp)

tokenLists: public(TokenList[2])


@public
@constant
def contractVersion() -> uint256:
    return CONTRACT_VERSION


@public
@constant
def getDeepestLevel() -> int128:
    return DEEPEST_LEVEL


@private
@constant
def _getState() -> uint256:
    if block.timestamp < self.endDate:
        if self.paused:
            return PAUSED_STATE
        else:
            if block.timestamp < self.startDate:
                return PENDING_STATE
            return OPEN_STATE
    return CLOSED_STATE


@public
@constant
def getState() -> uint256:
    return self._getState()


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
def _getTokenTypeIndex(_tokenId: uint256) -> int128:
    tokenTypeId: uint256 = ABC(self.tokenContract).getNonFungibleBaseType(_tokenId)
    tokenTypeIndex: int128

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
                dataSubmitted: False,
                userQualified: False,
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
def removeToken(_tokenTypeIndex: int128, _tokenId: uint256):
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
                dataSubmitted: False,
                userQualified: False,
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


@public
@constant
def onRequestFromTokenCall() -> bytes32:
    return FROM_TOKEN_CALL


@public
@constant
def isOpen() -> bool:
    return block.timestamp >= self.startDate and block.timestamp < self.endDate


@public
def applyToken(_tokenId: uint256):
    assert self._getState() == OPEN_STATE

    tokenTypeId: uint256 = ABC(self.tokenContract).getNonFungibleBaseType(_tokenId)
    tokenTypeIndex: int128

    if tokenTypeId == self.tokenLists[PREFERRED_TOKEN_TYPE].tokenTypeId:
        tokenTypeIndex = PREFERRED_TOKEN_TYPE
    elif tokenTypeId == self.tokenLists[REGULAR_TOKEN_TYPE].tokenTypeId:
        tokenTypeIndex = REGULAR_TOKEN_TYPE
    else:
        assert False, 'Invalid token type!'

    ABC(self.tokenContract).applyTokenCall(_tokenId)

    self.insertToken(tokenTypeIndex, _tokenId, msg.sender)


@public
def withdrawToken(_tokenId: uint256):
    assert self._getState() == OPEN_STATE

    assert ABC(self.tokenContract).nfTokens__owner(_tokenId) == msg.sender, 'Wrong token owner'

    ABC(self.tokenContract).withdrawFromTokenCall(_tokenId)
    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)
    self.removeToken(tokenTypeIndex, _tokenId)


@public
def rejectToken(_tokenId: uint256):
    assert self.contractOwner == msg.sender

    state: uint256 = self._getState()
    assert state == OPEN_STATE or state == CLOSED_STATE

    ABC(self.tokenContract).withdrawFromTokenCall(_tokenId)
    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)
    self.removeToken(tokenTypeIndex, _tokenId)


@public
def pause():
    assert self.contractOwner == msg.sender
    assert self._getState() != CLOSED_STATE

    self.paused = True


@public
def unPause():
    assert self.contractOwner == msg.sender
    assert self._getState() == PAUSED_STATE

    self.paused = False


@public
def approveToken(_tokenId: uint256, _dataSubmitted: bool, _userQualified: bool):
    assert self.contractOwner == msg.sender
    state: uint256 = self._getState()
    assert state == OPEN_STATE or state == CLOSED_STATE


    tokenTypeIndex: int128 = self._getTokenTypeIndex(_tokenId)

    assert self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][_tokenId].tokenId != 0

    if _dataSubmitted:
        self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][_tokenId].dataSubmitted = _dataSubmitted

    if _userQualified:
        self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][_tokenId].userQualified = _userQualified


@public
def batchApproveTokens(_tokenIds: uint256[MAX_BATCH_SIZE], _dataSubmitted: bool[MAX_BATCH_SIZE], _userQualified: bool[MAX_BATCH_SIZE]):
    assert self.contractOwner == msg.sender
    state: uint256 = self._getState()
    assert state == OPEN_STATE or state == CLOSED_STATE

    for i in range(MAX_BATCH_SIZE):
        tokenId: uint256 = _tokenIds[i]
        if tokenId == 0:
            continue

        dataSubmitted: bool = _dataSubmitted[i]
        userQualified: bool = _userQualified[i]

        tokenTypeIndex: int128 = self._getTokenTypeIndex(tokenId)

        assert self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][tokenId].tokenId != 0

        if dataSubmitted:
            self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][tokenId].dataSubmitted = dataSubmitted

        if userQualified:
            self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][tokenId].userQualified = userQualified


@public
def finalize(_size: uint256):
    assert _size > 0, 'Op size must greater than zero'
    assert self.contractOwner == msg.sender, 'Caller is not contract owner'
    assert self._getState() == CLOSED_STATE

    opCounts: uint256[2]
    EapLimits: uint256[2] = [self.maxPreferredTokens, self.maxTokens]

    tokenId: uint256
    token: TokenApplication

    for tokenTypeIndex in [PREFERRED_TOKEN_TYPE, REGULAR_TOKEN_TYPE]:
        if self.tokenLists[tokenTypeIndex].tokenCount > 0:
            tokenId = self.tokenLists[tokenTypeIndex].firstToken
            for _ in range(MAX_BATCH_SIZE):
                if tokenId == 0 or opCounts[0] + opCounts[1] >= _size:
                    break

                token = self.tokenLists[tokenTypeIndex].levels[DEEPEST_LEVEL][tokenId]

                if (EapLimits[tokenTypeIndex] > 0 and token.dataSubmitted and token.userQualified):
                    if tokenTypeIndex == PREFERRED_TOKEN_TYPE:
                        EapLimits[REGULAR_TOKEN_TYPE] -= 1
                    EapLimits[tokenTypeIndex] -= 1

                    ABC(self.tokenContract).burnToken(tokenId)
                else:
                    ABC(self.tokenContract).withdrawFromTokenCall(tokenId)

                for level in range(MAX_LEVEL):
                    if token.tokenId != 0:
                        self.tokenLists[tokenTypeIndex].levels[level][token.nextToken].prevToken = 0
                        self.tokenLists[tokenTypeIndex].levels[level][tokenId] = TokenApplication({
                            tokenId: 0,
                            dataSubmitted: False,
                            userQualified: False,
                            prevToken: 0,
                            nextToken: 0,
                        })

                tokenId = token.nextToken
                opCounts[tokenTypeIndex] += 1

        self.tokenLists[tokenTypeIndex].firstToken = tokenId
        self.tokenLists[tokenTypeIndex].tokenCount -= opCounts[tokenTypeIndex]

    self.maxPreferredTokens = EapLimits[PREFERRED_TOKEN_TYPE]
    self.maxTokens = EapLimits[REGULAR_TOKEN_TYPE]

    if (self.tokenLists[PREFERRED_TOKEN_TYPE].tokenCount == 0 and \
        self.tokenLists[REGULAR_TOKEN_TYPE].tokenCount == 0):
        self.contractOwner = ZERO_ADDRESS
        selfdestruct(msg.sender)


@public
def destroyTokenCall():
    assert self.contractOwner == msg.sender
    assert self.tokenLists[PREFERRED_TOKEN_TYPE].tokenCount == 0 and self.tokenLists[REGULAR_TOKEN_TYPE].tokenCount == 0
    self.contractOwner = ZERO_ADDRESS

    selfdestruct(msg.sender)
