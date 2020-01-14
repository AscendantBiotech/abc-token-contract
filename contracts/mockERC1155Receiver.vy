
MAX_BATCH_SIZE: constant(uint256) = 100
BYTE_SIZE: constant(uint256) = 1024
ERC1155_ACCEPTED: constant(bytes[5]) = b'\xf2\x3a\x6e\x61'  # bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
ERC1155_BATCH_ACCEPTED: constant(bytes[5]) = b'\xbc\x19\x7c\x81'  # bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))

shouldReject: public(bool)
lastData: public(bytes[BYTE_SIZE])
lastOperator: public(address)
lastFrom: public(address)
lastId: public(uint256)
lastValue: public(uint256)


@public
def setShouldReject(_value: bool):
    self.shouldReject = _value


@public
def onERC1155Received(_operator: address, _from: address, _token_id: uint256, _value: uint256, _data: bytes[BYTE_SIZE]) -> bytes[4]:
    self.lastOperator = _operator
    self.lastFrom = _from
    self.lastId = _token_id
    self.lastValue = _value
    self.lastData = _data

    assert not self.shouldReject

    return ERC1155_ACCEPTED


@public
def onERC1155BatchReceived(_operator: address, _from: address, _token_ids: uint256[MAX_BATCH_SIZE], _values: uint256[MAX_BATCH_SIZE], _data: bytes[BYTE_SIZE]) -> bytes[4]:
    self.lastOperator = _operator
    self.lastFrom = _from
    self.lastId = _token_ids[0]
    self.lastValue = _values[0]
    self.lastData = _data

    assert not self.shouldReject

    return ERC1155_BATCH_ACCEPTED
