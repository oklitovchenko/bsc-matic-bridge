// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../openzeppelin-contracts/contracts/utils/Counters.sol";
import "../openzeppelin-contracts/contracts/access/Ownable.sol";

contract SimpleNFT is Ownable, ERC721  {
    using Counters for Counters.Counter;

    Counters.Counter private _id;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    receive() external payable {
        revert();
    }

    function mint(address to) public onlyOwner {
        _id.increment();
        _safeMint(to, _id.current());
    }

    function burn(uint256 tokenId) public {
        require(_exists(tokenId), "SimpleNFT: burn query for nonexistent token");
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "SimpleNFT: transfer caller is not owner nor approved"
        );
        _burn(tokenId);
    }
}