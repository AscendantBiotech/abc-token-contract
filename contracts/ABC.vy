
################ CONSTANTS ################
TYPE_MASK: constant(uint256) = shift(bitwise_not(0), 128) # 1111111...0000000
NF_INDEX_MASK: constant(uint256) = shift(bitwise_not(0), -128) # 0000000....1111111
TYPE_NF_BIT: constant(uint256) = shift(1, 255) # 1000000...0000000

BYTE_SIZE: constant(uint256) = 1024
MAX_BATCH_SIZE: constant(uint256) = 100
MAX_URI_LENGTH: constant(uint256) = 256

# bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
ERC1155_ACCEPTED: constant(bytes[5]) = b'\xf2\x3a\x6e\x61'

# bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
ERC1155_BATCH_ACCEPTED: constant(bytes[5]) = b'\xbc\x19\x7c\x81'

INTERFACE_SIGNATURE_ERC165: constant(bytes[5]) = b'\x01\xff\xc9\xa7'
INTERFACE_SIGNATURE_ERC1155: constant(bytes[5]) = b'\xd9\xb6\x7a\x26'


################ STRUCTS #################
struct TokenType:
    tokenTypeId: uint256
    uri: string[256]
    creator: address
    mintedQty: uint256

struct Option:
    currency: address
    price: uint256
    buyer: address
    expires: timestamp


################ INTERFACES ################
contract ERC1155Receiver:
    def onERC1155Received(
        _operator: address,
        _from: address,
        _token_id: uint256,
        _value: uint256,
        _data: bytes[1024]
    ) -> bytes[4]: modifying
    def onERC1155BatchReceived(
        _operator: address,
        _from: address,
        _token_ids: uint256[100],
        _values: uint256[100],
        _data: bytes[1024]
    ) -> bytes[4]: modifying


################ EXTERNAL CONTRACTS ################
contract TokenCall:
    def applyToken(_tokenId: uint256): modifying
    def removeToken(_tokenId: uint256): modifying
    def onRequestFromTokenCall() -> bytes32: constant

contract NFTTokenService:
    def get_state(_tokenId: uint256) -> int128: constant
    def setOwner(_tokenId: uint256, _newOwner: address): modifying
    def tokens__owner(_tokenId: uint256) -> address: constant
    def tokens__tco__tokenCall(_tokenId: uint256) -> address: constant
    def tokens__tco__docsSubmitted(_tokenId: uint256) -> bool: constant
    def tokens__tco__userQualified(_tokenId: uint256) -> bool: constant
    def nextTid() -> uint256: constant
    def mintToken(_owner: address, _sender: address): modifying
    def applyToken(_tokenId: uint256, _tokenCall: address, _sender: address): modifying
    def removeToken(_tokenId: uint256, _sender: address): modifying
    def docsSubmitted(_tokenId: uint256, _sender: address): modifying
    def userQualified(_tokenId: uint256, _sender: address): modifying
    def userRejected(_tokenId: uint256, _sender: address): modifying
    def finalize(_tokenId: uint256, _sender: address): modifying
    def tokens__option__buyer(_tokenId: uint256) -> address: constant
    def tokens__option__currency(_tokenId: uint256) -> address: constant
    def tokens__option__price(_tokenId: uint256) -> uint256: constant
    def tokens__option__expires(_tokenId: uint256) -> timestamp: constant

contract ERC20Currency:
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: modifying


################ EVENTS ################
TransferSingle: event({
    _operator: indexed(address),
    _from: indexed(address),
    _to: indexed(address),
    _token_id: uint256,
    _value: uint256
})
TransferBatch: event({
    _operator: indexed(address),
    _from: indexed(address),
    _to: indexed(address),
    _token_ids: uint256[MAX_BATCH_SIZE],
    _value: uint256[MAX_BATCH_SIZE]
})
ApprovalForAll: event({_owner: indexed(address), _operator: indexed(address), _approved: bool})
Approval: event({_owner: indexed(address), _spender: indexed(address), _tokenId: indexed(uint256), _oldValue: uint256, _value: uint256})
TokenCallApproval: event({_operator: indexed(address), _owner: indexed(address), _tokenId: indexed(uint256), _tokenCall: address})
URI: event({_value: string[MAX_URI_LENGTH], _token_id: indexed(uint256)})
ApplyTokenCall: event({_tokenId: indexed(uint256), _tokenCall: address})
WithdrawTokenCall: event({_tokenId: indexed(uint256), _tokenCall: address})
SellToken: event({_tokenId: indexed(uint256), _buyer: address, _price: uint256, _currency: address, _expires: timestamp})
BuyToken: event({_tokenId: indexed(uint256), _from: address, _to: address})
TokenDocsSubmitted: event({_tokenId: indexed(uint256)})
TokenUserQualified: event({_tokenId: indexed(uint256)})
TokenUserRejected: event({_tokenId: indexed(uint256)})


