################ Structs ################
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

struct Token:
    id: uint256
    owner: address
    tokenCall: address
    option: Option

################ Interfaces ################
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


# External Contracts
contract TokenCall:
    def onRequestFromTokenCall() -> bytes32: constant
    def getDeepestLevel() -> int128: constant
    def getTokenTypeIndex(_tokenId: uint256) -> int128: constant
    def tokenLists__levels__dataSubmitted(arg0: int128, arg1: int128, arg2: uint256) -> bool: constant
    def tokenLists__levels__userQualified(arg0: int128, arg1: int128, arg2: uint256) -> bool: constant

contract ERC20Currency:
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: modifying


################ Events ################
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

################ Constants ################
TYPE_MASK: constant(uint256) = shift(bitwise_not(0), 128)
NF_INDEX_MASK: constant(uint256) = shift(bitwise_not(0), -128)
TYPE_NF_BIT: constant(uint256) = shift(1, 255)

BYTE_SIZE: constant(uint256) = 1024
MAX_BATCH_SIZE: constant(uint256) = 100
MAX_URI_LENGTH: constant(uint256) = 256
HOUR: constant(timedelta) = 3600

# bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
ERC1155_ACCEPTED: constant(bytes[5]) = b'\xf2\x3a\x6e\x61'

# bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
ERC1155_BATCH_ACCEPTED: constant(bytes[5]) = b'\xbc\x19\x7c\x81'

# keccak256("onRequestFromTokenCall()")
FROM_TOKEN_CALL: constant(bytes32) = 0x095332897a16faaf295be718bfc48721e7de9e87ff680ab2dd0179fb892881ea


INTERFACE_SIGNATURE_ERC165: constant(bytes[5]) = b'\x01\xff\xc9\xa7'
INTERFACE_SIGNATURE_ERC1155: constant(bytes[5]) = b'\xd9\xb6\x7a\x26'

NFTSTATE_AVAILABLE: constant(uint256) = 1
NFTSTATE_EAP_APPLIED: constant(uint256) = 2
NFTSTATE_EAP_PROCESSING: constant(uint256) = 3
NFTSTATE_EAP_APPROVED: constant(uint256) = 4
NFTSTATE_OPTIONED: constant(uint256) = 5
NFTSTATE_BURNED: constant(uint256) = 6


################ Storages ################
balances: map(uint256, map(address, uint256))
owners: public(map(uint256, address))
tokenTypes: public(map(uint256, TokenType))
nfTokens: public(map(uint256, Token))
nonce: public(uint256)
maxIndex: map(uint256, uint256)
isApprovedForAll: public(map(address, map(address, bool)))
isApprovedToMintToken: public(map(uint256, map(address, bool)))
allowance: public(map(address, map(address, map(uint256, uint256))))
tokenCallApproval: map(address, map(uint256, address))

################ Functions ################
@public
@constant
def supportsInterface(_interfaceId: bytes[4]) -> bool:
    return _interfaceId == INTERFACE_SIGNATURE_ERC165 or _interfaceId == INTERFACE_SIGNATURE_ERC1155

@private
@constant
def _getNFTState(_tokenId: uint256) -> uint256:
    token: Token = self.nfTokens[_tokenId]
    if token.owner != ZERO_ADDRESS:
        if token.option.expires >= block.timestamp:
            return NFTSTATE_OPTIONED
        if token.tokenCall != ZERO_ADDRESS:
            deepestLevel: int128 = TokenCall(token.tokenCall).getDeepestLevel()
            if TokenCall(token.tokenCall).tokenLists__levels__dataSubmitted(
                   TokenCall(token.tokenCall).getTokenTypeIndex(_tokenId),
                   deepestLevel,
                   _tokenId
                ):
                if TokenCall(token.tokenCall).tokenLists__levels__userQualified(
                        TokenCall(token.tokenCall).getTokenTypeIndex(_tokenId),
                        deepestLevel,
                        _tokenId
                    ):
                    return NFTSTATE_EAP_APPROVED
                return NFTSTATE_EAP_PROCESSING
            return NFTSTATE_EAP_APPLIED
        return NFTSTATE_AVAILABLE
    return NFTSTATE_BURNED



@public
@constant
def getNFTState(_tokenId: uint256) -> uint256:
    return self._getNFTState(_tokenId)


@private
@constant
def _isNonFungible(_tokenId: uint256) -> bool:
    return bitwise_and(_tokenId, TYPE_NF_BIT) == TYPE_NF_BIT


@private
@constant
def _isFungible(_tokenId: uint256) -> bool:
    return bitwise_and(_tokenId, TYPE_NF_BIT) == 0


@private
@constant
def _getNonFungibleIndex(_tokenId: uint256) -> uint256:
    return bitwise_and(_tokenId, NF_INDEX_MASK)


@public
@constant
def getNonFungibleIndex(_tokenId: uint256) -> uint256:
    return self._getNonFungibleIndex(_tokenId)


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
    return (
        bitwise_and(_tokenId, TYPE_NF_BIT) == TYPE_NF_BIT and
        bitwise_and(_tokenId, NF_INDEX_MASK) == 0
    )


