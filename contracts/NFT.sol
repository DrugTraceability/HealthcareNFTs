// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4; //Similar to hardhat's version

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract NFT is ERC721URIStorage {
    uint public tokenCount; 
    constructor() ERC721("DApp NFT", "DAPP"){} //The constructor of openzeppelin smart contract is used
    function mint(string memory _tokenURI) external returns(uint) { //tokenURI is the metadata of the NFT (IPFS hash)
        tokenCount ++;
        _safeMint(msg.sender, tokenCount);
        _setTokenURI(tokenCount, _tokenURI);
        return(tokenCount);
    }
}