################ STORAGES ################
balances: map(uint256, map(address, uint256))
tokenTypes: public(map(uint256, TokenType))
nonce: public(uint256)
isApprovedForAll: public(map(address, map(address, bool)))
isApprovedToMintToken: public(map(uint256, map(address, bool)))
allowance: public(map(address, map(address, map(uint256, uint256))))
tokenServices: public(map(uint256,address))


################ CONSTANT FUNCTIONS ################
@public
@constant
def supportsInterface(_interfaceId: bytes[4]) -> bool:
    return _interfaceId == INTERFACE_SIGNATURE_ERC165 or _interfaceId == INTERFACE_SIGNATURE_ERC1155


@private
@constant
def _isNonFungible(_tokenId: uint256) -> bool:
    return bitwise_and(_tokenId, TYPE_NF_BIT) == TYPE_NF_BIT


@private
@constant
def _getNonFungibleBaseType(_tokenId: uint256) -> uint256:
    return bitwise_and(_tokenId, TYPE_MASK)


@public
@constant
def getNonFungibleBaseType(_tokenId: uint256) -> uint256:
    return self._getNonFungibleBaseType(_tokenId)


@private
@constant
def _isNonFungibleBaseType(_tokenId: uint256) -> bool:
    return bitwise_and(_tokenId, TYPE_NF_BIT) == TYPE_NF_BIT and bitwise_and(_tokenId, NF_INDEX_MASK) == 0


@public
@constant
def isNonFungibleBaseType(_tokenId: uint256) -> bool:
    return self._isNonFungibleBaseType(_tokenId)


@private
@constant
def _isNonFungibleItem(_tokenId: uint256) -> bool:
    return bitwise_and(_tokenId, TYPE_NF_BIT) == TYPE_NF_BIT and bitwise_and(_tokenId, NF_INDEX_MASK) != 0


@public
@constant
def isNonFungibleItem(_tokenId: uint256) -> bool:
    return self._isNonFungibleItem(_tokenId)


@public
@constant
def getNFTState(_tokenId: uint256) -> int128:
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    return NFTTokenService(self.tokenServices[_tokenType]).get_state(_tokenId)


@public
@constant
def getNFTOwner(_tokenId: uint256) -> address:
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    return NFTTokenService(self.tokenServices[_tokenType]).tokens__owner(_tokenId)


@public
@constant
def getNFTTokenCall(_tokenId: uint256) -> address:
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    return NFTTokenService(self.tokenServices[_tokenType]).tokens__tco__tokenCall(_tokenId)


@public
@constant
def getNFTDataSubmitted(_tokenId: uint256) -> bool:
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    return NFTTokenService(self.tokenServices[_tokenType]).tokens__tco__docsSubmitted(_tokenId)


@public
@constant
def getNFTUserQualified(_tokenId: uint256) -> bool:
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    return NFTTokenService(self.tokenServices[_tokenType]).tokens__tco__userQualified(_tokenId)


@public
@constant
def getOptionExpireDate(_tokenId: uint256) -> timestamp:
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    return NFTTokenService(self.tokenServices[_tokenType]).tokens__option__expires(_tokenId)


@public
@constant
def balanceOf(_owner: address, _tokenId: uint256) -> uint256:
    if self._isNonFungibleItem(_tokenId):
        _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
        if NFTTokenService(self.tokenServices[_tokenType]).tokens__owner(_tokenId) == _owner:
            return 1
        else:
            return 0
    else:
        return self.balances[_tokenId][_owner]