@public
@constant
def isNonFungibleBaseType(_tokenId: uint256) -> bool:
    return self._isNonFungibleBaseType(_tokenId)


@private
@constant
def _isNonFungibleItem(_tokenId: uint256) -> bool:
    return (
        bitwise_and(_tokenId, TYPE_NF_BIT) == TYPE_NF_BIT and
        bitwise_and(_tokenId, NF_INDEX_MASK) != 0
    )


@public
@constant
def isNonFungibleItem(_tokenId: uint256) -> bool:
    return self._isNonFungibleItem(_tokenId)


@private
@constant
def _ownerOf(_tokenId: uint256) -> address:
    return self.nfTokens[_tokenId].owner


@public
@constant
def ownerOf(_tokenId: uint256) -> address:
    return self._ownerOf(_tokenId)


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


@public
def safeTransferFrom(_from: address, _to: address, _tokenId: uint256, _value: uint256, _data: bytes[BYTE_SIZE]):
    assert _to != ZERO_ADDRESS
    fromSpender: bool = _from != msg.sender and not self.isApprovedForAll[_from][msg.sender]

    if self._isNonFungible(_tokenId):
        baseType: uint256 = self._getNonFungibleBaseType(_tokenId)

        assert self._getNFTState(_tokenId) == NFTSTATE_AVAILABLE

        assert self.nfTokens[_tokenId].owner == _from, "From addres is not owner of token"
        assert self.balances[baseType][_from] >= 1

        if fromSpender:
            assert self.allowance[_from][msg.sender][_tokenId] >= 1
            self.allowance[_from][msg.sender][_tokenId] = 0

        self.nfTokens[_tokenId].owner = _to

        self.balances[baseType][_from] = self.balances[baseType][_from] - 1
        self.balances[baseType][_to] = self.balances[baseType][_to] + 1
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
            baseType: uint256 = self._getNonFungibleBaseType(tokenId)

            assert self._getNFTState(tokenId) == NFTSTATE_AVAILABLE

            assert self.nfTokens[tokenId].owner == _from
            assert self.nfTokens[tokenId].tokenCall == ZERO_ADDRESS
            assert self.balances[baseType][_from] >= 1

            if fromSpender:
                assert self.allowance[_from][msg.sender][tokenId] >= 1
                self.allowance[_from][msg.sender][tokenId] = 0

            self.nfTokens[tokenId].owner = _to

            self.balances[baseType][_from] = self.balances[baseType][_from] - 1
            self.balances[baseType][_to] = self.balances[baseType][_to] + 1
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
@constant
def balanceOf(_owner: address, _tokenId: uint256) -> uint256:
    if self._isNonFungibleItem(_tokenId):
        if self.nfTokens[_tokenId].owner == _owner:
            return 1
        else:
            return 0
    else:
        return self.balances[_tokenId][_owner]


@public
@constant
def balanceOfBatch(_owners: address[MAX_BATCH_SIZE], _tokenIds: uint256[MAX_BATCH_SIZE]) -> uint256[MAX_BATCH_SIZE]:
    balances_: uint256[MAX_BATCH_SIZE]

    for i in range(MAX_BATCH_SIZE):
        owner: address = _owners[i]
        tokenId: uint256 = _tokenIds[i]

        if owner == ZERO_ADDRESS:
            continue

        if self._isNonFungibleItem(tokenId):
            if self.nfTokens[tokenId].owner == owner:
                balances_[i] = 1
            else:
                balances_[i] = 0
        else:
            balances_[i] = self.balances[tokenId][owner]

    return balances_


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
def mintNonFungibleToken(_tokenTypeId: uint256, _to: address[MAX_BATCH_SIZE], _indexes: uint256[MAX_BATCH_SIZE]):
    assert self._isNonFungible(_tokenTypeId)
    assert self.isApprovedToMintToken[_tokenTypeId][msg.sender]

    totalQty: uint256

    for i in range(MAX_BATCH_SIZE):
        to: address = _to[i]
        if to == ZERO_ADDRESS:
            continue  # Skip zero address and continue to next address

        tokenId: uint256 = bitwise_or(_tokenTypeId, _indexes[i])

        assert self.nfTokens[tokenId].owner == ZERO_ADDRESS

        self.nfTokens[tokenId] = Token({
            id: tokenId,
            owner: to,
            tokenCall: ZERO_ADDRESS,
            option: Option({
                currency: ZERO_ADDRESS,
                price: 0,
                buyer: ZERO_ADDRESS,
                expires: 0
            })
        })
        self.balances[_tokenTypeId][to] = self.balances[_tokenTypeId][to] + 1
        totalQty += 1

        log.TransferSingle(msg.sender, ZERO_ADDRESS, to, tokenId, 1)
        if to.is_contract:
            self._doSafeTransferAcceptanceCheck(msg.sender, msg.sender, to, tokenId, 1, '')

    if totalQty > 0:
        self.tokenTypes[_tokenTypeId].mintedQty  += totalQty


