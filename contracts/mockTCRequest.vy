struct TokenApplication:
    tokenId: uint256
    dataSubmitted: bool
    userQualified: bool


struct TokenList:
    levels: map(uint256, TokenApplication)[1]


contract ABC:
    def applyTokenCall(_tokenId: uint256): modifying
    def withdrawFromTokenCall(_tokenId: uint256): modifying
    def burnToken(_tokenId: uint256): modifying


# keccak256("onRequestFromTokenCall()")
FROM_TOKEN_CALL: constant(bytes32) = 0x095332897a16faaf295be718bfc48721e7de9e87ff680ab2dd0179fb892881ea

fromTokenCall: bytes32
tokenContract: address
getDeepestLevel: public(int128)
tokenLists: public(TokenList[1])


@public
def __init__(_tokenContract: address):
    self.tokenContract = _tokenContract
    self.fromTokenCall = FROM_TOKEN_CALL
    self.getDeepestLevel = 0


@public
@constant
def onRequestFromTokenCall() -> bytes32:
    return self.fromTokenCall


@public
def changeFromTokenCallValue(newVal: bytes32):
    self.fromTokenCall = newVal


@public
def resetFromTokenCallValue():
    self.fromTokenCall = FROM_TOKEN_CALL

@public
@constant
def getTokenTypeIndex(_tokenId: uint256) -> int128:
    return 0


@public
def setTokenApproval(_tokenId: uint256, _dataSubmitted: bool, _userQualified: bool):
    assert self.tokenLists[0].levels[0][_tokenId].tokenId != 0
    self.tokenLists[0].levels[0][_tokenId].dataSubmitted = _dataSubmitted
    self.tokenLists[0].levels[0][_tokenId].userQualified = _userQualified


@public
def applyToken(_tokenId: uint256):
    ABC(self.tokenContract).applyTokenCall(_tokenId)
    self.tokenLists[0].levels[0][_tokenId] = TokenApplication({
        tokenId: _tokenId,
        dataSubmitted: False,
        userQualified: False
    })


@public
def withdrawToken(_tokenId: uint256):
    ABC(self.tokenContract).withdrawFromTokenCall(_tokenId)
    self.tokenLists[0].levels[0][_tokenId] = TokenApplication({
        tokenId: 0,
        dataSubmitted: False,
        userQualified: False
    })


@public
def burnToken(_tokenId: uint256):
    ABC(self.tokenContract).burnToken(_tokenId)
    self.tokenLists[0].levels[0][_tokenId] = TokenApplication({
        tokenId: 0,
        dataSubmitted: False,
        userQualified: False
    })