@public
@constant
def balanceOfBatch(_owners: address[MAX_BATCH_SIZE], _tokenIds: uint256[MAX_BATCH_SIZE]) -> uint256[MAX_BATCH_SIZE]:
    # To be clearer with newer Vyper compiler releases
    balances_: uint256[MAX_BATCH_SIZE] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

    for i in range(MAX_BATCH_SIZE):
        owner: address = _owners[i]
        tokenId: uint256 = _tokenIds[i]

        if owner == ZERO_ADDRESS:
            continue

        if self._isNonFungibleItem(tokenId):
            _tokenType: uint256 = self._getNonFungibleBaseType(tokenId)
            if NFTTokenService(self.tokenServices[_tokenType]).tokens__owner(tokenId) == owner:
                balances_[i] = 1
            else:
                balances_[i] = 0
        else:
            balances_[i] = self.balances[tokenId][owner]

    return balances_


################ UTIL PRIVATE FUNCTIONS ################
@private
def _doSafeTransferAcceptanceCheck(
    _operator: address,
    _from: address,
    _to: address,
    _tokenId: uint256,
    _value: uint256,
    _data: bytes[BYTE_SIZE]
):
    tempCheckingBytes: bytes[4] = ERC1155Receiver(_to).onERC1155Received(_operator, _from, _tokenId, _value, _data)
    tempAccepted: bytes[4] = ERC1155_ACCEPTED

    checkingBytes: bytes[4] = tempCheckingBytes
    accepted: bytes[4] = tempAccepted

    assert checkingBytes == accepted


@private
def _doSafeBatchTransferAcceptanceCheck(
    _operator: address,
    _from: address,
    _to: address,
    _tokenIds: uint256[MAX_BATCH_SIZE],
    _values: uint256[MAX_BATCH_SIZE],
    _data: bytes[BYTE_SIZE]
):
    tempCheckingBytes: bytes[4] = ERC1155Receiver(_to).onERC1155BatchReceived(_operator, _from, _tokenIds, _values, _data)
    tempAccepted: bytes[4] = ERC1155_BATCH_ACCEPTED

    checkingBytes: bytes[4] = tempCheckingBytes
    accepted: bytes[4] = tempAccepted

    assert checkingBytes == accepted


################ PUBLIC FUNCTIONS ################
@public
def safeTransferFrom(_from: address, _to: address, _tokenId: uint256, _value: uint256, _data: bytes[BYTE_SIZE]):
    assert _to != ZERO_ADDRESS
    fromSpender: bool = _from != msg.sender and not self.isApprovedForAll[_from][msg.sender]

    if self._isNonFungible(_tokenId):
        _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)

        assert NFTTokenService(self.tokenServices[_tokenType]).tokens__owner(_tokenId) == _from
        assert NFTTokenService(self.tokenServices[_tokenType]).tokens__option__expires(_tokenId) < block.timestamp

        assert self.balances[_tokenType][_from] >= 1

        if fromSpender:
            assert self.allowance[_from][msg.sender][_tokenId] >= 1
            self.allowance[_from][msg.sender][_tokenId] = 0

        self.balances[_tokenType][_from] = self.balances[_tokenType][_from] - 1
        self.balances[_tokenType][_to] = self.balances[_tokenType][_to] + 1

        NFTTokenService(self.tokenServices[_tokenType]).setOwner(_tokenId, _to)
    else:
        assert self.balances[_tokenId][_from] >= _value
        if fromSpender:
            self.allowance[_from][msg.sender][_tokenId] = self.allowance[_from][msg.sender][_tokenId] - _value

        self.balances[_tokenId][_from] = self.balances[_tokenId][_from] - _value
        self.balances[_tokenId][_to] = self.balances[_tokenId][_to] + _value

    log.TransferSingle(msg.sender, _from, _to, _tokenId, _value)

    if _to.is_contract:
        self._doSafeTransferAcceptanceCheck(msg.sender, _from, _to, _tokenId, _value, _data)