@public
def mintFungibleToken(_tokenId: uint256, _to: address[MAX_BATCH_SIZE], _quantities: uint256[MAX_BATCH_SIZE]):
    assert self._isFungible(_tokenId)
    tokenCreator: address = self.tokenTypes[_tokenId].creator
    assert tokenCreator == msg.sender or self.isApprovedForAll[tokenCreator][msg.sender] == True

    totalQty: uint256

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
def tokenCallApprove(_tokenCall: address, _tokenId: uint256):
    assert TokenCall(_tokenCall).onRequestFromTokenCall() == FROM_TOKEN_CALL
    tokenOwner: address = self.nfTokens[_tokenId].owner
    assert tokenOwner == msg.sender or self.isApprovedForAll[tokenOwner][msg.sender] == True
    assert self._getNFTState(_tokenId) == NFTSTATE_AVAILABLE

    self.tokenCallApproval[tokenOwner][_tokenId] = _tokenCall

    log.TokenCallApproval(msg.sender, tokenOwner, _tokenId, _tokenCall)


@public
def applyTokenCall(_tokenId: uint256):
    assert self.tokenCallApproval[self.nfTokens[_tokenId].owner][_tokenId] == msg.sender
    assert self._getNFTState(_tokenId) == NFTSTATE_AVAILABLE
    assert TokenCall(msg.sender).onRequestFromTokenCall() == FROM_TOKEN_CALL

    self.nfTokens[_tokenId].tokenCall = msg.sender
    log.ApplyTokenCall(_tokenId, msg.sender)


@public
def withdrawFromTokenCall(_tokenId: uint256):
    assert self.tokenCallApproval[self.nfTokens[_tokenId].owner][_tokenId] == msg.sender
    assert self.nfTokens[_tokenId].tokenCall == msg.sender
    assert TokenCall(msg.sender).onRequestFromTokenCall() == FROM_TOKEN_CALL
    NFTState: uint256 = self._getNFTState(_tokenId)
    assert NFTState == NFTSTATE_EAP_APPLIED or NFTState == NFTSTATE_EAP_PROCESSING or NFTState == NFTSTATE_EAP_APPROVED

    self.nfTokens[_tokenId].tokenCall = ZERO_ADDRESS
    log.WithdrawTokenCall(_tokenId, msg.sender)


@public
def burnToken(_tokenId: uint256):
    assert self.tokenCallApproval[self.nfTokens[_tokenId].owner][_tokenId] == msg.sender
    assert self.nfTokens[_tokenId].tokenCall == msg.sender
    assert TokenCall(msg.sender).onRequestFromTokenCall() == FROM_TOKEN_CALL
    assert self._getNFTState(_tokenId) == NFTSTATE_EAP_APPROVED

    log.TransferSingle(msg.sender, self.nfTokens[_tokenId].owner, ZERO_ADDRESS, _tokenId, 0)
    self.nfTokens[_tokenId].owner = ZERO_ADDRESS


@public
def sellToken(_tokenId: uint256, _price: uint256, _currency: address, _buyer: address):
    assert self.nfTokens[_tokenId].owner == msg.sender, 'Token can be sold only by owner' 
    assert _buyer != ZERO_ADDRESS, 'Buyer is not specified'
    assert _price >= 0, 'Price must be Non-negative'
    assert self._isNonFungible(_tokenId)
    assert self._getNFTState(_tokenId) == NFTSTATE_AVAILABLE

    expires: timestamp = block.timestamp + 10*24*HOUR
    self.nfTokens[_tokenId].option = Option({
        currency: _currency,
        price: _price,
        buyer: _buyer,
        expires: expires
    })
    log.SellToken(_tokenId, _buyer, _price, _currency, expires)


@public
@payable
def buyToken(_tokenId: uint256, _transferAmount: uint256):
    assert self._isNonFungible(_tokenId)
    assert self._getNFTState(_tokenId) == NFTSTATE_OPTIONED
    token: Token = self.nfTokens[_tokenId]
    assert token.option.buyer == msg.sender

    if token.option.currency == ZERO_ADDRESS:
        assert msg.value >= token.option.price, 'Transfer amount is not sufficient'
        send(token.owner, msg.value)
    else:
        assert token.option.price <= _transferAmount, 'Trasfer amount is not sufficient'
        ERC20Currency(token.option.currency).transferFrom(msg.sender, token.owner, _transferAmount)

    baseType: uint256 = self._getNonFungibleBaseType(_tokenId)
    self.balances[baseType][token.owner] = self.balances[baseType][token.owner] - 1
    self.balances[baseType][msg.sender] = self.balances[baseType][msg.sender] + 1

    log.BuyToken(_tokenId, token.owner, msg.sender)
    log.TransferSingle(msg.sender, token.owner, msg.sender, _tokenId, 1)

    self.nfTokens[_tokenId].owner = msg.sender
    self.nfTokens[_tokenId].option = Option({
        currency: ZERO_ADDRESS,
        price: 0,
        buyer: ZERO_ADDRESS,
        expires: 0
    })

