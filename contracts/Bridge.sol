// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "../openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import "../openzeppelin-contracts/contracts/access/Ownable.sol";
import "../openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import "./SimpleNFT.sol";

contract Bridge is Ownable, IERC721Receiver, ERC165 {
    SimpleNFT private _NFT;

    // member for store initiated swap transactions
    mapping(bytes32 => bool) private _swapInit;

    // member for store finished swap transactions
    mapping(bytes32 => bool) private _swapDone;

    // member for store validator address
    address private _validator;

    // member for store current chain ID
    // ==== only for test purposes ===
    // before deploy in production delete it and use block.chainid
    uint256 private _chainID;

    bool isOnERC721Received;

    // If this event is stored in BC it generates an obligation of
    // the Validator to perform the procedure for the transfer of
    // ownership of the token in the target network
    event Swap(
        address sender, // mean - from (address from source chain)
        address receiver, // mean - to (address in destination chain)
        uint256 tokenId,
        uint256 chainFrom,
        uint256 chainTo,
        bytes32 indexed nonce // keccak256 hash for abi.encode(from, to, tokenId, chainFrom, chainTo);
    );

    constructor(address payable nft, address v, uint256 cId /* delete it before deploy in production */) {
        _NFT = SimpleNFT(nft);
        _validator = v;
        _chainID = cId; // before deploy in production delete it for use block.chainid
    }

    receive() external payable {
        revert();
    }

    // Setter for change Validator address
    // Only owner of this contract can change Validator address
    function setValidator(address v) external onlyOwner {
        _validator = v;
    }

    // initSwap method as required in SOW for this test task
    function initSwap(
        address from,
        address to,
        uint256 tokenId,
        uint256 toChainID
    ) public {
        // prevent swap init tx inside one network
        require(toChainID != _chainID, "Bridge: destination chain is same current");
        bytes32 swapTxHash =
            keccak256(
                abi.encode(
                    from,
                    to,
                    tokenId,
                    _chainID, // before deploy in production delete it and use block.chainid
                    toChainID
                )
            );
        // prevent swap init duplicate tx
        require(!_swapInit[swapTxHash], "Bridge: swap has been initiated before");

        _swapDone[swapTxHash] = false;
        _swapInit[swapTxHash] = true;

        // lock token on bridge contract
        if (!isOnERC721Received)
            _NFT.safeTransferFrom(from, address(this), tokenId);

        // Use event to to store swap init tx in BC
        emit Swap(
            from,
            to,
            tokenId,
            _chainID,
            toChainID,
            swapTxHash
        );
    }

    // redeemSwap method as required in SOW for this test task
    function redeemSwap(
        address sender, // mean - from (address from source chain)
        address receiver, // mean - to (address in destination chain)
        uint256 tokenId,
        uint256 chainFrom,
        bytes32 nonce, // Ethereum Signed keccak256 hash of indexed nonce field from Swap event;
        bytes memory sig // eth.sig signature made only by validator
    ) public {
        // prevent swap redeem tx inside one network
        require(chainFrom != _chainID, "Bridge: destination chain is same current");

        // check if redeemSwap is a continuation of THE right initSwap
        bytes32 swapTxHash = keccak256(abi.encode(sender, receiver, tokenId, chainFrom, _chainID));
        require(swapTxHash == nonce, "Bridge: wrong swap transaction");

        // prevent swap redeem duplicate tx
        require(!_swapDone[swapTxHash], "Bridge: swap has been done before");

        // check if swap tx accepted by actual validator
        address signer = ECDSA.recover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", nonce)), sig);
        require(signer == _validator, "Bridge: invalid signature");

        _swapInit[swapTxHash] = false;
        _swapDone[swapTxHash] = true;

        // unlock token to send it to receiver
        _NFT.safeTransferFrom(address(this), receiver, tokenId);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external virtual override returns (bytes4) {
        // check if onERC721Received called by _NFT contract
        require(_msgSender() == address(_NFT));

        if (data.length == 0) return IERC721Receiver.onERC721Received.selector;

        // revert if data has wrong length
        require(data.length == 64, "Bridge: wrong swap request");

        // parse calldata to extract destination address in destination chain
        (address to, uint256 toChainID) = parseCallDataOnERC721Received(data);

        // check if data looks like valid to init swap
        require(to != address(0) && toChainID != 0);

        isOnERC721Received = true;
        initSwap(from, to, tokenId, toChainID);
        isOnERC721Received = false;

        return IERC721Receiver.onERC721Received.selector;
    }

    function validator() public view returns (address) {
        return _validator;
    }

    function chainID() public view returns (uint256) {
        return _chainID;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function parseCallDataOnERC721Received(bytes calldata data)
        public pure
        returns (address to, uint256 toChainID) {
        assembly {
            to := calldataload(add(data.offset, 32))
            toChainID := calldataload(data.offset)
        }
    }
}