@public
def safeBatchTransferFrom(
    _from: address,
    _to: address,
    _tokenIds: uint256[MAX_BATCH_SIZE],
    _values: uint256[MAX_BATCH_SIZE],
    _data: bytes[BYTE_SIZE]
):
    assert _to != ZERO_ADDRESS
    fromSpender: bool = _from != msg.sender and not self.isApprovedForAll[_from][msg.sender]

    for i in range(MAX_BATCH_SIZE):
        tokenId: uint256 = _tokenIds[i]
        value: uint256 = _values[i]

        if tokenId == 0:
            continue

        if self._isNonFungible(tokenId):
            _tokenType: uint256 = self._getNonFungibleBaseType(tokenId)

            assert NFTTokenService(self.tokenServices[_tokenType]).tokens__owner(tokenId) == _from
            assert NFTTokenService(self.tokenServices[_tokenType]).tokens__option__expires(tokenId) < block.timestamp

            assert self.balances[_tokenType][_from] >= 1

            if fromSpender:
                assert self.allowance[_from][msg.sender][tokenId] >= 1
                self.allowance[_from][msg.sender][tokenId] = 0

            NFTTokenService(self.tokenServices[_tokenType]).setOwner(tokenId, _to)

            self.balances[_tokenType][_from] = self.balances[_tokenType][_from] - 1
            self.balances[_tokenType][_to] = self.balances[_tokenType][_to] + 1
        else:
            assert self.balances[tokenId][_from] >= value

            if fromSpender:
                self.allowance[_from][msg.sender][tokenId] = self.allowance[_from][msg.sender][tokenId] - value

            self.balances[tokenId][_from] = self.balances[tokenId][_from] - value
            self.balances[tokenId][_to] = self.balances[tokenId][_to] + value

    log.TransferBatch(msg.sender, _from, _to, _tokenIds, _values)

    if _to.is_contract:
        self._doSafeBatchTransferAcceptanceCheck(msg.sender, _from, _to, _tokenIds, _values, _data)


@public
def setApprovalForAll(_operator: address, _approved: bool):
    self.isApprovedForAll[msg.sender][_operator] = _approved
    log.ApprovalForAll(msg.sender, _operator, _approved)


@public
def approve(_spender: address, _tokenId: uint256, _currentValue: uint256, _value: uint256):
    assert self.allowance[msg.sender][_spender][_tokenId] == _currentValue

    self.allowance[msg.sender][_spender][_tokenId] = _value

    log.Approval(msg.sender, _spender, _tokenId, _currentValue, _value)


@public
def createToken(_uri: string[MAX_URI_LENGTH], _isNonFungible: bool) -> uint256:
    newNonce: uint256 = self.nonce + 1
    self.nonce = newNonce

    tokenTypeId: uint256 = shift(newNonce, 128)

    if _isNonFungible:
        tokenTypeId = bitwise_or(tokenTypeId, TYPE_NF_BIT)

    self.tokenTypes[tokenTypeId] = TokenType({
        tokenTypeId: tokenTypeId,
        uri: _uri,
        creator: msg.sender,
        mintedQty: 0
    })

    # Transfer event with mint semantic
    log.TransferSingle(msg.sender, ZERO_ADDRESS, ZERO_ADDRESS, tokenTypeId, 0)

    if len(_uri) > 0:
        log.URI(_uri, tokenTypeId)

    return tokenTypeId


@public
def mintNonFungibleToken(_tokenTypeId: uint256, _to: address[MAX_BATCH_SIZE]):
    assert self._isNonFungible(_tokenTypeId)
    assert self.isApprovedToMintToken[_tokenTypeId][msg.sender]
    totalQty: uint256 = 0

    for i in range(MAX_BATCH_SIZE):
        to: address = _to[i]
        if to == ZERO_ADDRESS:
            continue  # Skip zero address and continue to next address

        tokenId: uint256 = NFTTokenService(self.tokenServices[_tokenTypeId]).nextTid()
        NFTTokenService(self.tokenServices[_tokenTypeId]).mintToken(to, msg.sender)

        self.balances[_tokenTypeId][to] = self.balances[_tokenTypeId][to] + 1
        totalQty += 1

        log.TransferSingle(msg.sender, ZERO_ADDRESS, to, tokenId, 1)
        if to.is_contract:
            self._doSafeTransferAcceptanceCheck(msg.sender, msg.sender, to, tokenId, 1, '')

    if totalQty > 0:
        self.tokenTypes[_tokenTypeId].mintedQty  += totalQty


@public
def mintFungibleToken(_tokenId: uint256, _to: address[MAX_BATCH_SIZE], _quantities: uint256[MAX_BATCH_SIZE]):
    assert not self._isNonFungible(_tokenId)
    tokenCreator: address = self.tokenTypes[_tokenId].creator
    assert tokenCreator == msg.sender or self.isApprovedForAll[tokenCreator][msg.sender] == True

    totalQty: uint256 = 0

    for i in range(MAX_BATCH_SIZE):
        to: address = _to[i]
        if to == ZERO_ADDRESS:
            continue  # Skip zero address and continue to next address

        quantity: uint256 = _quantities[i]

        self.balances[_tokenId][to] = self.balances[_tokenId][to] + quantity

        totalQty += quantity

        log.TransferSingle(msg.sender, ZERO_ADDRESS, to, _tokenId, quantity)

        if to.is_contract:
            self._doSafeTransferAcceptanceCheck(msg.sender, msg.sender, to, _tokenId, quantity, '')

    if totalQty > 0:
        self.tokenTypes[_tokenId].mintedQty  += totalQty


@public
def setURI(_uri: string[MAX_URI_LENGTH], _tokenTypeId: uint256):
    assert self.tokenTypes[_tokenTypeId].creator == msg.sender

    self.tokenTypes[_tokenTypeId].uri = _uri
    log.URI(_uri, _tokenTypeId)


@public
def setMintTokenApproval(_tokenTypeId: uint256, _auction: address, _approved: bool):
    tokenCreator: address = self.tokenTypes[_tokenTypeId].creator
    assert tokenCreator == msg.sender or self.isApprovedForAll[tokenCreator][msg.sender] == True

    self.isApprovedToMintToken[_tokenTypeId][_auction] = _approved


@public
def setTokenService(_tokenServiceAddr: address, _tokenTypeId: uint256):
    assert self._isNonFungible(_tokenTypeId)
    _tokenCreator: address = self.tokenTypes[_tokenTypeId].creator
    assert _tokenCreator == msg.sender or self.isApprovedForAll[_tokenCreator][msg.sender] == True

    self.tokenServices[_tokenTypeId] = _tokenServiceAddr


@public
def applyToken(_tokenId: uint256, _tokenCall: address):
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    NFTTokenService(self.tokenServices[_tokenType]).applyToken(_tokenId, _tokenCall, msg.sender)

    log.ApplyTokenCall(_tokenId, _tokenCall)


@public
def removeToken(_tokenId: uint256):
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    NFTTokenService(self.tokenServices[_tokenType]).removeToken(_tokenId, msg.sender)

    log.WithdrawTokenCall(_tokenId, msg.sender)


@public
def finalize(_tokenId: uint256):
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    _tokenOwner: address = NFTTokenService(self.tokenServices[_tokenType]).tokens__owner(_tokenId)
    NFTTokenService(self.tokenServices[_tokenType]).finalize(_tokenId, msg.sender)

    log.TransferSingle(msg.sender, _tokenOwner, ZERO_ADDRESS, _tokenId, 0)


@public
def docsSubmitted(_tokenId: uint256):
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    NFTTokenService(self.tokenServices[_tokenType]).docsSubmitted(_tokenId, msg.sender)
    log.TokenDocsSubmitted(_tokenId)


@public
def userQualified(_tokenId: uint256):
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    NFTTokenService(self.tokenServices[_tokenType]).userQualified(_tokenId, msg.sender)
    log.TokenUserQualified(_tokenId)


@public
def userRejected(_tokenId: uint256):
    _tokenType: uint256 = self._getNonFungibleBaseType(_tokenId)
    NFTTokenService(self.tokenServices[_tokenType]).userRejected(_tokenId, msg.sender)
    log.TokenUserRejected(_tokenId)


@public
def updateBalanceOnNFTTransfer(_tokenNonce: uint256, _tokenType: uint256, _from: address, _to: address):
    assert msg.sender == self.tokenServices[_tokenType]
    tokenId: uint256 = bitwise_or(_tokenType, _tokenNonce)

    self.balances[_tokenType][_from] = self.balances[_tokenType][_from] - 1
    self.balances[_tokenType][_to] = self.balances[_tokenType][_to] + 1

    log.TransferSingle(msg.sender, _from, _to, tokenId, 1)
